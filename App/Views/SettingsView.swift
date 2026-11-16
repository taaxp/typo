import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(filter: #Predicate<TypoItem> { $0.shortcut != "" }, sort: \TypoItem.shortcut) private var shortcuts: [TypoItem]
    @AppStorage(SpotlightSettings.key, store: AppGroup.defaults) private var spotlightOn = true
    #if os(iOS)
    @AppStorage(WatchSync.snippetsKey, store: AppGroup.defaults) private var watchSnippets = true
    #endif
    @AppStorage(AppGroup.Key.recentsAgeOutDays, store: AppGroup.defaults) private var ageOutDays = 3
    @State private var hueRevision = 0
    @AppStorage(SaveAssistant.autoApplyKey, store: AppGroup.defaults) private var autoApplySuggestions = false

    var body: some View {
        Form {
            Section {
                ForEach(ItemKind.allCases) { kind in
                    NavigationLink {
                        HueChooser(title: kind.title, selection: Binding(
                            get: { _ = hueRevision; return CategoryColours.hueName(for: kind) },
                            set: { CategoryColours.set($0, for: kind); model.hueSync.push(); hueRevision += 1 }))
                    } label: {
                        HStack(spacing: 12) {
                            HueTile(hue: CategoryColours.hue(for: kind), symbol: kind.symbol, size: 30)
                            Text(kind.title)
                            Spacer()
                            Text(CategoryColours.hueName(for: kind)).foregroundStyle(.secondary)
                        }
                    }
                    .id("\(kind.rawValue)-\(hueRevision)")
                }
                Button("Reset to Defaults") { CategoryColours.reset(); model.hueSync.push(); hueRevision += 1 }
            } header: {
                Text("Categories")
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
                    NavigationLink { TagEditor(tag: tag) } label: {
                        HStack(spacing: 12) {
                            HueDot(hue: tag.hue, size: 16)
                            Text(tag.name)
                            Spacer()
                            Text("\(tag.items?.count ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { tags[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }

            #if os(iOS)
            Section {
                Text("""
                1. Open Settings › General › Keyboard › Keyboards › Add New Keyboard… › Typo.
                2. Tap Typo and turn on Allow Full Access. Typo needs it to read your library and to put photos, GIFs and files on the clipboard. The Typo keyboard doesn't connect to the internet and stores nothing you type.
                3. In any app, touch and hold the globe key and choose Typo.
                """)
                .font(.callout)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                }
            } header: {
                Text("Keyboard")
            }

            Section {
                Text("Edit Control Centre or your Lock Screen and search for Typo. For the Action button: Settings › Action Button › Controls › Typo Quick Save.")
                    .font(.callout)
            } header: {
                Text("Control Centre, Lock Screen and Action button")
            }
            #endif

            Section {
                if shortcuts.isEmpty {
                    Text("No shortcuts yet. Open a snippet and give it a shortcut, such as ;addr.").foregroundStyle(.secondary)
                }
                ForEach(shortcuts) { item in
                    HStack {
                        Text(";" + item.shortcut).font(.body.monospaced().weight(.semibold))
                        Spacer()
                        Text(item.displayTitle).foregroundStyle(.secondary).lineLimit(1)
                        if item.isTemplate { Image(systemName: "curlybraces").foregroundStyle(Hues.named("Dusk").gradient) }
                    }
                }
            } header: {
                Text("Text expansion")
            } footer: {
                Text("Type a shortcut and a space with the Typo keyboard to insert the snippet. Templates can include {date}, {time}, {cursor} and fill-in fields such as {Name}. iOS doesn't let apps add to the system Text Replacements, so expansion works in the Typo keyboard only.")
            }

            Section {
                Toggle("Show Typo in Spotlight", isOn: $spotlightOn)
                    .onChange(of: spotlightOn) { _, _ in model.spotlight.rebuild() }
                Button("Rebuild Search Index") { model.spotlight.rebuild(); model.show("Rebuilding search index") }
            } header: {
                Text("Spotlight and Siri")
            } footer: {
                Text("Snippets, links, files, collections and code names appear in system search, and Siri can copy them (\"Copy my address from Typo\"). Bank cards, Wi-Fi passwords and clipboard history are never indexed.")
            }

            #if os(iOS)
            Section {
                Toggle("Send pinned snippets", isOn: $watchSnippets)
                    .onChange(of: watchSnippets) { _, _ in model.watch.schedule() }
                Text("To put a member card or guest Wi-Fi code on your watch, open Codes, touch and hold the code, and choose Show on Apple Watch.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Apple Watch")
            }
            #endif

            Section {
                Toggle("Apply suggestions automatically", isOn: $autoApplySuggestions)
            } header: {
                Text("Assistant")
            } footer: {
                Text("Apple Intelligence suggests tags, a collection and a summary for new saves, and Typo reads text in photos so you can search it. All on this device. When this is off, suggestions appear as dashed chips you can accept.")
            }

            #if os(macOS)
            MacSettingsSection()
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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        #endif
    }
}

/// Pick a named hue, with a live preview.
private struct HueChooser: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        HueTile(hue: Hues.named(selection), symbol: "sparkles", size: 72)
                        Text(selection).font(.title3.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            Section("Hues") { HuePicker(selection: $selection) }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

private struct TagEditor: View {
    @Bindable var tag: Tag

    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $tag.name) }
            Section {
                HStack { Spacer(); HueChip(title: tag.name.isEmpty ? "Tag" : tag.name, hue: tag.hue); Spacer() }
                    .padding(.vertical, 6)
            } header: { Text("Preview") }
            Section("Hue") {
                HuePicker(selection: Binding(get: { tag.hueName }, set: { tag.hueName = $0; tag.modifiedAt = Date() }))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tag.name)
    }
}
