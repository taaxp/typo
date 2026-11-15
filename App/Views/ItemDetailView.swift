import SwiftUI
import SwiftData
import QuickLook

/// Rename, edit text, tag, polish and preview one item.
struct ItemDetailView: View {
    @Bindable var item: StashItem
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var polishing = false

    private var library: StashLibrary { StashLibrary(context: context) }

    var body: some View {
        Form {
            Section("Name") {
                TextField(item.displayTitle, text: $item.title)
                    .onChange(of: item.title) { _, new in item.hasCustomTitle = !new.isEmpty }
            }

            switch item.kind {
            case .text:
                Section("Text") {
                    TextEditor(text: $item.text).frame(minHeight: 140)
                    if TextPolisher.isAvailable {
                        Menu {
                            ForEach(PolishStyle.allCases) { style in
                                Button(style.title, systemImage: style.symbol) { Task { await polish(style) } }
                            }
                        } label: {
                            Label(polishing ? "Polishing…" : "Polish with Apple Intelligence", systemImage: "wand.and.stars")
                        }
                        .disabled(polishing)
                    }
                }
            case .link:
                Section("Link") {
                    TextField("URL", text: $item.text)
                        #if os(iOS)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        #endif
                    if let url = item.url { Link("Open in Browser", destination: url) }
                }
            case .photo, .gif, .document:
                Section("File") {
                    if let data = item.thumbnail, let image = PlatformImage.from(data) {
                        image.resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                    }
                    LabeledContent("Name", value: item.filename ?? "—")
                    LabeledContent("Type", value: item.utType?.localizedDescription ?? "Unknown")
                    Button("Quick Look", systemImage: "eye") { previewURL = TempFiles.url(for: item) }
                }
            }

            Section("Tags") {
                TagPicker(selection: Binding(
                    get: { item.tags ?? [] },
                    set: { item.tags = $0; item.touch() }))
            }

            Section {
                Toggle("Pinned", isOn: $item.isPinned)
                Toggle("In Recents", isOn: Binding(get: { !item.isReviewed }, set: { item.isReviewed = !$0 }))
                LabeledContent("Saved", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.displayTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    item.touch()
                    try? context.save()
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy([item])
                    model.show("Copied")
                }
            }
        }
        .quickLookPreview($previewURL)
    }

    private func polish(_ style: PolishStyle) async {
        polishing = true
        defer { polishing = false }
        do {
            item.text = try await TextPolisher.polish(item.text, style: style)
            item.touch()
        } catch {
            model.show("Couldn't polish: \(error.localizedDescription)")
        }
    }
}

/// Pick existing tags or create a new colour-coded one.
struct TagPicker: View {
    @Binding var selection: [Tag]
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var newName = ""

    var body: some View {
        ForEach(tags) { tag in
            Button {
                if let index = selection.firstIndex(of: tag) { selection.remove(at: index) } else { selection.append(tag) }
            } label: {
                HStack {
                    Circle().fill(Color(hex: tag.colorHex)).frame(width: 12, height: 12)
                    Text(tag.name).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(tag) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(tag) ? .isSelected : [])
        }
        HStack {
            TextField("New tag", text: $newName).onSubmit(addTag)
            Button("Add", action: addTag).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addTag() {
        guard let tag = StashLibrary(context: context).tag(named: newName, create: true) else { return }
        if !selection.contains(tag) { selection.append(tag) }
        newName = ""
    }
}
