import SwiftUI

/// Each category's hue. Users can pick any named hue in Settings; the choice is
/// shared with the keyboard through the App Group.
enum CategoryColours {
    private static func key(_ kind: ItemKind) -> String { "categoryHue.\(kind.rawValue)" }

    static func hueName(for kind: ItemKind) -> String {
        AppGroup.defaults.string(forKey: key(kind)) ?? kind.defaultHueName
    }

    static func hue(for kind: ItemKind) -> Hue { Hues.named(hueName(for: kind)) }

    /// Solid representative colour (icons, accessibility).
    static func color(for kind: ItemKind) -> Color { hue(for: kind).base }

    static func set(_ hueName: String, for kind: ItemKind) {
        AppGroup.defaults.set(hueName, forKey: key(kind))
    }

    static func reset() {
        ItemKind.allCases.forEach { AppGroup.defaults.removeObject(forKey: key($0)) }
    }
}
