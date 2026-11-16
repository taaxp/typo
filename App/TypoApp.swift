import SwiftUI
import SwiftData

@main
struct TypoApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer

    init() {
        do {
            container = try SharedContainer.app()
        } catch {
            // Usually a schema/entitlement mismatch during development.
            fatalError("Could not open the Typo library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in model.open(AppRoute(url: url)) }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Save from Clipboard") { model.open(.quickSave) }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Dictate") { model.open(.dictate) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("New QR Code") { model.open(.newCode) }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                Button("New Collection") { model.open(.newCollection) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Quick Panel") { model.mac.togglePanel() }
            }
        }
        #endif

        #if os(macOS)
        Settings {
            NavigationStack { SettingsView() }
                .environment(model)
                .modelContainer(container)
        }

        MenuBarExtra("Typo", systemImage: "square.stack.3d.up.fill") {
            QuickPanelView(history: model.mac.history, close: {})
                .modelContainer(container)
                .environment(model)
                .frame(width: 560, height: 440)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

/// App-wide UI state and services.
@MainActor
@Observable
final class AppModel {
    var route: AppRoute?
    var filter: LibraryFilter? = .recents
    var scanning = false
    var presentingCode: CodeDraft?
    var toast: String?

    let sync = SyncMonitor()
    let assistant = SaveAssistant()
    let vaultLock = VaultLock()
    let vault = VaultStore()
    #if os(macOS)
    let mac = MacController()
    #endif

    /// Routes from URLs, intents, widgets and menus.
    func open(_ route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .codes: filter = .codes
        case .vault: filter = .vault
        case .scan:
            #if os(iOS)
            scanning = true
            #else
            break   // no live scanner on Mac
            #endif
        default: self.route = route
        }
    }

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == message { toast = nil }
        }
    }
}

/// Hooks the app lifecycle: imports the extension inbox, ages out Recents,
/// fetches link titles, starts the assistant and picks up routes set by intents.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        LibraryView()
            .overlay(alignment: .bottom) { ToastView(message: model.toast) }
            .overlay(alignment: .top) { foundCodeBanner }
            .sheet(item: Binding(get: { model.route?.isSheet == true ? model.route : nil },
                                 set: { model.route = $0 })) { route in
                NavigationStack {
                    switch route {
                    case .quickSave: QuickSaveView()
                    case .dictate: DictateView()
                    case .sync: SyncStatusView()
                    case .newCode: QRStudioView()
                    case .newCollection:
                        CollectionEditor(collection: nil) { model.filter = .collection($0) }
                    default: EmptyView()
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $model.scanning) { ScanView() }
            .fullScreenCover(item: $model.presentingCode) { PresentCodeView(draft: $0) }
            #else
            .sheet(item: $model.presentingCode) { PresentCodeView(draft: $0).frame(minWidth: 520, minHeight: 640) }
            #endif
            .task {
                model.assistant.start(container: context.container)
                #if os(macOS)
                model.mac.start(container: context.container, model: model)
                #endif
                await refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .typoInboxChanged)) { _ in
                Task { await refresh() }
            }
            .onAppear { InboxObserver.start() }
    }

    /// "Found a QR code in that photo" offer.
    @ViewBuilder
    private var foundCodeBanner: some View {
        if let found = model.assistant.foundCode {
            HStack(spacing: 12) {
                HueTile(hue: Hues.named("Lagoon"), symbol: "qrcode", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found a QR code").font(.subheadline.weight(.semibold))
                    Text(found.payload).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Save") {
                    let library = TypoLibrary(context: context)
                    if case .link(let url) = found.parsed { library.save(Ingest.draft(fromURL: url)) }
                    else if let draft = Ingest.draft(fromText: found.payload) { library.save(draft) }
                    model.assistant.foundCode = nil
                    model.show("Saved")
                }
                .buttonStyle(.glass)
                Button { model.assistant.foundCode = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func refresh() async {
        let library = TypoLibrary(context: context)
        let imported = library.importInbox()
        if imported > 0 { model.show("Saved \(imported) from Share") }
        library.ageOutRecents()
        if let raw = AppGroup.defaults.string(forKey: AppGroup.Key.pendingRoute) {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingRoute)
            model.open(AppRoute(rawValue: raw))
        }
        if let raw = AppGroup.defaults.string(forKey: AppGroup.Key.pendingCodeID), let id = UUID(uuidString: raw) {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingCodeID)
            let codes = (try? context.fetch(FetchDescriptor<CodeItem>(predicate: #Predicate { $0.uuid == id }))) ?? []
            if let code = codes.first { model.presentingCode = CodeLibrary(context: context).draft(for: code) }
        }
        await library.fetchMissingLinkTitles()
    }
}

extension AppRoute: Identifiable { var id: String { rawValue } }

extension Notification.Name {
    static let typoInboxChanged = Notification.Name("TypoInboxChanged")
}

/// Bridges the extension's Darwin notification into NotificationCenter.
enum InboxObserver {
    nonisolated(unsafe) private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async { NotificationCenter.default.post(name: .typoInboxChanged, object: nil) }
            },
            AppGroup.inboxDarwinNotification as CFString, nil, .deliverImmediately)
    }
}
