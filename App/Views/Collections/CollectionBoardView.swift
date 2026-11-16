import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

/// One collection shown as a board: quotes as cards, photos and video posters as
/// tiles, links with their preview image (YouTube gets a play badge).
struct CollectionBoardView: View {
    @Bindable var collection: TypoCollection
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var kindFilter: ItemKind?
    @State private var editing = false
    @State private var arranging = false
    @State private var addingExisting = false
    @State private var editingItem: TypoItem?
    @State private var previewURL: URL?
    @State private var dropTargeted = false
    @State private var exportURL: URL?

    private var library: CollectionLibrary { CollectionLibrary(context: context) }
    private var items: [TypoItem] {
        let all = library.orderedItems(collection)
        return kindFilter.map { k in all.filter { $0.kind == k } } ?? all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !library.summary(collection).isEmpty { filterChips }
                if items.isEmpty {
                    ContentUnavailableView("Empty collection", systemImage: collection.iconIsEmoji ? "square.stack.3d.up" : collection.icon,
                                           description: Text("Paste, drop files here, add existing items, or share to Typo and pick this collection."))
                        .padding(.top, 30)
                } else {
                    board
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background { AmbientBackground(hues: [collection.hue, Hues.named("Mist"), collection.hue]) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(collection.hue.gradient, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.item], isTargeted: $dropTargeted) { providers in
            Task { await ingest(providers) }
            return true
        }
        .safeAreaInset(edge: .bottom) { dock }
        .navigationTitle(collection.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Collection…", systemImage: "pencil") { editing = true }
                    Button("Arrange…", systemImage: "arrow.up.arrow.down") { arranging = true }
                    Button("Copy All", systemImage: "doc.on.doc") { copy(items) }
                    Button("Export as Zip…", systemImage: "archivebox") { exportURL = CollectionExporter.zip(collection, items: library.orderedItems(collection)) }
                    Button(collection.isPinned ? "Unpin" : "Pin", systemImage: collection.isPinned ? "pin.slash" : "pin") {
                        collection.isPinned.toggle(); try? context.save()
                    }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { CollectionEditor(collection: collection) } }
        .sheet(isPresented: $arranging) { NavigationStack { ArrangeCollectionView(collection: collection) } }
        .sheet(isPresented: $addingExisting) { NavigationStack { AddItemsPicker(collection: collection) } }
        .sheet(item: $editingItem) { item in NavigationStack { ItemDetailView(item: item) } }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { exportURL = $0?.url })) { file in
            ShareLink(item: file.url) { Label("Share \(collection.name).zip", systemImage: "square.and.arrow.up") }
                .buttonStyle(.glass).padding(40)
                .presentationDetents([.height(160)])
        }
        .quickLookPreview($previewURL)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            CollectionCover(collection: collection, items: library.coverItems(collection), height: 190)
            HStack(alignment: .firstTextBaseline) {
                Text(collection.name).font(.largeTitle.weight(.bold))
                Spacer()
                Text("\(collection.count)").font(.title3.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            }
            if !collection.note.isEmpty {
                Text(collection.note).font(.body).foregroundStyle(.secondary)
            }
            let summary = library.summary(collection)
            if !summary.isEmpty {
                Text(summary.map { $0.kind.counted($0.count) }.joined(separator: " · "))
                    .font(.footnote.weight(.medium)).foregroundStyle(collection.hue.inkColor)
            }
        }
        .padding(.top, 6)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(nil, "All", collection.hue)
                    ForEach(library.summary(collection), id: \.kind) { entry in
                        chip(entry.kind, entry.kind.title, CategoryColours.hue(for: entry.kind))
                    }
                }
            }
        }
    }

    private func chip(_ kind: ItemKind?, _ title: String, _ hue: Hue) -> some View {
        let on = kindFilter == kind
        return Button { withAnimation(.smooth) { kindFilter = kind } } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? hue.inkColor : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(hue.base.opacity(0.25)).interactive() : .regular.interactive())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Board

    /// Two columns on iPhone, more on iPad and Mac, filled shortest-column-first.
    private var board: some View {
        MasonryLayout(minColumnWidth: 220, spacing: 12) {
            ForEach(items) { item in
                BoardCard(item: item, hue: collection.hue)
                    .onTapGesture { copy([item]) }
                    .contextMenu { menu(for: item) }
                    .itemProvider { dragProvider(for: item) }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: TypoItem) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { copy([item]) }
        if let url = item.url { Link(destination: url) { Label(item.isVideoLink ? "Watch" : "Open Link", systemImage: item.isVideoLink ? "play.rectangle" : "safari") } }
        if item.byteCount > 0 { Button("Quick Look", systemImage: "eye") { previewURL = TempFiles.url(for: item) } }
        if item.thumbnail != nil {
            Button("Use as Cover", systemImage: "photo.on.rectangle") { library.setCover(item, for: collection) }
        }
        Button("Edit…", systemImage: "pencil") { editingItem = item }
        Divider()
        Button("Remove from Collection", systemImage: "minus.circle", role: .destructive) {
            withAnimation { library.remove([item], from: collection) }
        }
    }

    // MARK: Dock

    private var dock: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                PasteButton(supportedContentTypes: [.item]) { providers in Task { await ingest(providers) } }
                    .buttonBorderShape(.capsule)
                    .tint(collection.hue.base)
                Button { addingExisting = true } label: {
                    Label("Add Items", systemImage: "plus.rectangle.on.rectangle").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(.regular.interactive())
        }
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func copy(_ items: [TypoItem]) {
        guard !items.isEmpty else { return }
        Clipboard.copy(items)
        model.show(items.count == 1 ? "Copied" : "Copied \(items.count) items")
    }

    private func ingest(_ providers: [NSItemProvider]) async {
        let drafts = await Ingest.drafts(from: providers)
        guard !drafts.isEmpty else { return }
        let saved = TypoLibrary(context: context).save(drafts)
        library.add(saved, to: collection)
        model.show("Added \(saved.count) to \(collection.name)")
    }

    private func dragProvider(for item: TypoItem) -> NSItemProvider {
        if let url = TempFiles.url(for: item), let provider = NSItemProvider(contentsOf: url) { return provider }
        if let url = item.url { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider(object: item.text as NSString)
    }
}

private struct ExportFile: Identifiable { let url: URL; var id: String { url.path } }

/// Pinterest-style columns: each card goes into the currently shortest column.
struct MasonryLayout: Layout {
    var minColumnWidth: CGFloat = 220
    var spacing: CGFloat = 12

    private func columnCount(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minColumnWidth + spacing)))
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let count = columnCount(for: width)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        var heights = Array(repeating: CGFloat(0), count: count)
        var frames: [CGRect] = []
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: heights[column],
                                 width: columnWidth, height: size.height))
            heights[column] += size.height + spacing
        }
        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: place(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = place(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// One item on a collection board.
struct BoardCard: View {
    let item: TypoItem
    let hue: Hue

    var body: some View {
        Group {
            switch item.kind {
            case .text: quote
            case .photo, .gif, .video: media
            case .link: link
            case .document: document
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening").font(.title3.weight(.bold)).foregroundStyle(hue.gradient)
            Text(item.text)
                .font(.system(.title3, design: .serif))
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: true)
            if !item.title.isEmpty && item.title != item.text {
                Text("— " + item.title).font(.footnote.weight(.semibold)).foregroundStyle(hue.inkColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hue.softGradient)
        .background(.regularMaterial)
    }

    private var media: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = item.thumbnail, let image = PlatformImage.from(data) {
                image.resizable().scaledToFill().frame(minHeight: 150, maxHeight: 240).clipped()
            } else {
                HueTile(hue: CategoryColours.hue(for: item.kind), symbol: item.kind.symbol, size: 56)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(.regularMaterial)
            }
            if item.kind == .video {
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .glassEffect(in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if item.kind == .gif {
                Text("GIF").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 2)
                    .glassEffect().padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(item.displayTitle)
    }

    private var link: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = item.thumbnail, let image = PlatformImage.from(data) {
                ZStack {
                    image.resizable().scaledToFill().frame(height: 130).clipped()
                    if item.isVideoLink {
                        Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color(red: 0.9, green: 0.1, blue: 0.1).opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(3)
                Label(item.url?.host() ?? item.text, systemImage: item.isVideoLink ? "play.rectangle" : "link")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
    }

    private var document: some View {
        HStack(spacing: 10) {
            HueTile(hue: CategoryColours.hue(for: .document), symbol: "doc.fill", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                if item.byteCount > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

/// Mosaic of up to four images, or the collection's gradient and icon.
struct CollectionCover: View {
    let collection: TypoCollection
    let items: [TypoItem]
    var height: CGFloat = 120

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        // Decode first: an item can have thumbnail bytes that fail to decode.
        let images = items.compactMap { $0.thumbnail.flatMap(PlatformImage.from) }
        ZStack {
            if images.isEmpty {
                shape.fill(collection.hue.gradient)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)))
                Group {
                    if collection.iconIsEmoji { Text(collection.icon).font(.system(size: height * 0.38)) }
                    else { Image(systemName: collection.icon).font(.system(size: height * 0.3, weight: .semibold)).foregroundStyle(.white) }
                }
            } else {
                mosaic(images).clipShape(shape)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: collection.hue.base.opacity(0.25), radius: 14, y: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mosaic(_ images: [Image]) -> some View {
        switch images.count {
        case 1:
            images[0].resizable().scaledToFill()
        case 2:
            HStack(spacing: 2) { ForEach(0..<2, id: \.self) { images[$0].resizable().scaledToFill().frame(maxWidth: .infinity).clipped() } }
        case 3:
            HStack(spacing: 2) {
                images[0].resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                VStack(spacing: 2) { ForEach(1..<3, id: \.self) { images[$0].resizable().scaledToFill().frame(maxHeight: .infinity).clipped() } }
                    .frame(maxWidth: .infinity)
            }
        default:
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { tile(images, 0); tile(images, 1) }
                GridRow { tile(images, 2); tile(images, 3) }
            }
        }
    }

    private func tile(_ images: [Image], _ i: Int) -> some View {
        images[min(i, images.count - 1)].resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}
