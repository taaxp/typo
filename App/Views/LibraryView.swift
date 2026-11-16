import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

enum LibraryFilter: Hashable {
    case recents, all, pinned
    case kind(ItemKind)
    case tag(Tag)
    case collection(TypoCollection)
    case codes, vault

    var title: String {
        switch self {
        case .recents: "Recents"
        case .all: "All Items"
        case .pinned: "Pinned"
        case .kind(let kind): kind.title
        case .tag(let tag): tag.name
        case .collection(let c): c.name
        case .codes: "Codes"
        case .vault: "Vault"
        }
    }

    /// Hues that tint the ambient background for this view.
    var hues: [Hue] {
        switch self {
        case .recents: [Hues.named("Ocean"), Hues.named("Dusk"), Hues.named("Lagoon")]
        case .all: [Hues.named("Mist"), Hues.named("Dusk"), Hues.named("Sage")]
        case .pinned: [Hues.named("Amber"), Hues.named("Coral"), Hues.named("Honey")]
        case .kind(let kind): [CategoryColours.hue(for: kind), Hues.named("Mist"), CategoryColours.hue(for: kind)]
        case .tag(let tag): [tag.hue, Hues.named("Mist"), tag.hue]
        case .collection(let c): [c.hue, Hues.named("Mist"), c.hue]
        case .codes: [Hues.named("Lagoon"), Hues.named("Mist"), Hues.named("Amber")]
        case .vault: [Hues.named("Fog"), Hues.named("Ocean"), Hues.named("Dusk")]
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \TypoCollection.name) private var collections: [TypoCollection]
    @State private var showSettings = false

    private var orderedCollections: [TypoCollection] {
        collections.filter(\.isPinned) + collections.filter { !$0.isPinned }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.filter) {
                Section {
                    sidebarRow(.recents, symbol: "clock.fill", hue: Hues.named("Ocean"))
                    sidebarRow(.all, symbol: "tray.full.fill", hue: Hues.named("Fog"))
                    sidebarRow(.pinned, symbol: "pin.fill", hue: Hues.named("Amber"))
                }
                Section {
                    ForEach(orderedCollections) { c in
                        HStack(spacing: 10) {
                            CollectionCover(collection: c, items: CollectionLibrary(context: context).coverItems(c, limit: 1), height: 26)
                                .frame(width: 26)
                            Text(c.name)
                            Spacer()
                            Text("\(c.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                        }
                        .tag(LibraryFilter.collection(c))
                    }
                    Button { model.open(.newCollection) } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Collections")
                }
                Section("Categories") {
                    ForEach(ItemKind.allCases) { kind in
                        sidebarRow(.kind(kind), symbol: kind.symbol, hue: CategoryColours.hue(for: kind))
                    }
                }
                Section("Tools") {
                    sidebarRow(.codes, symbol: "qrcode", hue: Hues.named("Lagoon"))
                    sidebarRow(.vault, symbol: "lock.fill", hue: Hues.named("Fog"))
                }
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags) { tag in
                            HStack(spacing: 10) {
                                HueDot(hue: tag.hue, size: 14)
                                Text(tag.name)
                                Spacer()
                                Text(tag.hueName).font(.caption).foregroundStyle(.tertiary)
                            }
                            .tag(LibraryFilter.tag(tag))
                        }
                    }
                }
            }
            .navigationTitle("Typo")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            #endif
        } detail: {
            switch model.filter ?? .all {
            case .codes: NavigationStack { CodesView() }
            case .vault: NavigationStack { VaultView() }
            case .collection(let c): NavigationStack { CollectionBoardView(collection: c) }
            case let other: ItemListView(filter: other)
            }
        }
    }

    private func sidebarRow(_ filter: LibraryFilter, symbol: String, hue: Hue) -> some View {
        Label { Text(filter.title) } icon: { HueTile(hue: hue, symbol: symbol, size: 26) }
            .tag(filter)
    }
}

// MARK: - Item list

