import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

enum LibraryFilter: Hashable {
    case recents, all, pinned
    case kind(ItemKind)
    case tag(Tag)

    var title: String {
        switch self {
        case .recents: "Recents"
        case .all: "All Items"
        case .pinned: "Pinned"
        case .kind(let kind): kind.title
        case .tag(let tag): tag.name
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var filter: LibraryFilter? = .recents
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section {
                    sidebarRow(.recents, symbol: "clock.badge", colour: .accentColor)
                    sidebarRow(.all, symbol: "tray.full", colour: .secondary)
                    sidebarRow(.pinned, symbol: "pin", colour: .orange)
                }
                Section("Categories") {
                    ForEach(ItemKind.allCases) { kind in
                        sidebarRow(.kind(kind), symbol: kind.symbol, colour: CategoryColours.color(for: kind))
                    }
                }
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags) { tag in
                            Label { Text(tag.name) } icon: {
                                Circle().fill(Color(hex: tag.colorHex)).frame(width: 10, height: 10)
                            }
                            .tag(LibraryFilter.tag(tag))
                        }
                    }
                }
            }
            .navigationTitle("Stash")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            #endif
        } detail: {
            ItemListView(filter: filter ?? .all)
        }
    }

    private func sidebarRow(_ filter: LibraryFilter, symbol: String, colour: Color) -> some View {
        Label { Text(filter.title) } icon: { Image(systemName: symbol).foregroundStyle(colour) }
            .tag(filter)
    }
}

// MARK: - Item list

