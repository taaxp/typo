import Foundation

/// A drop-box in the App Group container.
///
/// Extensions write one folder per save:
///
///     Inbox/<uuid>/manifest.json
///     Inbox/<uuid>/payload          (optional file bytes)
///
/// The app imports and deletes these on launch, when it becomes active, and when an
/// extension posts the Darwin notification `AppGroup.inboxDarwinNotification`.
struct InboxManifest: Codable, Sendable {
    var kind: ItemKind
    var title: String = ""
    var text: String = ""
    var typeIdentifier: String?
    var filename: String?
    var tagNames: [String] = []
    var createdAt: Date = Date()
}

enum Inbox {
    /// Writes a pending save. Safe to call from any extension.
    static func write(_ draft: IngestDraft, tagNames: [String] = []) throws {
        let folder = AppGroup.inboxURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = draft.payload {
            try data.write(to: folder.appendingPathComponent("payload"), options: .atomic)
        }
        let manifest = InboxManifest(kind: draft.kind, title: draft.title, text: draft.text,
                                     typeIdentifier: draft.typeIdentifier, filename: draft.filename,
                                     tagNames: tagNames)
        // Manifest last: the importer ignores folders without one, so a half-written save is never imported.
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func notifyApp() {
        let centre = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(centre, CFNotificationName(AppGroup.inboxDarwinNotification as CFString),
                                             nil, nil, true)
    }

    /// Pending saves, oldest first. The caller deletes each folder after importing it.
    static func pending() -> [(folder: URL, manifest: InboxManifest, payload: Data?)] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: AppGroup.inboxURL, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? decoder.decode(InboxManifest.self, from: data) else { return nil }
            let payload = try? Data(contentsOf: folder.appendingPathComponent("payload"))
            return (folder, manifest, payload)
        }
        .sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }
}
