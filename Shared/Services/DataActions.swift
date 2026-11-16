import Foundation

/// Quick actions found in text: open an address in Maps, call a number, open a
/// link, add a date to Calendar. Uses Apple's NSDataDetector (on-device, no AI).
struct DataAction: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case address(String)
        case phone(String)
        case link(URL)
        case date(Date)
    }

    let kind: Kind
    var id: String {
        switch kind {
        case .address(let a): "a:" + a
        case .phone(let p): "p:" + p
        case .link(let u): "l:" + u.absoluteString
        case .date(let d): "d:\(d.timeIntervalSince1970)"
        }
    }

    var title: String {
        switch kind {
        case .address(let a): a.replacingOccurrences(of: "\n", with: ", ")
        case .phone(let p): p
        case .link(let u): u.host() ?? u.absoluteString
        case .date(let d): d.formatted(date: .abbreviated, time: .shortened)
        }
    }

    var symbol: String {
        switch kind {
        case .address: "map"
        case .phone: "phone"
        case .link: "safari"
        case .date: "calendar.badge.plus"
        }
    }

    /// URL that performs the action (Maps, phone, browser). Dates use EventKit UI instead.
    var url: URL? {
        switch kind {
        case .address(let a):
            var c = URLComponents(string: "https://maps.apple.com/")
            c?.queryItems = [URLQueryItem(name: "q", value: a)]
            return c?.url
        case .phone(let p): return URL(string: "tel:" + p.filter { $0.isNumber || $0 == "+" })
        case .link(let u): return u
        case .date: return nil
        }
    }

    static func detect(in text: String, limit: Int = 6) -> [DataAction] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType([.address, .phoneNumber, .link, .date]).rawValue)
        else { return [] }
        var out: [DataAction] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let action: DataAction?
            switch match.resultType {
            case .address: action = Range(match.range, in: text).map { DataAction(kind: .address(String(text[$0]))) }
            case .phoneNumber: action = match.phoneNumber.map { DataAction(kind: .phone($0)) }
            case .link: action = match.url.flatMap { $0.scheme == "mailto" ? nil : DataAction(kind: .link($0)) }
            case .date: action = match.date.map { DataAction(kind: .date($0)) }
            default: action = nil
            }
            if let action, !out.contains(action) { out.append(action) }
            if out.count >= limit { break }
        }
        return out
    }
}
