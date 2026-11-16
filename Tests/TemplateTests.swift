import Testing
import Foundation
@testable import Typo

@Suite("Templates and text expansion")
struct TemplateTests {
    private let melbourne = TimeZone(identifier: "Australia/Melbourne")!

    private var sampleDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 16; c.hour = 14; c.minute = 30
        c.timeZone = melbourne
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test func findsFieldsInOrderWithoutDuplicatesOrBuiltIns() {
        let fields = Template.fields(in: "Hi {Name}, your {Item=order} ships {date}. Thanks {name}!{cursor}")
        #expect(fields.map(\.name) == ["Name", "Item"])
        #expect(fields[1].defaultValue == "order")
    }

    @Test func clipboardIsAFieldUnlessReadable() {
        #expect(Template.fields(in: "Paste: {clipboard}").map(\.name) == ["Clipboard"])
        #expect(Template.fields(in: "Paste: {clipboard}", clipboardReadable: true).isEmpty)
    }

    @Test func rendersAustralianDatesAndTimes() {
        let r = Template.render("{date} · {shortdate} · {time} · {day}", now: sampleDate, timeZone: melbourne)
        #expect(r.text == "16 November 2026 · 16/11/2026 · 2:30 pm · Monday")
    }

    @Test func usesValuesThenDefaults() {
        let source = "Hi {Name=there}, about {Topic}."
        #expect(Template.render(source).text == "Hi there, about .")
        #expect(Template.render(source, values: ["name": "Sam", "Topic": "Friday"]).text == "Hi Sam, about Friday.")
    }

    @Test func cursorOffsetCountsFromTheEnd() {
        let r = Template.render("Dear {cursor},\nRegards")
        #expect(r.text == "Dear ,\nRegards")
        #expect(r.cursorOffsetFromEnd == 9)
        #expect(Template.render("No cursor").cursorOffsetFromEnd == 0)
    }

    @Test func doubledBracesAreLiteralAndJunkIsKept() {
        #expect(Template.render("{{literal}} and { \"json\": 1 }").text == "{literal} and { \"json\": 1 }")
        #expect(!Template.isTemplate("plain text"))
        #expect(Template.isTemplate("Hi {Name}"))
    }

    // MARK: Expansion

    @Test func expandsAtWordStartFollowedByDelimiter() {
        let shortcuts: Set<String> = ["addr", "sig"]
        #expect(TextExpander.match(contextBefore: "Send it to ;addr ", shortcuts: shortcuts)
                == .init(shortcut: "addr", deleteCount: 6, delimiter: " "))
        #expect(TextExpander.match(contextBefore: ";sig.", shortcuts: shortcuts)?.delimiter == ".")
        #expect(TextExpander.match(contextBefore: ";ADDR\n", shortcuts: shortcuts)?.shortcut == "addr")
    }

    @Test func doesNotExpandInsideWordsOrUnknownShortcuts() {
        let shortcuts: Set<String> = ["addr"]
        #expect(TextExpander.match(contextBefore: "x;addr ", shortcuts: shortcuts) == nil)
        #expect(TextExpander.match(contextBefore: ";nope ", shortcuts: shortcuts) == nil)
        #expect(TextExpander.match(contextBefore: ";addr", shortcuts: shortcuts) == nil)   // no delimiter yet
    }

    @Test func suggestsWhileTyping() {
        let result = TextExpander.suggestions(contextBefore: "hello ;ad", shortcuts: ["addr", "admin", "sig"])
        #expect(result?.typed == "ad")
        #expect(result?.matches == ["addr", "admin"])
    }

    @Test func normalisesShortcuts() {
        #expect(TextExpander.normalise(";My Addr!") == "myaddr")
    }
}

@Suite("Apple Watch pack")
struct WatchPackTests {
    @Test func roundTripsAndCapsSnippets() {
        let card = WatchCard(id: UUID(), title: "Gym", kind: .member, hueName: "Amber", caption: "4006381333931",
                             imageFile: "card.png", updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let snippets = (0..<40).map { WatchSnippet(id: UUID(), title: "S\($0)", text: "t", hueName: "Ocean") }
        let pack = WatchPack(cards: [card], snippets: snippets, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(pack.snippets.count == WatchPack.maxSnippets)
        #expect(WatchPack.decode(pack.encoded()) == pack)
        #expect(card.symbol == "barcode")
    }

    @Test func imageFileChangesWithVersion() {
        let id = UUID()
        #expect(WatchPack.imageFile(for: id, updatedAt: Date(timeIntervalSince1970: 1))
                != WatchPack.imageFile(for: id, updatedAt: Date(timeIntervalSince1970: 2)))
    }
}
