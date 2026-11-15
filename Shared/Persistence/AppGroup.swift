import Foundation

/// Identifiers shared by the app and its extensions.
///
/// The real values come from Info.plist (`TypoAppGroupID`, `TypoCloudKitContainer`),
/// which XcodeGen fills from the build settings in project.yml, so there is one
/// place to change them.
enum AppGroup {
    static let id: String =
        Bundle.main.object(forInfoDictionaryKey: "TypoAppGroupID") as? String
        ?? "group.com.starconnect.typo"

    static let cloudKitContainer: String =
        Bundle.main.object(forInfoDictionaryKey: "TypoCloudKitContainer") as? String
        ?? "iCloud.com.starconnect.typo"

    /// Shared defaults. On iOS this is the App Group suite so the keyboard, share
    /// extension and widgets see the same settings. The Mac app has no extensions,
    /// so it uses its own defaults.
    static var defaults: UserDefaults {
        #if os(iOS)
        return UserDefaults(suiteName: id) ?? .standard
        #else
        return .standard
        #endif
    }

    /// Root of the shared container (iOS), or Application Support (macOS).
    static var containerURL: URL {
        #if os(iOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typo", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    /// Where extensions drop new saves for the app to import. See `Inbox`.
    static var inboxURL: URL {
        let url = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Darwin notification name an extension posts after writing to the inbox,
    /// so a running app imports straight away.
    static let inboxDarwinNotification = "com.starconnect.typo.inbox-changed"

    /// Keys in `defaults`.
    enum Key {
        static let pendingRoute = "pendingRoute"          // set by intents/controls, read by the app
        static let recentsAgeOutDays = "recentsAgeOutDays"
        static let lastExport = "sync.lastExport"
        static let lastImport = "sync.lastImport"
        static let lastSyncError = "sync.lastError"
        static let keyboardLastRefresh = "keyboard.lastRefresh"
    }
}
