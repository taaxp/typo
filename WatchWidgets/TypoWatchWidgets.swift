import WidgetKit
import SwiftUI
import AppIntents

@main
struct TypoWatchWidgets: WidgetBundle {
    var body: some Widget { CardComplication() }
}

/// Watch-face complication and Smart Stack widget that opens a chosen card.
struct CardComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.starconnect.typo.watch.card", intent: SelectCardIntent.self, provider: Provider()) { entry in
            CardComplicationView(entry: entry)
                .widgetURL(entry.card.map { URL(string: "typowatch://card/\($0.id.uuidString)")! })
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Typo Card")
        .description("Open a member card or guest Wi-Fi code in one tap.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let card: WatchCard?
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, card: WatchCard(id: UUID(), title: "Gym", kind: .member, hueName: "Amber",
                                              caption: "", imageFile: "", updatedAt: .now))
        }

        func snapshot(for configuration: SelectCardIntent, in context: Context) async -> Entry {
            Entry(date: .now, card: resolve(configuration))
        }

        func timeline(for configuration: SelectCardIntent, in context: Context) async -> Timeline<Entry> {
            Timeline(entries: [Entry(date: .now, card: resolve(configuration))], policy: .never)
        }

        private func resolve(_ configuration: SelectCardIntent) -> WatchCard? {
            let cards = WatchPack.loadLocal().cards
            if let id = configuration.card?.id { return cards.first { $0.id == id } }
            return cards.first
        }
    }
}

private struct CardComplicationView: View {
    let entry: CardComplication.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let symbol = entry.card?.symbol ?? "qrcode"
        let title = entry.card?.title ?? "Typo"
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol).font(.title3.weight(.semibold))
            }
            .accessibilityLabel(title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol).font(.headline).widgetAccentable()
                Text(entry.card == nil ? "Choose cards in Typo on iPhone" : "Tap to show").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .widgetLabel(title)
        default:
            Label(title, systemImage: symbol)
        }
    }
}

// MARK: - Configuration

struct SelectCardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Card"
    static let description = IntentDescription("The card this complication opens.")

    @Parameter(title: "Card")
    var card: WatchCardEntity?
}

struct WatchCardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static let defaultQuery = WatchCardQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WatchCardQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WatchCardEntity] {
        WatchPack.loadLocal().cards.filter { identifiers.contains($0.id) }.map { WatchCardEntity(id: $0.id, title: $0.title) }
    }

    func suggestedEntities() async throws -> [WatchCardEntity] {
        WatchPack.loadLocal().cards.map { WatchCardEntity(id: $0.id, title: $0.title) }
    }
}
