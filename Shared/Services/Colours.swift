import SwiftUI

extension Color {
    /// `#RRGGBB` → Color. Falls back to grey for bad input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    /// Color → `#RRGGBB` (sRGB).
    var hexString: String {
        let resolved = self.resolve(in: EnvironmentValues())
        let r = Int((max(0, min(1, resolved.red)) * 255).rounded())
        let g = Int((max(0, min(1, resolved.green)) * 255).rounded())
        let b = Int((max(0, min(1, resolved.blue)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// User-chosen category colours, shared with the keyboard through the App Group.
enum CategoryColours {
    private static func key(_ kind: ItemKind) -> String { "categoryColour.\(kind.rawValue)" }

    static func hex(for kind: ItemKind) -> String {
        AppGroup.defaults.string(forKey: key(kind)) ?? kind.defaultColorHex
    }

    static func color(for kind: ItemKind) -> Color { Color(hex: hex(for: kind)) }

    static func set(_ color: Color, for kind: ItemKind) {
        AppGroup.defaults.set(color.hexString, forKey: key(kind))
    }

    static func reset() {
        ItemKind.allCases.forEach { AppGroup.defaults.removeObject(forKey: key($0)) }
    }
}
