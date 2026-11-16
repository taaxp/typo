import Foundation
import SwiftData

/// A saved QR code or member card.
///
/// Secrets (Wi-Fi passwords) are never stored here: `secretRef` names a Keychain
/// item instead. Only raw values are stored so the keyboard and share extension
/// can compile the schema without the code-drawing files.
@Model
final class CodeItem {
    var uuid: UUID = UUID()
    var title: String = ""
    /// "qr" or "member".
    var kindRaw: String = "qr"
    /// `QRPayloadType` raw value (QR codes only).
    var payloadTypeRaw: String = "link"
    /// Non-secret content as JSON or plain text, depending on the payload type.
    var payload: String = ""
    /// Keychain account holding the secret part, e.g. a Wi-Fi password.
    var secretRef: String?
    /// `Symbology` raw value.
    var symbologyRaw: String = "qr"
    var styleData: Data?
    var hueName: String = "Lagoon"
    var isPinned: Bool = false
    var sortIndex: Double = Date().timeIntervalSinceReferenceDate
    var showOnWidget: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(title: String, kind: String, payloadType: String, payload: String, symbology: String) {
        self.title = title
        self.kindRaw = kind
        self.payloadTypeRaw = payloadType
        self.payload = payload
        self.symbologyRaw = symbology
    }

    var isMemberCard: Bool { kindRaw == "member" }
}
