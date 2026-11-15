import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var tags: [Tag]
    @AppStorage(AppGroup.Key.recentsAgeOutDays, store: AppGroup.defaults) private var ageOutDays = 3
    @State private var colourRevision = 0

    var body: some View {
        Form {
            Section("Category colours") {
                ForEach(ItemKind.allCases) { kind in
                    ColorPicker(selection: Binding(
                        get: { _ = colourRevision; return CategoryColours.color(for: kind) },
                        set: { CategoryColours.set($0, for: kind); colourRevision += 1 }
                    ), supportsOpacity: false) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                Button("Reset to Defaults") { CategoryColours.reset(); colourRevision += 1 }
            }

            Section {
                Stepper(value: $ageOutDays, in: 0...30) {
                    Text(ageOutDays == 0 ? "Tagged items stay in Recents" : "Tagged items leave Recents after \(ageOutDays) day\(ageOutDays == 1 ? "" : "s")")
                }
            } header: {
                Text("Recents")
            } footer: {
                Text("Untagged items stay in Recents until you review them.")
            }

            Section("Tags") {
                if tags.isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
                ForEach(tags) { tag in
                    TagSettingsRow(tag: tag)
                }
                .onDelete { offsets in
                    offsets.map { tags[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }

            #if os(iOS)
            Section {
                Text("""
                1. Open Settings › General › Keyboard › Keyboards › Add New Keyboard… › Stash.
                2. Tap Stash and turn on Allow Full Access. Stash needs it to read your library and to put photos, GIFs and files on the clipboard. The Stash keyboard doesn't connect to the internet and stores nothing you type.
                3. In any app, touch and hold the globe key and choose Stash.
                """)
                .font(.callout)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                }
            } header: {
                Text("Keyboard")
            }

            Section {
                Text("Add Stash to Control Centre or the Lock Screen: edit Control Centre or your Lock Screen and search for Stash. For the Action button: Settings › Action Button › Controls › Stash Quick Save.")
                    .font(.callout)
            } header: {
                Text("Control Centre, Lock Screen and Action button")
            }
            #endif

            Section {
                NavigationLink { SyncStatusView() } label: { Label("Sync Status", systemImage: "icloud") }
                LabeledContent("Apple Intelligence") {
                    switch TextPolisher.availability {
                    case .available: Text("Ready")
                    case .unavailable(let reason): Text(reason).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        #endif
    }
}

private struct TagSettingsRow: View {
    @Bindable var tag: Tag

    var body: some View {
        HStack {
            ColorPicker("", selection: Binding(
                get: { Color(hex: tag.colorHex) },
                set: { tag.colorHex = $0.hexString; tag.modifiedAt = Date() }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField("Name", text: $tag.name)
            Spacer()
            Text("\(tag.items?.count ?? 0)").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
