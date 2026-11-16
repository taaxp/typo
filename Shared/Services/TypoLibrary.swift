import Foundation
import SwiftData
import AVFoundation
import ImageIO
#if canImport(LinkPresentation)
import LinkPresentation
#endif

extension Notification.Name {
    static let typoItemSaved = Notification.Name("TypoItemSaved")
    /// Edits, deletes, pins and collection changes (Spotlight, Apple Watch).
    static let typoLibraryChanged = Notification.Name("TypoLibraryChanged")
}

/// All writes to the library go through here so every input path behaves the same.
@MainActor
struct TypoLibrary {
    let context: ModelContext

    // MARK: Saving

    @discardableResult
    func save(_ draft: IngestDraft, tagNames: [String] = [], tags: [Tag] = []) -> TypoItem {
        let item = TypoItem(kind: draft.kind, title: draft.title, text: draft.text)
        item.payload = draft.payload
        item.byteCount = draft.payload?.count ?? 0
        item.typeIdentifier = draft.typeIdentifier
        item.filename = draft.filename
        item.hasCustomTitle = !draft.title.isEmpty
        if let data = draft.payload, draft.kind == .photo || draft.kind == .gif {
            item.thumbnail = Ingest.thumbnail(for: data)
        }
        if draft.kind == .video, draft.payload != nil {
            Task { await makeVideoThumbnail(for: item) }
        }
        context.insert(item)
        let resolved = tags + tagNames.compactMap { tag(named: $0, create: true) }
        item.tags = Array(Set(resolved))
        try? context.save()
        if item.kind == .link { Task { await fetchLinkTitle(for: item) } }
        // The app's assistant (OCR, QR detection, AI suggestions) listens for this.
        NotificationCenter.default.post(name: .typoItemSaved, object: item.persistentModelID)
        return item
    }

    func save(_ drafts: [IngestDraft], tags: [Tag] = []) -> [TypoItem] {
        drafts.map { save($0, tags: tags) }
    }

    // MARK: Inbox (written by the share extension)

    /// Imports everything extensions have dropped in the App Group inbox.
    @discardableResult
    func importInbox() -> Int {
        var count = 0
        for entry in Inbox.pending() {
            let m = entry.manifest
            let draft = IngestDraft(kind: m.kind, title: m.title, text: m.text, payload: entry.payload,
                                    typeIdentifier: m.typeIdentifier, filename: m.filename)
            let item = save(draft, tagNames: m.tagNames)
            item.createdAt = m.createdAt
            let collections = CollectionLibrary(context: context)
            for name in m.collectionNames ?? [] {
                if let collection = collections.named(name, create: true) { collections.add([item], to: collection) }
            }
            try? FileManager.default.removeItem(at: entry.folder)
            count += 1
        }
        if count > 0 { try? context.save() }
        return count
    }

    // MARK: Tags

    func allTags() -> [Tag] {
        (try? context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func tag(named raw: String, create: Bool) -> Tag? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = allTags().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        guard create else { return nil }
        let hue = Hues.tagRotation[allTags().count % Hues.tagRotation.count]
        let tag = Tag(name: name, hueName: hue)
        context.insert(tag)
        return tag
    }

    // MARK: Recents

    /// Marks items as reviewed so they leave Recents.
    func markReviewed(_ items: [TypoItem]) {
        items.forEach { $0.isReviewed = true }
        try? context.save()
    }

    /// Tagged items leave Recents on their own after the configured number of days.
    func ageOutRecents() {
        let days = AppGroup.defaults.object(forKey: AppGroup.Key.recentsAgeOutDays) as? Int ?? 3
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<TypoItem>(predicate: #Predicate { !$0.isReviewed && $0.createdAt < cutoff })
        let stale = (try? context.fetch(descriptor)) ?? []
        let tagged = stale.filter { !($0.tags ?? []).isEmpty }
        if !tagged.isEmpty { markReviewed(tagged) }
    }

    // MARK: Ordering

    /// Applies a drag-to-reorder within `ordered` (the list as currently displayed).
    func move(_ ordered: [TypoItem], from source: IndexSet, to destination: Int) {
        var items = ordered
        items.move(fromOffsets: source, toOffset: destination)
        // Re-spread sort indexes so the visible order is kept. Highest first.
        let top = (items.map(\.sortIndex).max() ?? Date().timeIntervalSinceReferenceDate) + 1
        for (offset, item) in items.enumerated() {
            item.sortIndex = top - Double(offset)
        }
        try? context.save()
    }

    // MARK: Links

    /// Fills in a link's title and preview image (e.g. a YouTube thumbnail) from
    /// the page. A title the user set is never overwritten.
    func fetchLinkTitle(for item: TypoItem) async {
        #if canImport(LinkPresentation)
        guard item.kind == .link, !item.didFetchLinkTitle, let url = item.url else { return }
        item.didFetchLinkTitle = true
        let provider = LPMetadataProvider()
        provider.timeout = 10
        if let metadata = try? await provider.startFetchingMetadata(for: url) {
            if let title = metadata.title, !title.isEmpty, !item.hasCustomTitle {
                item.title = title
            }
            if item.thumbnail == nil, let imageProvider = metadata.imageProvider,
               let data = try? await Self.loadImageData(imageProvider) {
                item.thumbnail = Ingest.thumbnail(for: data, maxPixel: 600)
            }
            item.touch()
        }
        try? context.save()
        #endif
    }

    private static func loadImageData(_ provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            _ = provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                if let data { cont.resume(returning: data) } else { cont.resume(throwing: error ?? IngestError.nothingUsable) }
            }
        }
    }

    // MARK: Video

    /// A poster frame for saved videos, from about one second in.
    func makeVideoThumbnail(for item: TypoItem) async {
        guard let url = TempFiles.url(for: item) else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else { return }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }
        item.thumbnail = out as Data
        try? context.save()
    }

    func fetchMissingLinkTitles() async {
        let linkRaw = ItemKind.link.rawValue
        let descriptor = FetchDescriptor<TypoItem>(predicate: #Predicate { $0.kindRaw == linkRaw && !$0.didFetchLinkTitle })
        for item in (try? context.fetch(descriptor)) ?? [] {
            await fetchLinkTitle(for: item)
        }
    }

    // MARK: Editing

    func rename(_ item: TypoItem, to title: String) {
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.hasCustomTitle = !item.title.isEmpty
        item.touch()
        try? context.save()
        Self.notifyChanged()
    }

    func togglePin(_ item: TypoItem) {
        item.isPinned.toggle()
        item.touch()
        try? context.save()
        Self.notifyChanged()
    }

    func delete(_ items: [TypoItem]) {
        items.forEach(context.delete)
        try? context.save()
        Self.notifyChanged()
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: .typoLibraryChanged, object: nil)
    }
}
