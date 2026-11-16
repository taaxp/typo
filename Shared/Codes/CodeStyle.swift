import Foundation

/// How a code is decorated. Stored as JSON in `CodeItem.styleData`.
///
/// Scannability rules baked in:
/// - Dark modules always use a hue's deep end and its ink (never the pale top),
///   so contrast against the light background stays high.
/// - Backgrounds are white or a very pale tint; "clear" keeps a white plate behind
///   the modules in exports.
/// - The centre badge is capped at 20% of the code width and forces correction H.
struct CodeStyle: Codable, Equatable, Sendable {
    enum ModuleShape: String, Codable, CaseIterable, Sendable { case square, rounded, dots, fluid }
    enum EyeShape: String, Codable, CaseIterable, Sendable { case square, rounded, circle, leaf }
    enum Background: String, Codable, CaseIterable, Sendable { case white, soft, clear }

    enum Badge: Codable, Equatable, Sendable {
        case symbol(String)
        case emoji(String)
        case photo(Data)   // small JPEG, ≤ 256 px
    }

    var moduleShape: ModuleShape = .rounded
    var eyeShape: EyeShape = .rounded
    /// Hue name for the modules, or nil for plain near-black ink.
    var fillHue: String? = "Ocean"
    /// Hue name for the three finder "eyes", or nil to match the fill.
    var eyeHue: String? = nil
    var background: Background = .white
    var badge: Badge? = nil
    var showFrame: Bool = true
    var caption: String = ""

    static let plainInk = "#15161C"

    var correction: QRCorrection { badge == nil ? .medium : .high }

    static let `default` = CodeStyle()

    struct Preset: Identifiable, Sendable {
        let name: String
        let style: CodeStyle
        var id: String { name }
    }

    /// Named presets, each built on a hue.
    static let presets: [Preset] = [
        Preset(name: "Classic", style: CodeStyle(moduleShape: .square, eyeShape: .square, fillHue: nil, background: .white, showFrame: false)),
        Preset(name: "Ocean glass", style: CodeStyle(moduleShape: .rounded, eyeShape: .rounded, fillHue: "Ocean", eyeHue: "Dusk", background: .white)),
        Preset(name: "Sage card", style: CodeStyle(moduleShape: .dots, eyeShape: .leaf, fillHue: "Sage", background: .soft)),
        Preset(name: "Lagoon flow", style: CodeStyle(moduleShape: .fluid, eyeShape: .circle, fillHue: "Lagoon", background: .white)),
        Preset(name: "Dusk dots", style: CodeStyle(moduleShape: .dots, eyeShape: .circle, fillHue: "Dusk", eyeHue: "Plum", background: .soft)),
        Preset(name: "Coral pop", style: CodeStyle(moduleShape: .rounded, eyeShape: .leaf, fillHue: "Coral", eyeHue: "Amber", background: .white)),
    ]

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> CodeStyle { data.flatMap { try? JSONDecoder().decode(CodeStyle.self, from: $0) } ?? .default }
}
