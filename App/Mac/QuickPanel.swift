#if os(macOS)
import AppKit
import SwiftUI
import SwiftData
import Observation

/// Owns the Mac-only extras: the global shortcut, the floating quick panel and
/// clipboard history.
@MainActor
@Observable
final class MacController {
    static let comboKey = "mac.hotKeyCombo"

    let history = ClipboardHistory()
    private var hotKey: HotKey?
    private var panel: QuickPanelWindow?
    private weak var container: ModelContainer?
    private weak var model: AppModel?

    var combo: HotKey.Combo {
        get { HotKey.Combo.all.first { $0.title == UserDefaults.standard.string(forKey: Self.comboKey) } ?? .optionSpace }
        set { UserDefaults.standard.set(newValue.title, forKey: Self.comboKey); registerHotKey() }
    }

    func start(container: ModelContainer, model: AppModel) {
        self.container = container
        self.model = model
        registerHotKey()
        history.start()
    }

    private func registerHotKey() {
        hotKey = nil
        hotKey = HotKey(combo) { [weak self] in self?.togglePanel() }
    }

    func togglePanel() {
        guard let container, let model else { return }
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let window = panel ?? QuickPanelWindow.make(content: QuickPanelView(history: history, close: { [weak self] in self?.panel?.orderOut(nil) })
            .modelContainer(container)
            .environment(model))
        panel = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

/// A floating panel that takes key focus for typing without activating Typo, so
/// focus goes back to the previous app when it closes and ⌘V pastes there.
final class QuickPanelWindow: NSPanel {
    /// Uses NSPanel's own initialiser, then configures, to avoid subclass init rules.
    static func make(content: some View) -> QuickPanelWindow {
        let panel = QuickPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                                     styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                                     backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }

    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        orderOut(nil)   // close when you click elsewhere
    }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }   // Esc
}

/// Search and copy without leaving the app you're in.
struct QuickPanelView: View {
    let history: ClipboardHistory
    let close: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \TypoItem.sortIndex, order: .reverse) private var items: [TypoItem]
    @Query(sort: \CodeItem.sortIndex, order: .reverse) private var codes: [CodeItem]
    @State private var search = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private enum Row: Identifiable {
        case item(TypoItem)
        case history(HistoryEntry)
        var id: String {
            switch self {
            case .item(let i): "i" + i.uuid.uuidString
            case .history(let h): "h" + h.uuid.uuidString
            }
        }
    }

    private var rows: [(section: String, rows: [Row])] {
        let match: (String) -> Bool = { search.isEmpty || $0.localizedStandardContains(search) }
        let pinned = items.filter { $0.isPinned && match($0.searchableText) }
        let recent = items.filter { !$0.isPinned && match($0.searchableText) }.prefix(search.isEmpty ? 8 : 30)
        var out: [(String, [Row])] = []
        if !pinned.isEmpty { out.append(("Pinned", pinned.map(Row.item))) }
        if !recent.isEmpty { out.append((search.isEmpty ? "Recent" : "Library", recent.map(Row.item))) }
        if history.isRunning {
            let h = history.recent(limit: 30).filter { match($0.text) }.prefix(search.isEmpty ? 10 : 30)
            if !h.isEmpty { out.append(("Clipboard history", h.map(Row.history))) }
        }
        return out
    }

    private var flat: [Row] { rows.flatMap(\.rows) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Typo", text: $search)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { copy(at: selected) }
                Text("↩ copy · ⌘1–9 · ⌘S save · esc").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rows, id: \.section) { group in
                            Text(group.section).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.top, 8)
                            ForEach(group.rows) { row in
                                let index = flat.firstIndex { $0.id == row.id } ?? 0
                                rowView(row, index: index)
                                    .id(row.id)
                                    .onTapGesture { copy(at: index) }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
                .onChange(of: selected) { _, new in
                    if flat.indices.contains(new) { proxy.scrollTo(flat[new].id) }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { searchFocused = true; selected = 0 }
        .onChange(of: search) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(flat.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if let digit = press.characters.first?.wholeNumberValue, (1...9).contains(digit) {
                copy(at: digit - 1); return .handled
            }
            if press.characters == "s" { saveSelected(); return .handled }
            return .ignored
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, index: Int) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .item(let item):
                ItemThumbnail(item: item, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle).lineLimit(1)
                    if item.kind == .text || item.kind == .link {
                        Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            case .history(let entry):
                HueTile(hue: Hues.named("Fog"), symbol: entry.isImage ? "photo" : "clock.arrow.circlepath", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.text).lineLimit(1)
                    Text("\(entry.sourceApp) · \(entry.copiedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if index < 9 { Text("⌘\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(index == selected ? AnyShapeStyle(Hues.named("Ocean").base.opacity(0.18)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func copy(at index: Int) {
        guard flat.indices.contains(index) else { return }
        switch flat[index] {
        case .item(let item):
            Clipboard.copy([item])
            history.ignoreCurrentChange()
        case .history(let entry): history.copy(entry)
        }
        close()
    }

    private func saveSelected() {
        guard flat.indices.contains(selected), case .history(let entry) = flat[selected] else { return }
        history.saveToTypo(entry, context: context)
    }
}

/// Mac settings: shortcut and clipboard history.
struct MacSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var historyOn = UserDefaults.standard.bool(forKey: ClipboardHistory.enabledKey)
    @State private var combo: HotKey.Combo = .optionSpace

    var body: some View {
        Section {
            Picker("Quick panel shortcut", selection: $combo) {
                ForEach(HotKey.Combo.all) { Text($0.title).tag($0) }
            }
            .onChange(of: combo) { _, new in model.mac.combo = new }
            Toggle("Keep clipboard history on this Mac", isOn: $historyOn)
                .onChange(of: historyOn) { _, on in model.mac.history.isEnabled = on }
            Button("Clear Clipboard History", role: .destructive) { model.mac.history.clear() }
        } header: {
            Text("Mac")
        } footer: {
            Text("History is off until you turn it on. It stays on this Mac (never synced), keeps 200 items for up to 7 days, and skips anything password managers mark as private.")
        }
        .onAppear { combo = model.mac.combo }
    }
}
#endif
