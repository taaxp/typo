import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The five fixed categories.
enum ItemKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case text, link, photo, gif, document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text Snippets"
        case .link: "Links"
        case .photo: "Photos"
        case .gif: "GIFs"
        case .document: "Documents"
        }
    }

    var shortTitle: String {
        switch self {
        case .text: "Text"
        case .link: "Links"
        case .photo: "Photos"
        case .gif: "GIFs"
        case .document: "Docs"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.quote"
        case .link: "link"
        case .photo: "photo"
        case .gif: "sparkles.rectangle.stack"
        case .document: "doc"
        }
    }

    /// Default colour (hex). Users can override per category in Settings.
    var defaultColorHex: String {
        switch self {
        case .text: "#5E7CE2"
        case .link: "#2BA6A0"
        case .photo: "#E58A2E"
        case .gif: "#C2489B"
        case .document: "#7A7F8C"
        }
    }

    /// Text and links can be typed straight into a text field by the keyboard.
    var isInsertableAsText: Bool { self == .text || self == .link }
}

/// One saved thing.
///
/// CloudKit-backed SwiftData rules apply: every stored property has a default or is
/// optional, there are no unique constraints, and relationships are optional.
@Model
final class StashItem {
    var uuid: UUID = UUID()
    var kindRaw: String = ItemKind.text.rawValue
    var title: String = ""
    /// Text snippets: the text. Links: the URL string.
    var text: String = ""
    /// Uniform type identifier of `payload` (photos, GIFs, documents).
    var typeIdentifier: String?
    var filename: String?
    /// Full file contents. Stored outside the SQLite file and synced as a CKAsset.
    @Attribute(.externalStorage) var payload: Data?
    /// Size of `payload`, so lists and the keyboard never load a file just to show its size.
    var byteCount: Int = 0
    /// Small JPEG preview (≤ 256 px) so the keyboard and lists never load full files.
    @Attribute(.externalStorage) var thumbnail: Data?

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isPinned: Bool = false
    /// Higher sorts first. New items get the current time, so they land on top.
    var sortIndex: Double = Date().timeIntervalSinceReferenceDate
    /// `false` while the item is in Recents.
    var isReviewed: Bool = false
    /// `true` once a link's page title has been fetched (or tried).
    var didFetchLinkTitle: Bool = false
    /// `true` if the user renamed it, so automatic titles never overwrite theirs.
    var hasCustomTitle: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Tag.items)
    var tags: [Tag]? = []

    init(kind: ItemKind, title: String = "", text: String = "") {
        self.kindRaw = kind.rawValue
        self.title = title
        self.text = text
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var url: URL? { kind == .link ? URL(string: text) : nil }

    var utType: UTType? { typeIdentifier.flatMap(UTType.init) }

    /// What to show in a list row.
    var displayTitle: String {
        if !title.isEmpty { return title }
        switch kind {
        case .text: return text.split(separator: "\n").first.map(String.init) ?? "Empty snippet"
        case .link: return url?.host() ?? text
        case .photo, .gif, .document: return filename ?? kind.title
        }
    }

    var sortedTags: [Tag] { (tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    /// Lower-cased haystack for search.
    var searchableText: String {
        ([title, text, filename ?? ""] + (tags ?? []).map(\.name)).joined(separator: " ")
    }

    func touch() { modifiedAt = Date() }
}

/// A user-defined, colour-coded tag.
@Model
final class Tag {
    var uuid: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var items: [StashItem]? = []

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    static let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
                          "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93"]
}
