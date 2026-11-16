import Foundation

/// One thing found by the scanner, routed to the right place.
struct ScanResult: Identifiable, Equatable {
    enum Kind: Equatable {
        case code(ParsedCode, raw: String, symbology: Symbology?)
        case text(String)
        case contact(ContactCard)
    }

    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
        case .code(let parsed, let raw, let symbology):
            switch parsed {
            case .link(let url): return url.host() ?? url.absoluteString
            case .wifi(let w): return "Wi-Fi: \(w.ssid)"
            case .contact: return "Contact card"
            case .email(let e): return e
            case .phone(let p): return p
            case .sms(let n, _): return "Message to \(n)"
            case .location: return "Location"
            case .event: return "Calendar event"
            case .text: return symbology.map { "\($0.title): \(raw)" } ?? raw
            }
        case .text(let t): return t
        case .contact(let c): return c.displayName.isEmpty ? "Business card" : c.displayName
        }
    }

    var symbol: String {
        switch kind {
        case .code(let parsed, _, let symbology):
            switch parsed {
            case .link: return "link"
            case .wifi: return "wifi"
            case .contact: return "person.crop.circle"
            case .email: return "envelope"
            case .phone: return "phone"
            case .sms: return "message"
            case .location: return "mappin.and.ellipse"
            case .event: return "calendar"
            case .text: return symbology?.isLinear == true ? "barcode" : "qrcode"
            }
        case .text: return "text.quote"
        case .contact: return "person.text.rectangle"
        }
    }

    /// Retail and membership barcodes can become member cards.
    var memberSymbology: Symbology? {
        if case .code(.text, _, let symbology) = kind, let symbology, symbology != .qr { return symbology }
        return nil
    }
}

/// Maps Vision/VisionKit symbology names to Typo's.
enum SymbologyMapper {
    static func from(visionName name: String) -> Symbology? {
        let n = name.lowercased()
        if n.contains("qr") { return .qr }
        if n.contains("aztec") { return .aztec }
        if n.contains("pdf417") { return .pdf417 }
        if n.contains("code128") { return .code128 }
        if n.contains("ean13") { return .ean13 }
        if n.contains("upce") { return nil }
        if n.contains("upca") || n.contains("upc") { return .upcA }
        return nil
    }
}

/// Builds a contact from lines of text recognised on a business card.
/// Phone, email, website and address come from NSDataDetector; the name,
/// title and company use simple heuristics (and on-device AI when available).
enum BusinessCardReader {
    static func contact(fromLines lines: [String]) -> ContactCard {
        var card = ContactCard()
        let joined = lines.joined(separator: "\n")
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            for match in detector.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
                switch match.resultType {
                case .phoneNumber where card.phone.isEmpty:
                    card.phone = match.phoneNumber ?? ""
                case .link:
                    if let url = match.url {
                        if url.scheme == "mailto" { if card.email.isEmpty { card.email = String(url.absoluteString.dropFirst(7)) } }
                        else if card.url.isEmpty { card.url = url.absoluteString }
                    }
                case .address where card.address.isEmpty:
                    if let range = Range(match.range, in: joined) { card.address = String(joined[range]).replacingOccurrences(of: "\n", with: ", ") }
                default: break
                }
            }
        }
        // Name: first short line of letters only, not an email/phone/URL.
        let candidates = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            !line.isEmpty && line.count <= 40 && !line.contains("@") && !line.contains("www") &&
            line.rangeOfCharacter(from: .decimalDigits) == nil
        }
        if let nameLine = candidates.first(where: { $0.split(separator: " ").count.isBetween(2, 4) && $0.first?.isUppercase == true }) {
            let parts = nameLine.split(separator: " ").map(String.init)
            card.givenName = parts.first ?? ""
            card.familyName = parts.dropFirst().joined(separator: " ")
            let rest = candidates.filter { $0 != nameLine }
            card.jobTitle = rest.first ?? ""
            card.organisation = rest.dropFirst().first ?? ""
        }
        return card
    }
}

private extension Int {
    func isBetween(_ low: Int, _ high: Int) -> Bool { self >= low && self <= high }
}
