import WidgetKit
import SwiftUI

/// Shows one saved code (for example the guest Wi-Fi QR) on the Home Screen and
/// in StandBy. The app renders the PNG into the App Group; see `WidgetSnapshot`.
struct CodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.starconnect.typo.code", provider: Provider()) { entry in
            CodeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
                .widgetURL(URL(string: "typo://codes"))
        }
        .configurationDisplayName("Typo Code")
        .description("Your guest Wi-Fi or another saved code, ready to scan. Choose which in Typo › Codes › Show on Widget.")
        // Lock Screen sizes are left out: tinted Lock Screen rendering can make QR codes unscannable.
        .supportedFamilies([.systemSmall, .systemLarge])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: WidgetSnapshot?
        let image: Data?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil, image: nil) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(load())
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            // The app calls reloadAllTimelines() whenever the chosen code changes.
            completion(Timeline(entries: [load()], policy: .never))
        }

        private func load() -> Entry {
            if let (snapshot, image) = WidgetSnapshot.load() {
                return Entry(date: .now, snapshot: snapshot, image: image)
            }
            return Entry(date: .now, snapshot: nil, image: nil)
        }
    }
}

private struct CodeWidgetView: View {
    let entry: CodeWidget.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let data = entry.image, let image = UIImage(data: data) {
            VStack(spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                if family == .systemLarge, let snapshot = entry.snapshot, !snapshot.caption.isEmpty {
                    Text(snapshot.caption).font(.headline).foregroundStyle(.black)
                }
            }
            // Full colour even in tinted Home Screen modes, so the code keeps its contrast.
            .widgetAccentable(false)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "qrcode").font(.largeTitle)
                Text("Choose a code in Typo").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}
