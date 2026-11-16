import SwiftUI
import SwiftData
import QuickLook

/// Rename, edit text, tag, polish and preview one item.
struct ItemDetailView: View {
    @Bindable var item: TypoItem
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var polishing = false

    private var library: TypoLibrary { TypoLibrary(context: context) }

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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Template.helpChips, id: \.label) { chip in
                                Button { item.text += chip.insert } label: {
                                    Text(chip.insert).font(.caption.monospaced().weight(.semibold))
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("Insert \(chip.label)")
                            }
                        }
                    }
                    if item.isTemplate {
                        LabeledContent("Preview") {
                            Text(Template.render(item.text).text).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
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
            case .photo, .gif, .video, .document:
                Section("File") {
                    if let data = item.thumbnail, let image = PlatformImage.from(data) {
                        image.resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                    }
                    LabeledContent("Name", value: item.filename ?? "—")
                    LabeledContent("Type", value: item.utType?.localizedDescription ?? "Unknown")
                    Button("Quick Look", systemImage: "eye") { previewURL = TempFiles.url(for: item) }
                }
            }

            if item.kind == .text || item.kind == .link {
                Section {
                    HStack(spacing: 2) {
                        Text(";").font(.body.monospaced().weight(.bold)).foregroundStyle(Hues.named("Dusk").inkColor)
                        TextField("shortcut, e.g. addr", text: Binding(
                            get: { item.shortcut },
                            set: { item.shortcut = TextExpander.normalise($0) }))
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    if let clash = shortcutClash {
                        Label("“;\(item.shortcut)” is already used by \(clash).", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Hues.named("Coral").inkColor)
                    }
                } header: {
                    Text("Text expansion")
                } footer: {
                    Text("Type ;\(item.shortcut.isEmpty ? "shortcut" : item.shortcut) and a space with the Typo keyboard to insert this. In templates, {Name} becomes a field you fill in, and {date}, {time} and {cursor} fill themselves.")
                }
            }

            if !item.summary.isEmpty {
                Section {
                    Text(item.summary)
                } header: {
                    Label("Summary", systemImage: "sparkles")
                }
            }

            let actions = DataAction.detect(in: [item.text, item.recognisedText].joined(separator: "\n"))
            if !actions.isEmpty {
                Section("Quick actions") {
                    ForEach(actions) { action in
                        if let url = action.url {
                            Link(destination: url) { Label(action.title, systemImage: action.symbol) }
                        } else {
                            Button(action.title, systemImage: action.symbol) {
                                Clipboard.copy(text: action.title)
                                model.show("Copied date")
                            }
                        }
                    }
                }
            }

            if !item.recognisedText.isEmpty {
                Section("Text in image") {
                    Text(item.recognisedText).font(.callout).textSelection(.enabled)
                }
            }

            Section("Collections") {
                CollectionPicker(selection: Binding(
                    get: { item.collections ?? [] },
                    set: { newValue in
                        let library = CollectionLibrary(context: context)
                        let old = item.collections ?? []
                        for c in newValue where !old.contains(c) { library.add([item], to: c) }
                        for c in old where !newValue.contains(c) { library.remove([item], from: c) }
                    }))
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
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(hues: [CategoryColours.hue(for: item.kind), Hues.named("Mist"), CategoryColours.hue(for: item.kind)]) }
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

    /// Another item using the same shortcut, if any.
    private var shortcutClash: String? {
        guard !item.shortcut.isEmpty else { return nil }
        let wanted = item.shortcut
        let others = (try? context.fetch(FetchDescriptor<TypoItem>(predicate: #Predicate { $0.shortcut == wanted }))) ?? []
        return others.first { $0.persistentModelID != item.persistentModelID }?.displayTitle
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

/// Pick existing tags or create a new one. Each tag shows its gradient and hue name.
struct TagPicker: View {
    @Binding var selection: [Tag]
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var newName = ""

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    let isOn = selection.contains(tag)
                    Button {
                        if let index = selection.firstIndex(of: tag) { selection.remove(at: index) } else { selection.append(tag) }
                    } label: {
                        HStack(spacing: 6) {
                            HueDot(hue: tag.hue, size: 10)
                            Text(tag.name).font(.subheadline.weight(.medium))
                            if isOn { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        }
                        .foregroundStyle(isOn ? tag.hue.inkColor : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(isOn ? AnyShapeStyle(tag.hue.softGradient) : AnyShapeStyle(.thinMaterial), in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? tag.hue.base.opacity(0.6) : .white.opacity(0.4), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tag.name), \(tag.hueName)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        HStack {
            TextField("New tag", text: $newName).onSubmit(addTag)
            Button("Add", action: addTag)
                .buttonStyle(.glass)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addTag() {
        guard let tag = TypoLibrary(context: context).tag(named: newName, create: true) else { return }
        if !selection.contains(tag) { selection.append(tag) }
        newName = ""
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
