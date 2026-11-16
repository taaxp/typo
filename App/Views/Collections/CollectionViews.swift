import SwiftUI
import SwiftData

/// Create or edit a collection: name, note, hue and icon.
struct CollectionEditor: View {
    var collection: TypoCollection?
    var onCreate: ((TypoCollection) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var hueName = "Dusk"
    @State private var icon = "square.stack.3d.up.fill"
    @State private var emoji = ""
    @State private var confirmDelete = false

    private static let icons = ["square.stack.3d.up.fill", "star.fill", "heart.fill", "lightbulb.fill", "book.fill",
                                "film.fill", "music.note", "airplane", "fork.knife", "briefcase.fill", "graduationcap.fill",
                                "paintpalette.fill", "person.fill", "quote.bubble.fill", "sparkles", "leaf.fill"]

    var body: some View {
        Form {
            Section {
                CollectionCover(collection: preview, items: [], height: 120)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Name, e.g. Steve Jobs", text: $name)
                TextField("Description (optional)", text: $note, axis: .vertical).lineLimit(1...4)
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                    ForEach(Self.icons, id: \.self) { symbol in
                        Button { icon = symbol; emoji = "" } label: {
                            Image(systemName: symbol).font(.title3).frame(width: 44, height: 44)
                                .foregroundStyle(icon == symbol ? Color.white : Color.primary)
                                .background(icon == symbol ? AnyShapeStyle(Hues.named(hueName).gradient) : AnyShapeStyle(.thinMaterial), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                TextField("Or an emoji", text: $emoji)
                    .onChange(of: emoji) { _, new in if let first = new.first { icon = String(first) } }
            }
            Section("Colour") { HuePicker(selection: $hueName) }
            if collection != nil {
                Section {
                    Button("Delete Collection", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("The items stay in your library.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(collection == nil ? "New Collection" : "Edit Collection")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let collection {
                name = collection.name; note = collection.note; hueName = collection.hueName; icon = collection.icon
            }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmDelete) {
            Button("Delete Collection", role: .destructive) {
                if let collection { CollectionLibrary(context: context).delete(collection) }
                dismiss()
            }
        }
    }

    private var preview: TypoCollection {
        let c = TypoCollection(name: name, hueName: hueName, icon: icon)
        return c
    }

    private func save() {
        let library = CollectionLibrary(context: context)
        let target = collection ?? library.create(name: name, hueName: hueName, icon: icon)
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = note
        target.hueName = hueName
        target.icon = icon
        target.modifiedAt = .now
        try? context.save()
        if collection == nil { onCreate?(target) }
        dismiss()
    }
}

/// Drag to reorder a collection.
struct ArrangeCollectionView: View {
    let collection: TypoCollection
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let library = CollectionLibrary(context: context)
        List {
            ForEach(library.orderedItems(collection)) { item in
                HStack(spacing: 12) {
                    ItemThumbnail(item: item, size: 36)
                    Text(item.displayTitle).lineLimit(1)
                }
            }
            .onMove { library.move(in: collection, from: $0, to: $1) }
            .onDelete { offsets in
                let items = library.orderedItems(collection)
                library.remove(offsets.map { items[$0] }, from: collection)
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Arrange")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
    }
}

/// Pick existing library items to add to a collection.
struct AddItemsPicker: View {
    let collection: TypoCollection
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TypoItem.sortIndex, order: .reverse) private var items: [TypoItem]
    @State private var search = ""
    @State private var selection = Set<PersistentIdentifier>()

    private var candidates: [TypoItem] {
        let notIn = items.filter { !(collection.items ?? []).contains($0) }
        return search.isEmpty ? notIn : notIn.filter { $0.searchableText.localizedStandardContains(search) }
    }

    var body: some View {
        List(candidates, selection: $selection) { item in
            ItemRow(item: item)
                .tag(item.persistentModelID)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Search your library")
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Add to \(collection.name)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(selection.count)", systemImage: "checkmark") {
                    let chosen = items.filter { selection.contains($0.persistentModelID) }
                    CollectionLibrary(context: context).add(chosen, to: collection)
                    model.show("Added \(chosen.count) to \(collection.name)")
                    dismiss()
                }
                .disabled(selection.isEmpty)
            }
        }
    }
}

/// Chip picker for choosing collections on the way in (Quick Save, Dictate, item details).
struct CollectionPicker: View {
    @Binding var selection: [TypoCollection]
    @Query(sort: \TypoCollection.name) private var collections: [TypoCollection]
    @State private var creating = false

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(collections) { c in
                let on = selection.contains(c)
                Button {
                    if let i = selection.firstIndex(of: c) { selection.remove(at: i) } else { selection.append(c) }
                } label: {
                    HStack(spacing: 6) {
                        if c.iconIsEmoji { Text(c.icon).font(.caption) } else { Image(systemName: c.icon).font(.caption) }
                        Text(c.name).font(.subheadline.weight(.medium))
                        if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }
                    .foregroundStyle(on ? c.hue.inkColor : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(on ? AnyShapeStyle(c.hue.softGradient) : AnyShapeStyle(.thinMaterial), in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? c.hue.base.opacity(0.6) : .white.opacity(0.4), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button { creating = true } label: {
                Label("New", systemImage: "plus").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
            }
            .buttonStyle(.glass)
        }
        .sheet(isPresented: $creating) {
            NavigationStack { CollectionEditor(collection: nil) { selection.append($0) } }
        }
    }
}

/// Exports a collection as a zip: files as themselves, plus "Notes.md" with the
/// quotes, notes and links in order.
enum CollectionExporter {
    @MainActor
    static func zip(_ collection: TypoCollection, items: [TypoItem]) -> URL? {
        let fm = FileManager.default
        let safeName = collection.name.replacingOccurrences(of: "/", with: "-")
        let root = fm.temporaryDirectory.appendingPathComponent("TypoExport-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(safeName, isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var notes = "# \(collection.name)\n\n"
            if !collection.note.isEmpty { notes += collection.note + "\n\n" }
            var used = Set<String>()
            for item in items {
                switch item.kind {
                case .text:
                    notes += "> " + item.text.replacingOccurrences(of: "\n", with: "\n> ") + "\n"
                    if !item.title.isEmpty { notes += "> — \(item.title)\n" }
                    notes += "\n"
                case .link:
                    notes += "- [\(item.displayTitle)](\(item.text))\n"
                default:
                    guard let data = item.payload else { continue }
                    var name = item.filename ?? Ingest.defaultFilename(for: item.utType ?? .data)
                    while used.contains(name) { name = "1-" + name }
                    used.insert(name)
                    try data.write(to: folder.appendingPathComponent(name))
                    notes += "- \(name)\n"
                }
            }
            try notes.write(to: folder.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        // NSFileCoordinator's .forUploading option produces a zip of a folder.
        var zipped: URL?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { tempZip in
            let destination = root.appendingPathComponent("\(safeName).zip")
            try? fm.copyItem(at: tempZip, to: destination)
            zipped = destination
        }
        return zipped
    }
}
