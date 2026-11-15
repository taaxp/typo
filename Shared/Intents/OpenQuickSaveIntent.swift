import AppIntents
import Foundation

/// Opens Stash straight to Quick Save (paste + tag). Used by the Control Centre
/// control, the Lock Screen widget and the Action button.
///
/// Why open the app instead of saving silently in the background: reading the
/// clipboard from the background is not permitted, and a programmatic read in the
/// foreground shows the "Allow Paste?" prompt. Quick Save uses the system Paste
/// button, which never prompts. For a fully silent save, use the "Save to Stash"
/// action in a Shortcut after Shortcuts' own "Get Clipboard" step.
struct OpenQuickSaveIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Save to Stash"
    static let description = IntentDescription("Opens Stash ready to save what's on your clipboard and tag it.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(AppRoute.quickSave.rawValue, forKey: AppGroup.Key.pendingRoute)
        return .result()
    }
}

/// Deep-link destinations, used by intents (via shared defaults) and the `stash://` URL scheme.
enum AppRoute: String {
    case quickSave = "quicksave"
    case dictate = "dictate"
    case sync = "sync"

    init?(url: URL) {
        guard url.scheme == "stash", let host = url.host() else { return nil }
        self.init(rawValue: host)
    }

    var url: URL { URL(string: "stash://\(rawValue)")! }
}
