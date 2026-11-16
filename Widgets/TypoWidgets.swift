import WidgetKit
import SwiftUI
import AppIntents

@main
struct TypoWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickSaveControl()
        QuickSaveLockScreenWidget()
        CodeWidget()
    }
}

/// Control Centre / Lock Screen control / Action button.
struct QuickSaveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.starconnect.typo.quicksave") {
            ControlWidgetButton(action: OpenQuickSaveIntent()) {
                Label("Typo Quick Save", systemImage: "tray.and.arrow.down")
            }
        }
        .displayName("Typo Quick Save")
        .description("Save what's on your clipboard to Typo and tag it.")
    }
}

/// Lock Screen accessory widget that opens Quick Save.
struct QuickSaveLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.starconnect.typo.lockscreen", provider: Provider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tray.and.arrow.down").font(.title3)
            }
            .widgetURL(AppRoute.quickSave.url)
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel("Typo Quick Save")
        }
        .configurationDisplayName("Quick Save")
        .description("Save your clipboard to Typo.")
        .supportedFamilies([.accessoryCircular])
    }

    struct Entry: TimelineEntry { let date: Date }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }
}