struct ItemListView: View {
    let filter: LibraryFilter

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \StashItem.sortIndex, order: .reverse) private var allItems: [StashItem]

    @State private var search = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var editing: StashItem?
    @State private var renaming: StashItem?
    @State private var renameText = ""
    @State private var previewURL: URL?
    @State private var showImageURLPrompt = false
    @State private var imageURLText = ""
    @State private var showFileImporter = false
    @State private var dropTargeted = false
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var library: StashLibrary { StashLibrary(context: context) }

    /// Pinned first, then manual order.
    private var visibleItems: [StashItem] {
        let filtered = allItems.filter { item in
            switch filter {
            case .recents: !item.isReviewed
            case .all: true
            case .pinned: item.isPinned
            case .kind(let kind): item.kind == kind
            case .tag(let tag): (item.tags ?? []).contains(tag)
            }
        }
        let searched = search.isEmpty ? filtered : filtered.filter { $0.searchableText.localizedStandardContains(search) }
        return searched.filter(\.isPinned) + searched.filter { !$0.isPinned }
    }

    private var canReorder: Bool { search.isEmpty && filter != .recents }

    private var selectedItems: [StashItem] { visibleItems.filter { selection.contains($0.persistentModelID) } }

    var body: some View {
        let items = visibleItems
        List(selection: $selection) {
            if filter == .recents && !items.isEmpty {
                Section {
                    Button("Clear Recents", systemImage: "checkmark.circle") {
                        withAnimation { library.markReviewed(items) }
                    }
                } footer: {
                    Text("New saves wait here until you've reviewed them. Tagged items leave on their own after a few days (change this in Settings).")
                }
            }
            ForEach(items) { item in
                ItemRow(item: item)
                    .tag(item.persistentModelID)
                    .itemProvider { dragProvider(for: item) }
                    .swipeActions(edge: .leading) {
                        Button { library.togglePin(item) } label: {
                            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { library.delete([item]) } label: { Label("Delete", systemImage: "trash") }
                        if !item.isReviewed {
                            Button { library.markReviewed([item]) } label: { Label("Reviewed", systemImage: "checkmark") }
                                .tint(.green)
                        }
                    }
            }
            .onMove(perform: canReorder ? { (from: IndexSet, to: Int) in library.move(items, from: from, to: to) } as ((IndexSet, Int) -> Void)? : nil)
        }
        // Tap (iOS) / double-click or Return (Mac) copies. Long-press / right-click for more.
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            contextMenu(for: items.filter { ids.contains($0.persistentModelID) })
        } primaryAction: { ids in
            copy(items.filter { ids.contains($0.persistentModelID) })
        }
        .overlay {
            if items.isEmpty { emptyState }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.item], isTargeted: $dropTargeted) { providers in
            Task { await ingest(providers) }
            return true
        }
        .searchable(text: $search, prompt: "Search everything")
        .navigationTitle(filter.title)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .toolbar { toolbar }
        .onCopyCommandIfAvailable { selectedItems.map(dragProvider(for:)) }
        .sheet(item: $editing) { item in NavigationStack { ItemDetailView(item: item) } }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let renaming { library.rename(renaming, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save image from URL", isPresented: $showImageURLPrompt) {
            TextField("https://example.com/picture.gif", text: $imageURLText)
                #if os(iOS)
                .keyboardType(.URL).textInputAutocapitalization(.never)
                #endif
            Button("Save") { Task { await saveImage(from: imageURLText) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a direct link to a photo or GIF.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .quickLookPreview($previewURL)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // The system Paste button reads the clipboard without the "Allow Paste?" prompt.
            PasteButton(supportedContentTypes: [.item]) { providers in
                Task { await ingest(providers) }
            }
            .labelStyle(.iconOnly)

            Menu {
                Button("Quick Save with Tags…", systemImage: "tag") { model.route = .quickSave }
                Button("Dictate…", systemImage: "mic") { model.route = .dictate }
                Button("Photo or GIF from URL…", systemImage: "photo.badge.arrow.down") {
                    imageURLText = ""
                    showImageURLPrompt = true
                }
                Button("Import Files…", systemImage: "doc.badge.plus") { showFileImporter = true }
                Divider()
                Button("Sync Status", systemImage: "icloud") { model.route = .sync }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            if editMode.isEditing {
                Button("Copy \(selection.count)", systemImage: "doc.on.doc") { copy(selectedItems) }
                    .disabled(selection.isEmpty)
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    library.delete(selectedItems)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                    if !editMode.isEditing { selection.removeAll() }
                }
            }
        }
        #endif
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(for items: [StashItem]) -> some View {
        if items.count > 1 {
            Button("Copy \(items.count) Items", systemImage: "doc.on.doc") { copy(items) }
            Button("Delete \(items.count) Items", systemImage: "trash", role: .destructive) { library.delete(items) }
        } else if let item = items.first {
            Button("Copy", systemImage: "doc.on.doc") { copy([item]) }
            if item.byteCount > 0 {
                Button("Quick Look", systemImage: "eye") { previewURL = TempFiles.url(for: item) }
            }
            if let url = item.url {
                Link(destination: url) { Label("Open Link", systemImage: "safari") }
            }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") { library.togglePin(item) }
            Button("Rename…", systemImage: "pencil") {
                renameText = item.title
                renaming = item
            }
            Button("Edit Tags and Details…", systemImage: "tag") { editing = item }
            if let url = TempFiles.url(for: item) {
                ShareLink(item: url)
            } else if item.kind.isInsertableAsText {
                ShareLink(item: item.text)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { library.delete([item]) }
        }
    }

    // MARK: Actions

    private func copy(_ items: [StashItem]) {
        guard !items.isEmpty else { return }
        Clipboard.copy(items)
        model.show(items.count == 1 ? "Copied" : "Copied \(items.count) items")
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func ingest(_ providers: [NSItemProvider]) async {
        let drafts = await Ingest.drafts(from: providers)
        guard !drafts.isEmpty else { model.show("Nothing to save"); return }
        let tags: [Tag] = if case .tag(let tag) = filter { [tag] } else { [] }
        _ = library.save(drafts, tags: tags)
        model.show(drafts.count == 1 ? "Saved" : "Saved \(drafts.count) items")
    }

    private func saveImage(from text: String) async {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            model.show("That isn't a valid link"); return
        }
        do {
            library.save(try await Ingest.draft(fromImageURL: url))
            model.show("Saved")
        } catch {
            model.show(error.localizedDescription)
        }
    }

    private func importFiles(_ urls: [URL]) {
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if let draft = try? Ingest.draft(fromData: data, type: type, filename: url.lastPathComponent) {
                library.save(draft)
                count += 1
            }
        }
        model.show("Imported \(count)")
    }

    private func dragProvider(for item: StashItem) -> NSItemProvider {
        if let url = TempFiles.url(for: item), let provider = NSItemProvider(contentsOf: url) {
            provider.suggestedName = item.filename
            return provider
        }
        if let url = item.url { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider(object: item.text as NSString)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if filter == .recents {
            ContentUnavailableView("All caught up", systemImage: "checkmark.circle",
                                   description: Text("New saves from the share sheet, clipboard, drag and drop or Shortcuts appear here."))
        } else {
            ContentUnavailableView("Nothing here yet", systemImage: "tray",
                                   description: Text("Paste, drop a file here, or share to Stash from any app."))
        }
    }
}

private extension View {
    /// ⌘C on the Mac copies the selected items as the real thing.
    @ViewBuilder
    func onCopyCommandIfAvailable(_ providers: @escaping () -> [NSItemProvider]) -> some View {
        #if os(macOS)
        self.onCopyCommand(perform: providers)
        #else
        self
        #endif
    }
}
