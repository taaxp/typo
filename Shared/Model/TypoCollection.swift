import Foundation
import SwiftData

/// A folder of mixed items: quotes, photos, videos, links, GIFs, documents.
/// Example: "Steve Jobs" with his quotes, photos, a YouTube link to a speech,
/// an article and a GIF.
///
/// An item can belong to several collections. Manual order is kept as a list of
/// item UUIDs (CloudKit-safe), because SwiftData relationships are unordered.
@Model
final class TypoCollection {
    var uuid: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var hueName: String = "Dusk"
    /// SF Symbol name or a single emoji.
    var icon: String = "square.stack.3d.up.fill"
    /// UUID of the item used as the cover, if chosen.
    var coverItemUUID: String?
    var isPinned: Bool = false
    var sortIndex: Double = Date().timeIntervalSinceReferenceDate
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Newline-separated item UUIDs in display order.
    var orderedItemIDs: String = ""

    @Relationship(deleteRule: .nullify, inverse: \TypoItem.collections)
    var items: [TypoItem]? = []

    init(name: String, hueName: String = "Dusk", icon: String = "square.stack.3d.up.fill") {
        self.name = name
        self.hueName = hueName
        self.icon = icon
    }

    var hue: Hue { Hues.named(hueName) }
    var iconIsEmoji: Bool { icon.unicodeScalars.first?.properties.isEmojiPresentation == true }
    var count: Int { items?.count ?? 0 }
}
