import Foundation

/// What the Home Screen / StandBy widget shows. The app renders the code to a PNG
/// in the App Group so the widget never needs SwiftData or the Keychain.
struct WidgetSnapshot: Codable, Sendable {
    var title: String
    var caption: String
    var hueName: String
    var updatedAt: Date

    static var folder: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var imageURL: URL { folder.appendingPathComponent("code.png") }
    static var metaURL: URL { folder.appendingPathComponent("code.json") }

    static func load() -> (WidgetSnapshot, Data)? {
        guard let meta = try? Data(contentsOf: metaURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: meta),
              let image = try? Data(contentsOf: imageURL) else { return nil }
        return (snapshot, image)
    }

    static func save(_ snapshot: WidgetSnapshot, png: Data) throws {
        try png.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(snapshot).write(to: metaURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}
