import Foundation
import SwiftData

/// All collection changes go through here.
@MainActor
struct CollectionLibrary {
    let context: ModelContext

    func all() -> [TypoCollection] {
        (try? context.fetch(FetchDescriptor<TypoCollection>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func named(_ raw: String, create: Bool) -> TypoCollection? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = all().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        guard create else { return nil }
        return self.create(name: name)
    }

    @discardableResult
    func create(name: String, hueName: String? = nil, icon: String = "square.stack.3d.up.fill") -> TypoCollection {
        let rotation = ["Dusk", "Lagoon", "Coral", "Sage", "Plum", "Amber", "Ocean", "Blush"]
        let collection = TypoCollection(name: name, hueName: hueName ?? rotation[all().count % rotation.count], icon: icon)
        context.insert(collection)
        try? context.save()
        return collection
    }

    /// Adds items to the front of the collection's order.
    func add(_ items: [TypoItem], to collection: TypoCollection) {
        var order = ids(collection)
        for item in items where !(collection.items ?? []).contains(item) {
            collection.items = (collection.items ?? []) + [item]
            order.insert(item.uuid.uuidString, at: 0)
        }
        collection.orderedItemIDs = order.joined(separator: "\n")
        collection.modifiedAt = .now
        try? context.save()
    }

    func remove(_ items: [TypoItem], from collection: TypoCollection) {
        let removing = Set(items.map(\.uuid.uuidString))
        collection.items = (collection.items ?? []).filter { !removing.contains($0.uuid.uuidString) }
        collection.orderedItemIDs = ids(collection).filter { !removing.contains($0) }.joined(separator: "\n")
        if let cover = collection.coverItemUUID, removing.contains(cover) { collection.coverItemUUID = nil }
        collection.modifiedAt = .now
        try? context.save()
    }

    func toggle(_ item: TypoItem, in collection: TypoCollection) {
        if (collection.items ?? []).contains(item) { remove([item], from: collection) } else { add([item], to: collection) }
    }

    /// Items in display order: manual order first, then anything not yet ordered
    /// (e.g. added on another device) newest first.
    func orderedItems(_ collection: TypoCollection) -> [TypoItem] {
        let items = collection.items ?? []
        let order = ids(collection)
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.sorted { a, b in
            switch (position[a.uuid.uuidString], position[b.uuid.uuidString]) {
            case let (pa?, pb?): return pa < pb
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt > b.createdAt
            }
        }
    }

    func move(in collection: TypoCollection, from source: IndexSet, to destination: Int) {
        var items = orderedItems(collection)
        items.move(fromOffsets: source, toOffset: destination)
        collection.orderedItemIDs = items.map(\.uuid.uuidString).joined(separator: "\n")
        collection.modifiedAt = .now
        try? context.save()
    }

    func setCover(_ item: TypoItem?, for collection: TypoCollection) {
        collection.coverItemUUID = item?.uuid.uuidString
        try? context.save()
    }

    /// Items to show on the cover: the chosen cover first, then other visual items.
    func coverItems(_ collection: TypoCollection, limit: Int = 4) -> [TypoItem] {
        let items = orderedItems(collection)
        var visual = items.filter { $0.thumbnail != nil }
        if let cover = collection.coverItemUUID, let index = visual.firstIndex(where: { $0.uuid.uuidString == cover }) {
            visual.insert(visual.remove(at: index), at: 0)
        }
        return Array(visual.prefix(limit))
    }

    /// "3 quotes · 4 photos · 1 video · 2 links · 1 GIF"
    func summary(_ collection: TypoCollection) -> [(kind: ItemKind, count: Int)] {
        let items = collection.items ?? []
        return ItemKind.allCases.compactMap { kind in
            let n = items.filter { $0.kind == kind }.count
            return n > 0 ? (kind, n) : nil
        }
    }

    func delete(_ collection: TypoCollection) {
        // Items stay in the library; only the folder goes.
        context.delete(collection)
        try? context.save()
    }

    private func ids(_ collection: TypoCollection) -> [String] {
        collection.orderedItemIDs.split(separator: "\n").map(String.init)
    }
}

extension ItemKind {
    /// Counted noun for collection summaries.
    func counted(_ n: Int) -> String {
        let one: String, many: String
        switch self {
        case .text: (one, many) = ("quote or note", "quotes and notes")
        case .link: (one, many) = ("link", "links")
        case .photo: (one, many) = ("photo", "photos")
        case .gif: (one, many) = ("GIF", "GIFs")
        case .video: (one, many) = ("video", "videos")
        case .document: (one, many) = ("document", "documents")
        }
        return "\(n) \(n == 1 ? one : many)"
    }
}
