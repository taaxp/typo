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
                .onOpenURL { url in model.route = AppRoute(url: url) }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Save from Clipboard") { model.route = .quickSave }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Dictate") { model.route = .dictate }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            NavigationStack { SettingsView() }
                .environment(model)
                .modelContainer(container)
        }
        #endif
    }
}

/// App-wide UI state.
@MainActor
@Observable
final class AppModel {
    var route: AppRoute?
    var toast: String?
    let sync = SyncMonitor()

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == message { toast = nil }
        }
    }
}

/// Hooks the app lifecycle: imports the extension inbox, ages out Recents,
/// fetches link titles and picks up routes set by intents.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        LibraryView()
            .overlay(alignment: .bottom) { ToastView(message: model.toast) }
            .sheet(item: $model.route) { route in
                NavigationStack {
                    switch route {
                    case .quickSave: QuickSaveView()
                    case .dictate: DictateView()
                    case .sync: SyncStatusView()
                    }
                }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 420)
                #endif
            }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .typoInboxChanged)) { _ in
                Task { await refresh() }
            }
            .onAppear { InboxObserver.start() }
    }

    private func refresh() async {
        let library = TypoLibrary(context: context)
        let imported = library.importInbox()
        if imported > 0 { model.show("Saved \(imported) from Share") }
        library.ageOutRecents()
        if let raw = AppGroup.defaults.string(forKey: AppGroup.Key.pendingRoute) {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingRoute)
            model.route = AppRoute(rawValue: raw)
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
