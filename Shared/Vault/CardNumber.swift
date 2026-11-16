import Foundation

/// Payment card helpers. Pure logic, unit-tested.
enum CardNumber {
    enum Network: String, Codable, CaseIterable, Sendable {
        case visa, mastercard, amex, eftpos, unionpay, jcb, diners, discover, unknown

        var title: String {
            switch self {
            case .visa: "Visa"
            case .mastercard: "Mastercard"
            case .amex: "American Express"
            case .eftpos: "eftpos"
            case .unionpay: "UnionPay"
            case .jcb: "JCB"
            case .diners: "Diners Club"
            case .discover: "Discover"
            case .unknown: "Card"
            }
        }
    }

    static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    /// Luhn (mod 10) check.
    static func isValid(_ input: String) -> Bool {
        let d = digits(input)
        guard (12...19).contains(d.count) else { return false }
        var sum = 0
        for (i, ch) in d.reversed().enumerated() {
            guard var n = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { n *= 2; if n > 9 { n -= 9 } }
            sum += n
        }
        return sum % 10 == 0
    }

    /// Best-effort network from the leading digits (IIN ranges). Australian
    /// eftpos-only cards can't be told apart reliably by number, so they show as
    /// "Card" unless the user picks eftpos.
    static func network(_ input: String) -> Network {
        let d = digits(input)
        func prefix(_ n: Int) -> Int { Int(d.prefix(n)) ?? -1 }
        if d.hasPrefix("4") { return .visa }
        if (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) { return .mastercard }
        if prefix(2) == 34 || prefix(2) == 37 { return .amex }
        if prefix(2) == 62 { return .unionpay }
        if (3528...3589).contains(prefix(4)) { return .jcb }
        if prefix(2) == 36 || (300...305).contains(prefix(3)) || prefix(2) == 38 { return .diners }
        if prefix(4) == 6011 || prefix(2) == 65 || (644...649).contains(prefix(3)) { return .discover }
        return .unknown
    }

    /// Groups digits for display: 4-4-4-4 (Amex 4-6-5).
    static func formatted(_ input: String) -> String {
        let d = Array(digits(input))
        let groups = network(input) == .amex ? [4, 6, 5] : [4, 4, 4, 4, 3]
        var out: [String] = []
        var i = 0
        for g in groups where i < d.count {
            out.append(String(d[i..<min(i + g, d.count)]))
            i += g
        }
        return out.joined(separator: " ")
    }

    /// "•••• 4821"
    static func masked(_ input: String) -> String {
        let d = digits(input)
        return "•••• " + String(d.suffix(4))
    }

    /// Accepts "MM/YY", "MM/YYYY", "MMYY"; returns "MM/YY" or nil.
    static func normalisedExpiry(_ input: String) -> String? {
        let d = digits(input)
        let mm: Int, yy: Int
        switch d.count {
        case 4: mm = Int(d.prefix(2)) ?? 0; yy = Int(d.suffix(2)) ?? -1
        case 6: mm = Int(d.prefix(2)) ?? 0; yy = (Int(d.suffix(4)) ?? -1) % 100
        default: return nil
        }
        guard (1...12).contains(mm), yy >= 0 else { return nil }
        return String(format: "%02d/%02d", mm, yy)
    }

    /// Finds a card number and expiry in OCR'd lines from a card photo.
    /// The longest digit run that passes Luhn wins. Security codes are never read.
    static func extract(fromLines lines: [String]) -> (number: String?, expiry: String?, name: String?) {
        var bestNumber: String?
        var expiry: String?
        var name: String?
        let expiryPattern = try? NSRegularExpression(pattern: #"\b(0[1-9]|1[0-2])\s?/\s?(\d{2}|\d{4})\b"#)
        for line in lines {
            let d = digits(line)
            if isValid(d), d.count > (bestNumber?.count ?? 0) { bestNumber = d }
            if expiry == nil, let regex = expiryPattern,
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                expiry = normalisedExpiry(String(line[range]))
            }
            let letters = line.trimmingCharacters(in: .whitespaces)
            if name == nil, letters.count >= 5, letters.count <= 26,
               letters.allSatisfy({ $0.isUppercase || $0 == " " || $0 == "." || $0 == "-" || $0 == "'" }),
               letters.contains(" "),
               !["VALID", "THRU", "DEBIT", "CREDIT", "VISA", "MASTERCARD", "BANK", "PLATINUM", "GOLD"].contains(where: letters.contains) {
                name = letters
            }
        }
        return (bestNumber, expiry, name)
    }
}
