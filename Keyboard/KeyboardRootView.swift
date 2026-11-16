import SwiftUI
import SwiftData

struct KeyboardRootView: View {
    let actions: KeyboardActions
    let libraryAvailable: Bool

    @State private var tab: Tab = .typo
    enum Tab { case typo, keys }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // Banner sits at the bottom so it never covers the category chips.
            ZStack(alignment: .bottom) {
                switch tab {
                case .typo:
                    if libraryAvailable { TypoGrid(actions: actions) } else { FullAccessPrompt() }
                case .keys:
                    TypingKeys(actions: actions)
                }
                if let banner = actions.banner {
                    Label(banner, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect()
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.smooth, value: actions.banner)
    }

    /// Liquid Glass control strip: mode switch, Polish, next keyboard.
    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    modeButton(.typo) { Image(systemName: "square.grid.2x2.fill") }
                        .accessibilityLabel("Typo library")
                    modeButton(.keys) { Text("ABC").font(.footnote.weight(.bold)) }
                        .accessibilityLabel("Letters")
                }
                .padding(3)
                .glassEffect()

                Spacer()

                if case .available = actions.polishAvailability {
                    Menu {
                        ForEach(PolishStyle.allCases) { style in
                            Button(style.title, systemImage: style.symbol) { Task { await actions.polish(style) } }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if actions.isPolishing { ProgressView().controlSize(.small) }
                            else { Image(systemName: "wand.and.stars").foregroundStyle(Hues.named("Dusk").gradient) }
                            Text("Polish").font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .glassEffect(.regular.tint(Hues.named("Dusk").base.opacity(0.15)).interactive())
                    .accessibilityHint("Rewrites the selected text, or the text before the cursor, with Apple Intelligence")
                }

                if actions.needsGlobe {
                    Button { actions.nextKeyboard() } label: {
                        Image(systemName: "globe").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Next keyboard")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func modeButton<Label: View>(_ value: Tab, @ViewBuilder label: () -> Label) -> some View {
        Button { withAnimation(.smooth) { tab = value } } label: {
            label()
                .frame(width: 48, height: 30)
                .foregroundStyle(tab == value ? Color.white : Color.primary)
                .background {
                    if tab == value { Capsule().fill(Hues.named("Ocean").gradient) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

/// Library grid, grouped by category, pinned and manual order first.
private struct TypoGrid: View {
    let actions: KeyboardActions
    @Query(sort: \TypoItem.sortIndex, order: .reverse) private var items: [TypoItem]
    @Query(sort: \TypoCollection.name) private var collections: [TypoCollection]
    @State private var kind: ItemKind?
    @State private var collectionID: UUID?

    private var visible: [TypoItem] {
        var filtered = kind.map { k in items.filter { $0.kind == k } } ?? items
        if let collectionID {
            filtered = filtered.filter { ($0.collections ?? []).contains { $0.uuid == collectionID } }
        }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, title: "All", hue: Hues.named("Fog"))
                    ForEach(ItemKind.allCases) { k in chip(k, title: k.shortTitle, hue: CategoryColours.hue(for: k)) }
                    // Collections, e.g. "Steve Jobs", so a whole set is one tap away.
                    ForEach(collections) { c in collectionChip(c) }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }
            if visible.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "tray",
                                       description: Text("Share to Typo from any app, or open Typo to paste."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(visible) { item in
                            KeyboardItemCell(item: item)
                                .onTapGesture { actions.use(item) }
                                .contextMenu {
                                    Button("Copy", systemImage: "doc.on.doc") { actions.copy(item) }
                                    if item.kind.isInsertableAsText {
                                        Button("Insert", systemImage: "text.insert") { actions.use(item) }
                                    }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint(item.kind.isInsertableAsText ? "Types this into the text field" : "Copies this to the clipboard")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
            }
        }
    }

    private func collectionChip(_ c: TypoCollection) -> some View {
        let on = collectionID == c.uuid
        return Button { withAnimation(.smooth) { collectionID = on ? nil : c.uuid; kind = nil } } label: {
            HStack(spacing: 5) {
                if c.iconIsEmoji { Text(c.icon).font(.caption2) } else { Image(systemName: c.icon).font(.caption2) }
                Text(c.name).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? c.hue.inkColor : .primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(on ? AnyShapeStyle(c.hue.softGradient) : AnyShapeStyle(.thinMaterial), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collection \(c.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chip(_ k: ItemKind?, title: String, hue: Hue) -> some View {
        let on = kind == k && (k != nil || collectionID == nil)
        return Button { withAnimation(.smooth) { kind = k; if k == nil { collectionID = nil } } } label: {
            HStack(spacing: 5) {
                HueDot(hue: hue, size: 8)
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? hue.inkColor : .primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(on ? AnyShapeStyle(hue.softGradient) : AnyShapeStyle(.thinMaterial), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct KeyboardItemCell: View {
    let item: TypoItem

    var body: some View {
        HStack(spacing: 9) {
            // Thumbnails only: the keyboard has a small memory budget, so full files are never loaded here.
            if let data = item.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                HueTile(hue: CategoryColours.hue(for: item.kind), symbol: item.kind.symbol, size: 34)
            }
            Text(item.displayTitle).font(.footnote.weight(.medium)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Hues.named("Amber").gradient)
            }
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

private struct FullAccessPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Allow Full Access", systemImage: "lock")
        } description: {
            Text("To show your Typo library here, go to Settings › General › Keyboard › Keyboards › Typo and turn on Allow Full Access. The keyboard doesn't connect to the internet or store what you type.")
        }
    }
}
