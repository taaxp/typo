import Foundation

/// What a QR code contains.
enum QRPayloadType: String, CaseIterable, Codable, Identifiable, Sendable {
    case link, text, wifi, contact, email, phone, sms, location, event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: "Link"
        case .text: "Text"
        case .wifi: "Wi-Fi"
        case .contact: "Contact"
        case .email: "Email"
        case .phone: "Phone"
        case .sms: "Message"
        case .location: "Location"
        case .event: "Event"
        }
    }

    var symbol: String {
        switch self {
        case .link: "link"
        case .text: "text.quote"
        case .wifi: "wifi"
        case .contact: "person.crop.circle"
        case .email: "envelope"
        case .phone: "phone"
        case .sms: "message"
        case .location: "mappin.and.ellipse"
        case .event: "calendar"
        }
    }

    var hueName: String {
        switch self {
        case .link: "Lagoon"
        case .text: "Ocean"
        case .wifi: "Sage"
        case .contact: "Dusk"
        case .email: "Mist"
        case .phone: "Amber"
        case .sms: "Blush"
        case .location: "Coral"
        case .event: "Plum"
        }
    }
}

struct WiFiNetwork: Codable, Equatable, Sendable {
    enum Security: String, Codable, CaseIterable, Sendable {
        case wpa = "WPA"      // WPA, WPA2 and WPA3 personal all use "WPA" in Wi-Fi QR codes
        case wep = "WEP"
        case open = "nopass"

        var title: String {
            switch self {
            case .wpa: "WPA2 / WPA3"
            case .wep: "WEP"
            case .open: "None"
            }
        }
    }

    var ssid: String
    var password: String
    var security: Security = .wpa
    var hidden: Bool = false
}

struct ContactCard: Codable, Equatable, Sendable {
    var givenName = ""
    var familyName = ""
    var organisation = ""
    var jobTitle = ""
    var phone = ""
    var email = ""
    var url = ""
    var address = ""

    var displayName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct CalendarEvent: Codable, Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var location = ""
}

/// A scanned or decoded code, classified.
enum ParsedCode: Equatable {
    case link(URL)
    case wifi(WiFiNetwork)
    case contact(vCard: String)
    case email(String)
    case phone(String)
    case sms(number: String, body: String)
    case location(latitude: Double, longitude: Double)
    case event(String)
    case text(String)
}

/// Builds and parses the text inside QR codes.
///
/// The Wi-Fi format has no formal specification. This follows the ZXing reference
/// that iOS and Android camera apps implement:
///   WIFI:T:<WPA|WEP|nopass>;S:<ssid>;P:<password>;H:<true|false>;;
/// with `\ ; , : "` escaped by a backslash (backslash first).
enum QRPayload {

    // MARK: Wi-Fi

    static let wifiSpecials: [Character] = ["\\", ";", ",", ":", "\""]

