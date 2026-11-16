import Foundation

/// Editable content for a QR code or member card, used by the studio and editors.
/// Converts to the encoded message and to/from a stored `CodeItem`.
struct CodeDraft: Equatable, Sendable {
    var title = ""
    var type: QRPayloadType = .link
    var symbology: Symbology = .qr
    var isMember = false

    var text = ""                       // link, text, phone, member number
    var wifi = WiFiNetwork(ssid: "", password: "")
    var contact = ContactCard()
    var emailTo = "", emailSubject = "", emailBody = ""
    var smsNumber = "", smsBody = ""
    var latitude = "", longitude = ""
    var event = CalendarEvent(title: "", start: .now, end: .now.addingTimeInterval(3600))

    var style = CodeStyle.default

    /// The exact string encoded in the code.
    var message: String {
        if isMember { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch type {
        case .link, .text: return text
        case .wifi: return wifi.ssid.isEmpty ? "" : QRPayload.wifi(wifi)
        case .contact: return contact.displayName.isEmpty && contact.phone.isEmpty ? "" : QRPayload.contact(contact)
        case .email: return emailTo.isEmpty ? "" : QRPayload.email(to: emailTo, subject: emailSubject, body: emailBody)
        case .phone: return text.isEmpty ? "" : QRPayload.phone(text)
        case .sms: return smsNumber.isEmpty ? "" : QRPayload.sms(to: smsNumber, body: smsBody)
        case .location:
            guard let lat = Double(latitude), let lon = Double(longitude) else { return "" }
            return QRPayload.location(latitude: lat, longitude: lon)
        case .event: return event.title.isEmpty ? "" : QRPayload.event(event)
        }
    }

    var suggestedTitle: String {
        if !title.isEmpty { return title }
        switch type {
        case .wifi: return wifi.ssid.isEmpty ? "Guest Wi-Fi" : "Wi-Fi: \(wifi.ssid)"
        case .contact: return contact.displayName.isEmpty ? "Contact" : contact.displayName
        case .link: return URL(string: text)?.host() ?? "Link"
        case .event: return event.title.isEmpty ? "Event" : event.title
        default: return type.title
        }
    }

    // MARK: Storage

    /// Non-secret JSON stored in `CodeItem.payload`. The Wi-Fi password is left out.
    private struct Stored: Codable {
        var text: String?
        var wifi: WiFiNetwork?
        var contact: ContactCard?
        var email: [String]?
        var sms: [String]?
        var location: [String]?
        var event: CalendarEvent?
    }

    func storedPayload() -> String {
        var s = Stored()
        switch type {
        case .link, .text, .phone: s.text = text
        case .wifi: var w = wifi; w.password = ""; s.wifi = w
        case .contact: s.contact = contact
        case .email: s.email = [emailTo, emailSubject, emailBody]
        case .sms: s.sms = [smsNumber, smsBody]
        case .location: s.location = [latitude, longitude]
        case .event: s.event = event
        }
        if isMember { s = Stored(text: text) }
        let data = (try? JSONEncoder().encode(s)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    init() {}

    init(item: CodeItem, secret: String?) {
        title = item.title
        isMember = item.isMemberCard
        type = QRPayloadType(rawValue: item.payloadTypeRaw) ?? .text
        symbology = Symbology(rawValue: item.symbologyRaw) ?? .qr
        style = CodeStyle.decode(item.styleData)
        guard let data = item.payload.data(using: .utf8), let s = try? JSONDecoder().decode(Stored.self, from: data) else {
            text = item.payload
            return
        }
        text = s.text ?? ""
        if var w = s.wifi { w.password = secret ?? ""; wifi = w }
        if let c = s.contact { contact = c }
        if let e = s.email, e.count == 3 { emailTo = e[0]; emailSubject = e[1]; emailBody = e[2] }
        if let m = s.sms, m.count == 2 { smsNumber = m[0]; smsBody = m[1] }
        if let l = s.location, l.count == 2 { latitude = l[0]; longitude = l[1] }
        if let ev = s.event { event = ev }
    }

    /// The secret to keep in the Keychain, if this draft has one.
    var secret: String? { (type == .wifi && !isMember && wifi.security != .open) ? wifi.password : nil }
}
