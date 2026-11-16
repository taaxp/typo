import Foundation

/// A fill-in field in a template, e.g. `{Name}` or `{Name=Alex}`.
struct TemplateField: Hashable, Identifiable, Sendable {
    let name: String
    let defaultValue: String
    var id: String { name.lowercased() }
}

/// Snippet templates.
///
/// Placeholders:
/// - `{date}` 16 November 2026, `{shortdate}` 16/11/2026, `{time}` 2:30 pm, `{day}` Monday
/// - `{cursor}` where the cursor lands after inserting
/// - `{clipboard}` the clipboard text, where it can be read without a prompt (Mac);
///   elsewhere it becomes a fill-in field with a Paste button
/// - `{Anything}` or `{Anything=default}` a fill-in field
/// - `{{` and `}}` for literal braces
enum Template {
    static let builtIns: Set<String> = ["date", "shortdate", "time", "day", "cursor", "clipboard"]

    enum Token: Equatable {
        case text(String)
        case placeholder(name: String, defaultValue: String)
    }

    /// Splits a template into literal text and placeholders. Anything that isn't a
    /// well-formed placeholder is kept as literal text.
    static func tokens(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        var i = source.startIndex
        func flush() { if !literal.isEmpty { tokens.append(.text(literal)); literal = "" } }

        while i < source.endIndex {
            let ch = source[i]
            let next = source.index(after: i)
            if ch == "{", next < source.endIndex, source[next] == "{" {
                literal.append("{"); i = source.index(after: next); continue
            }
            if ch == "}", next < source.endIndex, source[next] == "}" {
                literal.append("}"); i = source.index(after: next); continue
            }
            if ch == "{", let close = source[next...].firstIndex(of: "}") {
                let inner = String(source[next..<close])
                if let placeholder = parsePlaceholder(inner) {
                    flush()
                    tokens.append(placeholder)
                    i = source.index(after: close)
                    continue
                }
            }
            literal.append(ch)
            i = next
        }
        flush()
        return tokens
    }

    private static func parsePlaceholder(_ inner: String) -> Token? {
        let parts = inner.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 30,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" }) else { return nil }
        let defaultValue = parts.count > 1 ? String(parts[1]) : ""
        return .placeholder(name: name, defaultValue: defaultValue)
    }

    static func isTemplate(_ source: String) -> Bool {
        tokens(source).contains { if case .placeholder = $0 { return true }; return false }
    }

    /// Fill-in fields, in order of first appearance, without duplicates.
    /// `{clipboard}` is included as a field unless the clipboard can be read silently.
    static func fields(in source: String, clipboardReadable: Bool = false) -> [TemplateField] {
        var seen = Set<String>()
        var out: [TemplateField] = []
        for token in tokens(source) {
            guard case .placeholder(let name, let defaultValue) = token else { continue }
            let key = name.lowercased()
            if builtIns.contains(key) && !(key == "clipboard" && !clipboardReadable) { continue }
            if seen.insert(key).inserted {
                out.append(TemplateField(name: key == "clipboard" ? "Clipboard" : name, defaultValue: defaultValue))
            }
        }
        return out
    }

    struct Rendered: Equatable {
        let text: String
        /// Characters from the end of `text` back to `{cursor}` (0 = end).
        let cursorOffsetFromEnd: Int
    }

    /// Renders a template. `values` are keyed by field name (case-insensitive).
    static func render(_ source: String, values: [String: String] = [:], now: Date = Date(),
                       clipboard: String? = nil, timeZone: TimeZone = .current) -> Rendered {
        let lowered = Dictionary(values.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var text = ""
        var cursorIndex: Int?
        for token in tokens(source) {
            switch token {
            case .text(let t):
                text += t
            case .placeholder(let name, let defaultValue):
                let key = name.lowercased()
                switch key {
                case "date": text += format(now, "d MMMM yyyy", timeZone)
                case "shortdate": text += format(now, "dd/MM/yyyy", timeZone)
                case "time": text += format(now, "h:mm a", timeZone)
                case "day": text += format(now, "EEEE", timeZone)
                case "cursor": cursorIndex = text.count
                case "clipboard": text += lowered["clipboard"] ?? clipboard ?? defaultValue
                default:
                    let value = lowered[key] ?? ""
                    text += value.isEmpty ? defaultValue : value
                }
            }
        }
        let offset = cursorIndex.map { text.count - $0 } ?? 0
        return Rendered(text: text, cursorOffsetFromEnd: offset)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.timeZone = timeZone
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date)
    }

    /// Chips shown in the editor for quick insertion.
    static let helpChips: [(label: String, insert: String)] = [
        ("Field", "{Name}"), ("Date", "{date}"), ("Short date", "{shortdate}"),
        ("Time", "{time}"), ("Day", "{day}"), ("Cursor", "{cursor}"), ("Clipboard", "{clipboard}"),
    ]
}

/// Typo's own text expansion: type `;addr` then a space or punctuation with the
/// Typo keyboard and the matching snippet replaces it.
enum TextExpander {
    static let trigger: Character = ";"
    static let delimiters: Set<Character> = [" ", "\n", ".", ",", "!", "?", ":", ")"]

    struct Match: Equatable {
        let shortcut: String
        /// Characters to delete before inserting: trigger + shortcut + delimiter.
        let deleteCount: Int
        let delimiter: Character
    }

    /// Lower-case, without the trigger, letters/digits/_/- only.
    static func normalise(_ raw: String) -> String {
        String(raw.lowercased().drop { $0 == trigger || $0 == " " }.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    }

    static func match(contextBefore: String, shortcuts: Set<String>) -> Match? {
        guard let delimiter = contextBefore.last, delimiters.contains(delimiter) else { return nil }
        let body = contextBefore.dropLast()
        guard let triggerIndex = body.lastIndex(of: trigger) else { return nil }
        let abbreviation = body[body.index(after: triggerIndex)...]
        guard !abbreviation.isEmpty,
              abbreviation.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        // The trigger must start a word: "a;b " is not an expansion.
        if triggerIndex > body.startIndex {
            let before = body[body.index(before: triggerIndex)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let key = abbreviation.lowercased()
        guard shortcuts.contains(key) else { return nil }
        return Match(shortcut: key, deleteCount: abbreviation.count + 2, delimiter: delimiter)
    }

    /// Shortcuts starting with what's typed after `;` (for the suggestion strip).
    static func suggestions(contextBefore: String, shortcuts: [String], limit: Int = 5) -> (typed: String, matches: [String])? {
        guard let triggerIndex = contextBefore.lastIndex(of: trigger) else { return nil }
        let typed = contextBefore[contextBefore.index(after: triggerIndex)...]
        guard typed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        if triggerIndex > contextBefore.startIndex {
            let before = contextBefore[contextBefore.index(before: triggerIndex)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let prefix = typed.lowercased()
        let matches = shortcuts.filter { $0.hasPrefix(prefix) }.sorted().prefix(limit)
        return matches.isEmpty ? nil : (String(typed), Array(matches))
    }
}
