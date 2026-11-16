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

    /// Shared defaults: the App Group suite, so each app and its extensions
    /// (keyboard, share, widgets, complications) see the same settings.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    /// Root of the App Group container, or Application Support if the group
    /// isn't available (e.g. unsigned development builds).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
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
        static let pendingCodeID = "pendingCodeID"        // set by ShowCodeIntent
        static let recentsAgeOutDays = "recentsAgeOutDays"
        static let lastExport = "sync.lastExport"
        static let lastImport = "sync.lastImport"
        static let lastSyncError = "sync.lastError"
        static let keyboardLastRefresh = "keyboard.lastRefresh"
    }
}