    static func escapeWiFi(_ value: String) -> String {
        var out = ""
        for ch in value {
            if wifiSpecials.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func wifi(_ network: WiFiNetwork) -> String {
        var s = "WIFI:T:\(network.security.rawValue);S:\(escapeWiFi(network.ssid));"
        if network.security != .open {
            s += "P:\(escapeWiFi(network.password));"
        }
        if network.hidden { s += "H:true;" }
        return s + ";"
    }

    static func parseWiFi(_ raw: String) -> WiFiNetwork? {
        guard raw.uppercased().hasPrefix("WIFI:") else { return nil }
        let body = raw.dropFirst(5)
        var fields: [String: String] = [:]
        var key = ""
        var value = ""
        var inKey = true
        var escaping = false
        for ch in body {
            if escaping {
                if inKey { key.append(ch) } else { value.append(ch) }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if inKey && ch == ":" {
                inKey = false
            } else if ch == ";" {
                if !key.isEmpty { fields[key.uppercased()] = value }
                key = ""; value = ""; inKey = true
            } else if inKey {
                key.append(ch)
            } else {
                value.append(ch)
            }
        }
        guard let ssid = fields["S"] else { return nil }
        let type = (fields["T"] ?? "").uppercased()
        let hasPassword = !(fields["P"] ?? "").isEmpty
        let security: WiFiNetwork.Security
        if type == "WEP" {
            security = .wep
        } else if type.hasPrefix("WPA") || type == "SAE" {
            security = .wpa
        } else {
            // "nopass", empty or unknown: treat as open unless a password is present.
            security = hasPassword ? .wpa : .open
        }
        return WiFiNetwork(ssid: ssid, password: fields["P"] ?? "", security: security,
                           hidden: fields["H"]?.lowercased() == "true")
    }

    // MARK: Contact (vCard 3.0)

    static func escapeVCard(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func contact(_ c: ContactCard) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0",
                     "N:\(escapeVCard(c.familyName));\(escapeVCard(c.givenName));;;",
                     "FN:\(escapeVCard(c.displayName))"]
        if !c.organisation.isEmpty { lines.append("ORG:\(escapeVCard(c.organisation))") }
        if !c.jobTitle.isEmpty { lines.append("TITLE:\(escapeVCard(c.jobTitle))") }
        if !c.phone.isEmpty { lines.append("TEL;TYPE=CELL:\(escapeVCard(c.phone))") }
        if !c.email.isEmpty { lines.append("EMAIL:\(escapeVCard(c.email))") }
        if !c.url.isEmpty { lines.append("URL:\(escapeVCard(c.url))") }
        if !c.address.isEmpty { lines.append("ADR;TYPE=WORK:;;\(escapeVCard(c.address));;;;") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    // MARK: Simple schemes

    static func email(to address: String, subject: String = "", body: String = "") -> String {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        var items: [URLQueryItem] = []
        if !subject.isEmpty { items.append(URLQueryItem(name: "subject", value: subject)) }
        if !body.isEmpty { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "mailto:\(address)"
    }

    static func phone(_ number: String) -> String {
        "tel:" + number.filter { $0.isNumber || $0 == "+" }
    }

    static func sms(to number: String, body: String = "") -> String {
        "SMSTO:" + number.filter { $0.isNumber || $0 == "+" } + ":" + body
    }

    static func location(latitude: Double, longitude: Double) -> String {
        String(format: "geo:%.6f,%.6f", latitude, longitude)
    }

    static func event(_ e: CalendarEvent) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var lines = ["BEGIN:VEVENT", "SUMMARY:\(escapeVCard(e.title))",
                     "DTSTART:\(f.string(from: e.start))", "DTEND:\(f.string(from: e.end))"]
        if !e.location.isEmpty { lines.append("LOCATION:\(escapeVCard(e.location))") }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\r\n")
    }

    // MARK: Parsing scanned codes

    static func parse(_ raw: String) -> ParsedCode {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        if let wifi = parseWiFi(trimmed) { return .wifi(wifi) }
        if upper.hasPrefix("BEGIN:VCARD") || upper.hasPrefix("MECARD:") { return .contact(vCard: trimmed) }
        if upper.hasPrefix("BEGIN:VEVENT") || upper.hasPrefix("BEGIN:VCALENDAR") { return .event(trimmed) }
        if upper.hasPrefix("MAILTO:") { return .email(String(trimmed.dropFirst(7)).components(separatedBy: "?")[0]) }
        if upper.hasPrefix("TEL:") { return .phone(String(trimmed.dropFirst(4))) }
        if upper.hasPrefix("SMSTO:") {
            let parts = trimmed.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            return .sms(number: parts.first ?? "", body: parts.count > 1 ? parts[1] : "")
        }
        if upper.hasPrefix("GEO:") {
            let coords = trimmed.dropFirst(4).split(separator: "?").first
                .map { $0.split(separator: ",").compactMap { Double($0) } } ?? []
            if coords.count >= 2 { return .location(latitude: coords[0], longitude: coords[1]) }
        }
        if let url = Ingest.singleWebURL(in: trimmed) { return .link(url) }
        return .text(trimmed)
    }
}
