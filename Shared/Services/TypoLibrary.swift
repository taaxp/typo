import Foundation
import SwiftData
#if canImport(LinkPresentation)
import LinkPresentation
#endif

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
        context.insert(item)
        let resolved = tags + tagNames.compactMap { tag(named: $0, create: true) }
        item.tags = Array(Set(resolved))
        try? context.save()
        if item.kind == .link { Task { await fetchLinkTitle(for: item) } }
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

    /// Fills in a link's title from the page, unless the user has renamed it.
    func fetchLinkTitle(for item: TypoItem) async {
        #if canImport(LinkPresentation)
        guard item.kind == .link, !item.hasCustomTitle, !item.didFetchLinkTitle, let url = item.url else { return }
        item.didFetchLinkTitle = true
        let provider = LPMetadataProvider()
        provider.timeout = 10
        if let metadata = try? await provider.startFetchingMetadata(for: url),
           let title = metadata.title, !title.isEmpty, !item.hasCustomTitle {
            item.title = title
            item.touch()
        }
        try? context.save()
        #endif
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
    }

    func togglePin(_ item: TypoItem) {
        item.isPinned.toggle()
        item.touch()
        try? context.save()
    }

    func delete(_ items: [TypoItem]) {
        items.forEach(context.delete)
        try? context.save()
    }
}
