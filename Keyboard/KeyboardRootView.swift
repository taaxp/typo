import SwiftUI
import SwiftData

struct KeyboardRootView: View {
    let actions: KeyboardActions
    let libraryAvailable: Bool

    @State private var tab: Tab = .stash
    enum Tab { case stash, keys }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack(alignment: .top) {
                switch tab {
                case .stash:
                    if libraryAvailable {
                        StashGrid(actions: actions)
                    } else {
                        FullAccessPrompt()
                    }
                case .keys:
                    TypingKeys(actions: actions)
                }
                if let banner = actions.banner {
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
        }
        .animation(.default, value: actions.banner)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $tab) {
                Image(systemName: "tray.full").tag(Tab.stash).accessibilityLabel("Stash")
                Text("ABC").tag(Tab.keys)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            if case .available = actions.polishAvailability {
                Menu {
                    ForEach(PolishStyle.allCases) { style in
                        Button(style.title, systemImage: style.symbol) { Task { await actions.polish(style) } }
                    }
                } label: {
                    if actions.isPolishing {
                        ProgressView()
                    } else {
                        Label("Polish", systemImage: "wand.and.stars").labelStyle(.titleAndIcon).font(.subheadline)
                    }
                }
                .accessibilityHint("Rewrites the selected text, or the text before the cursor, with Apple Intelligence")
            }

            if actions.needsGlobe {
                Button { actions.nextKeyboard() } label: { Image(systemName: "globe") }
                    .accessibilityLabel("Next keyboard")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}

/// Library grid, grouped by category, pinned and manual order first.
private struct StashGrid: View {
    let actions: KeyboardActions
    @Query(sort: \StashItem.sortIndex, order: .reverse) private var items: [StashItem]
    @State private var kind: ItemKind?

    private var visible: [StashItem] {
        let filtered = kind.map { k in items.filter { $0.kind == k } } ?? items
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, title: "All", colour: .secondary)
                    ForEach(ItemKind.allCases) { k in chip(k, title: k.shortTitle, colour: CategoryColours.color(for: k)) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            if visible.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "tray",
                                       description: Text("Share to Stash from any app, or open Stash to paste."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
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
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    private func chip(_ k: ItemKind?, title: String, colour: Color) -> some View {
        Button { kind = k } label: {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(kind == k ? colour.opacity(0.25) : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(kind == k ? colour : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == k ? .isSelected : [])
    }
}

private struct KeyboardItemCell: View {
    let item: StashItem

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnails only: the keyboard has a small memory budget, so full files are never loaded here.
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(CategoryColours.color(for: item.kind).opacity(0.15))
                if let data = item.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: item.kind.symbol).font(.caption).foregroundStyle(CategoryColours.color(for: item.kind))
                }
            }
            .frame(width: 32, height: 32)
            Text(item.displayTitle).font(.footnote).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
        }
        .padding(6)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct FullAccessPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Allow Full Access", systemImage: "lock")
        } description: {
            Text("To show your Stash library here, go to Settings › General › Keyboard › Keyboards › Stash and turn on Allow Full Access. The keyboard doesn't connect to the internet or store what you type.")
        }
    }
}