struct ItemListView: View {
    let filter: LibraryFilter

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \TypoItem.sortIndex, order: .reverse) private var allItems: [TypoItem]

    @State private var search = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var editing: TypoItem?
    @State private var renaming: TypoItem?
    @State private var renameText = ""
    @State private var previewURL: URL?
    @State private var showImageURLPrompt = false
    @State private var imageURLText = ""
    @State private var showFileImporter = false
    @State private var dropTargeted = false
    @State private var qrDraft: CodeDraft?
    @State private var newCollectionFor: TypoItem?
    @Query(sort: \TypoCollection.name) private var collections: [TypoCollection]
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var library: TypoLibrary { TypoLibrary(context: context) }

    /// Pinned first, then manual order.
    private var visibleItems: [TypoItem] {
        let filtered = allItems.filter { item in
            switch filter {
            case .recents: !item.isReviewed
            case .all: true
            case .pinned: item.isPinned
            case .kind(let kind): item.kind == kind
            case .tag(let tag): (item.tags ?? []).contains(tag)
            case .collection(let c): (item.collections ?? []).contains(c)
            case .codes, .vault: false
            }
        }
        let searched = search.isEmpty ? filtered : filtered.filter { $0.searchableText.localizedStandardContains(search) }
        return searched.filter(\.isPinned) + searched.filter { !$0.isPinned }
    }

    private var canReorder: Bool { search.isEmpty && filter != .recents }
    private var selectedItems: [TypoItem] { visibleItems.filter { selection.contains($0.persistentModelID) } }

    private var isEditing: Bool {
        #if os(iOS)
        editMode.isEditing
        #else
        false
        #endif
    }

    var body: some View {
        let items = visibleItems
        List(selection: $selection) {
            if filter == .recents && !items.isEmpty {
                Text("\(items.count) new \(items.count == 1 ? "save" : "saves") waiting for review. Tagged items leave on their own after a few days.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
            ForEach(items) { item in
                ItemRow(item: item)
                    .tag(item.persistentModelID)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .itemProvider { dragProvider(for: item) }
                    .swipeActions(edge: .leading) {
                        Button { library.togglePin(item) } label: {
                            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(Hues.named("Amber").base)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { library.delete([item]) } label: { Label("Delete", systemImage: "trash") }
                        if !item.isReviewed {
                            Button { library.markReviewed([item]) } label: { Label("Reviewed", systemImage: "checkmark") }
                                .tint(Hues.named("Sage").base)
                        }
                    }
            }
            .onMove(perform: canReorder ? { (from: IndexSet, to: Int) in library.move(items, from: from, to: to) } as ((IndexSet, Int) -> Void)? : nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(hues: filter.hues) }
        // Tap (iOS) / double-click or Return (Mac) copies. Long-press / right-click for more.
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            contextMenu(for: items.filter { ids.contains($0.persistentModelID) })
        } primaryAction: { ids in
            copy(items.filter { ids.contains($0.persistentModelID) })
        }
        .overlay { if items.isEmpty { emptyState } }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Hues.named("Ocean").gradient, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(Hues.named("Ocean").base.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom) { dock }
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
        .sheet(item: $qrDraft) { draft in NavigationStack { QRStudioView(draft: draft) } }
        .sheet(item: $newCollectionFor) { item in
            NavigationStack {
                CollectionEditor(collection: nil) { CollectionLibrary(context: context).add([item], to: $0) }
            }
        }
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

    // MARK: Dock

    /// Floating Liquid Glass dock: Paste, Dictate, Quick Save, More.
    @ViewBuilder
    private var dock: some View {
        GlassEffectContainer(spacing: 16) {
            if isEditing {
                HStack(spacing: 12) {
                    Button("Copy \(selection.count)", systemImage: "doc.on.doc") { copy(selectedItems) }
                        .disabled(selection.isEmpty)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        library.delete(selectedItems)
                        selection.removeAll()
                    }
                    .disabled(selection.isEmpty)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                HStack(spacing: 14) {
                    // The system Paste button reads the clipboard without the "Allow Paste?" prompt.
                    PasteButton(supportedContentTypes: [.item]) { providers in
                        Task { await ingest(providers) }
                    }
                    .buttonBorderShape(.capsule)
                    .tint(Hues.named("Ocean").base)

                    Button { model.open(.dictate) } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Hues.named("Dusk").gradient, in: Circle())
                            .shadow(color: Hues.named("Dusk").base.opacity(0.45), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dictate")

                    #if os(iOS)
                    Button { model.open(.scan) } label: {
                        Image(systemName: "qrcode.viewfinder").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan")
                    #else
                    Button { model.open(.quickSave) } label: {
                        Image(systemName: "tag.fill").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quick Save with tags")
                    #endif

                    addMenu
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular.interactive())
            }
        }
        .padding(.bottom, 8)
    }

    private var addMenu: some View {
        Menu {
            Button("Quick Save with Tags…", systemImage: "tag") { model.open(.quickSave) }
            Button("New QR Code…", systemImage: "qrcode") { model.open(.newCode) }
            Button("Add Member Card…", systemImage: "barcode") { model.open(.codes) }
            Button("Add Bank Card…", systemImage: "creditcard") { model.open(.vault) }
            Button("New Collection…", systemImage: "square.stack.3d.up") { model.open(.newCollection) }
            Divider()
            Button("Photo or GIF from URL…", systemImage: "photo.badge.arrow.down") {
                imageURLText = ""
                showImageURLPrompt = true
            }
            Button("Import Files…", systemImage: "doc.badge.plus") { showFileImporter = true }
            Divider()
            Button("Sync Status", systemImage: "icloud") { model.open(.sync) }
        } label: {
            Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("More ways to add")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if filter == .recents && !visibleItems.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", systemImage: "checkmark.circle") {
                    withAnimation { library.markReviewed(visibleItems) }
                }
                .accessibilityLabel("Clear Recents")
            }
        }
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Button(isEditing ? "Done" : "Select") {
                withAnimation {
                    editMode = isEditing ? .inactive : .active
                    if !isEditing { selection.removeAll() }
                }
            }
        }
        #endif
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(for items: [TypoItem]) -> some View {
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
            Menu("Add to Collection", systemImage: "square.stack.3d.up") {
                ForEach(collections) { c in
                    let isIn = (item.collections ?? []).contains(c)
                    Button(c.name, systemImage: isIn ? "checkmark" : "square.stack") {
                        CollectionLibrary(context: context).toggle(item, in: c)
                        model.show(isIn ? "Removed from \(c.name)" : "Added to \(c.name)")
                    }
                }
                Divider()
                Button("New Collection…", systemImage: "plus") { newCollectionFor = item }
            }
            if item.kind.isInsertableAsText {
                Button("Show as QR Code", systemImage: "qrcode") {
                    var draft = CodeDraft()
                    draft.type = item.kind == .link ? .link : .text
                    draft.text = item.text
                    draft.title = item.displayTitle
                    qrDraft = draft
                }
            }
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

    private func copy(_ items: [TypoItem]) {
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

    private func dragProvider(for item: TypoItem) -> NSItemProvider {
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
                                   description: Text("Paste, drop a file here, or share to Typo from any app."))
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
