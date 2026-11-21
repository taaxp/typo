#if DEBUG
import Foundation
import SwiftData

/// Sample library for simulator screenshots and demos. Launch with
/// `-TypoDemoData YES`. Only inserts when the library is empty, and is compiled
/// out of release builds. Contains no real people's data.
@MainActor
enum DemoData {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "TypoDemoData") }

    /// `-TypoRoute codes|quicksave|dictate|vault|sync|newcode|newcollection` opens that
    /// screen at launch, so CI can screenshot it without tapping through a link prompt.
    static var requestedRoute: AppRoute? {
        UserDefaults.standard.string(forKey: "TypoRoute").flatMap(AppRoute.init(rawValue:))
    }

    /// `-TypoCollection YES` opens the first collection's board.
    static var wantsCollection: Bool { UserDefaults.standard.bool(forKey: "TypoCollection") }

    static func seedIfRequested(_ context: ModelContext) {
        guard isRequested, ((try? context.fetchCount(FetchDescriptor<TypoItem>())) ?? 0) == 0 else { return }
        let collections = CollectionLibrary(context: context)

        let work = Tag(name: "Work", hueName: "Mist")
        let recipes = Tag(name: "Recipes", hueName: "Sage")
        let design = Tag(name: "Design", hueName: "Dusk")
        [work, recipes, design].forEach(context.insert)

        func text(_ title: String, _ body: String, tags: [Tag] = [], pinned: Bool = false, shortcut: String = "", reviewed: Bool = false) -> TypoItem {
            let item = TypoItem(kind: .text, title: title, text: body)
            item.tags = tags; item.isPinned = pinned; item.shortcut = shortcut; item.isReviewed = reviewed
            item.hasCustomTitle = !title.isEmpty
            context.insert(item)
            return item
        }
        func link(_ title: String, _ url: String, tags: [Tag] = [], pinned: Bool = false) -> TypoItem {
            let item = TypoItem(kind: .link, title: title, text: url)
            item.tags = tags; item.isPinned = pinned; item.hasCustomTitle = true; item.didFetchLinkTitle = true
            context.insert(item)
            return item
        }

        _ = text("Out-of-office reply", "Thanks for getting in touch. I'm away until Monday 24 November and will reply when I'm back.", tags: [work])
        _ = link("Swift documentation", "https://www.swift.org/documentation/", pinned: true)
        _ = text("Parking", "Level 3, bay 42. Exit via Lift B.", pinned: true, reviewed: true)
        _ = text("Home address", "1 Example Street\nSouthbank VIC 3006", shortcut: "addr", reviewed: true)
        _ = text("Meeting follow-up", "Hi {Name},\n\nThanks for your time today, {day} {date}. As promised, here are my notes on {Topic}.\n\n{cursor}\n\nTalk soon", tags: [work], shortcut: "fu", reviewed: true)
        _ = link("Pasta e fagioli", "https://example.com/recipes/pasta-e-fagioli", tags: [recipes])

        let quote1 = text("Stanford, 2005", "Stay hungry. Stay foolish.", reviewed: true)
        let quote2 = text("", "Design is not just what it looks like and feels like. Design is how it works.", tags: [design], reviewed: true)
        let speech = link("Stanford commencement speech", "https://www.youtube.com/watch?v=example", tags: [design])
        let jobs = collections.create(name: "Steve Jobs", hueName: "Fog", icon: "lightbulb.fill")
        collections.add([speech, quote2, quote1], to: jobs)
        jobs.note = "Quotes, talks and reading."

        let wifi = CodeItem(title: "Guest Wi-Fi", kind: "qr", payloadType: QRPayloadType.wifi.rawValue,
                            payload: "", symbology: Symbology.qr.rawValue)
        var draft = CodeDraft()
        draft.type = .wifi
        draft.wifi = WiFiNetwork(ssid: "Lighthouse Guest", password: "")   // no password stored in demo data
        draft.wifi.security = .open
        draft.style = CodeStyle.presets[2].style
        draft.style.caption = "Scan for Wi-Fi"
        wifi.payload = draft.storedPayload()
        wifi.styleData = draft.style.encoded()
        wifi.hueName = "Sage"
        context.insert(wifi)

        let gym = CodeItem(title: "Gym membership", kind: "member", payloadType: QRPayloadType.text.rawValue,
                           payload: "{\"text\":\"4006381333931\"}", symbology: Symbology.ean13.rawValue)
        gym.hueName = "Amber"
        gym.styleData = CodeStyle(fillHue: nil, showFrame: false).encoded()
        context.insert(gym)

        try? context.save()
    }
}
#endif
