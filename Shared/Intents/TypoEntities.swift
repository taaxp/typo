import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// Whether Typo adds items to Spotlight (Settings › Spotlight). Default on.
enum SpotlightSettings {
    static let key = "spotlight.enabled"
    static var isEnabled: Bool { AppGroup.defaults.object(forKey: key) as? Bool ?? true }
}

// MARK: - Items

/// A library item for Siri, Shortcuts and Spotlight. Payment cards, Wi-Fi
/// passwords and clipboard history are never represented as entities.
struct TypoItemEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Typo Item"
    static let defaultQuery = TypoItemQuery()

    var id: UUID
    var title: String
    var kindTitle: String
    var preview: String
    var keywords: [String]
    var thumbnail: Data?

    var displayRepresentation: DisplayRepresentation {
        if let thumbnail {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(kindTitle)", image: .init(data: thumbnail))
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(kindTitle)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.contentDescription = preview
        attributes.keywords = keywords
        attributes.thumbnailData = thumbnail
        return attributes
    }

    var hideInSpotlight: Bool { !SpotlightSettings.isEnabled }

    /// Call on the main actor (the model context is main-actor bound).
    init(_ item: TypoItem) {
        id = item.uuid
        title = item.displayTitle
        kindTitle = item.kind.title
        switch item.kind {
        case .text: preview = String(item.text.prefix(300))
        case .link: preview = item.text
        default: preview = [item.summary, String(item.recognisedText.prefix(300))].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        keywords = (item.tags ?? []).map(\.name) + (item.collections ?? []).map(\.name)
            + (item.shortcut.isEmpty ? [] : [";" + item.shortcut])
        thumbnail = item.thumbnail
    }
}

struct TypoItemQuery: EntityStringQuery {
    @MainActor
    static func fetch(_ predicate: Predicate<TypoItem>? = nil, limit: Int? = nil) throws -> [TypoItem] {
        var descriptor = FetchDescriptor<TypoItem>(predicate: predicate, sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        descriptor.fetchLimit = limit
        return try SharedContainer.app().mainContext.fetch(descriptor)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TypoItemEntity] {
        try Self.fetch(#Predicate { identifiers.contains($0.uuid) }).map(TypoItemEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TypoItemEntity] {
        try Self.fetch().filter { $0.searchableText.localizedStandardContains(string) }.prefix(30).map(TypoItemEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TypoItemEntity] {
        // Pinned first, then recent: these feed the "Copy … from Typo" Siri phrases.
        let items = try Self.fetch(limit: 60)
        return (items.filter(\.isPinned) + items.filter { !$0.isPinned }).prefix(30).map(TypoItemEntity.init)
    }


}

// MARK: - Collections

struct CollectionEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Typo Collection"
    static let defaultQuery = CollectionQuery()

    var id: UUID
    var name: String
    var note: String
    var count: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(count) items", image: .init(systemName: "square.stack.3d.up.fill"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.contentDescription = note
        return attributes
    }

    var hideInSpotlight: Bool { !SpotlightSettings.isEnabled }

    init(_ c: TypoCollection) {
        id = c.uuid; name = c.name; note = c.note; count = c.count
    }
}

struct CollectionQuery: EntityStringQuery {
    @MainActor
    private func all() throws -> [TypoCollection] {
        try SharedContainer.app().mainContext.fetch(FetchDescriptor<TypoCollection>(sortBy: [SortDescriptor(\.name)]))
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CollectionEntity] {
        try all().filter { identifiers.contains($0.uuid) }.map(CollectionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CollectionEntity] {
        try all().filter { $0.name.localizedStandardContains(string) }.map(CollectionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CollectionEntity] { try all().map(CollectionEntity.init) }


}

// MARK: - Index

/// The named Spotlight index. Apple recommends a named index rather than the default.
enum SpotlightIndex {
    static let index = CSSearchableIndex(name: "Typo")

    /// Clears and rebuilds the whole index (first launch, Settings › Rebuild, and
    /// after deletions, since the library is small).
    @MainActor
    static func reindexAll() async throws {
        try await index.deleteAllSearchableItems()
        guard SpotlightSettings.isEnabled else { return }
        let context = try SharedContainer.app().mainContext
        let items = try context.fetch(FetchDescriptor<TypoItem>()).map(TypoItemEntity.init)
        let collections = try context.fetch(FetchDescriptor<TypoCollection>()).map(CollectionEntity.init)
        let codes = try context.fetch(FetchDescriptor<CodeItem>()).map { CodeEntity(id: $0.uuid, title: $0.title, isMember: $0.isMemberCard) }
        try await index.indexAppEntities(items)
        try await index.indexAppEntities(collections)
        try await index.indexAppEntities(codes)
        TypoShortcuts.updateAppShortcutParameters()
    }

    @MainActor
    static func update(_ items: [TypoItem]) async {
        guard SpotlightSettings.isEnabled, !items.isEmpty else { return }
        try? await index.indexAppEntities(items.map(TypoItemEntity.init))
    }
}

// MARK: - Opening from Spotlight, Siri and Shortcuts

/// Asks the app to open something. The app reads this on becoming active.
enum PendingOpen {
    static let key = "pendingOpen"

    static func request(_ value: String) {
        AppGroup.defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .typoPendingOpen, object: nil)
    }
}

extension Notification.Name {
    static let typoPendingOpen = Notification.Name("TypoPendingOpen")
}

struct OpenItemIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Item"

    @Parameter(title: "Item", requestValueDialog: "Which item?")
    var target: TypoItemEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingOpen.request("item:\(target.id.uuidString)")
        return .result()
    }
}

struct OpenCollectionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Collection"

    @Parameter(title: "Collection", requestValueDialog: "Which collection?")
    var target: CollectionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingOpen.request("collection:\(target.id.uuidString)")
        return .result()
    }
}

struct OpenCodeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Code"

    @Parameter(title: "Code", requestValueDialog: "Which code?")
    var target: CodeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(target.id.uuidString, forKey: AppGroup.Key.pendingCodeID)
        NotificationCenter.default.post(name: .typoPendingOpen, object: nil)
        return .result()
    }
}
