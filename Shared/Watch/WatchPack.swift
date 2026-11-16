import Foundation

/// What the iPhone sends to the Apple Watch. The watch has no Core Image and no
/// access to the Keychain or CloudKit store, so the iPhone renders each code to a
/// PNG and sends this small manifest alongside.
struct WatchCard: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case wifi, member, qr }

    var id: UUID
    var title: String
    var kind: Kind
    var hueName: String
    var caption: String
    /// File name of the PNG in the watch's App Group "Watch" folder.
    var imageFile: String
    var updatedAt: Date

    var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .member: "barcode"
        case .qr: "qrcode"
        }
    }
}

struct WatchSnippet: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var hueName: String
}

struct WatchPack: Codable, Equatable, Sendable {
    static let maxSnippets = 25
    static let contextKey = "pack"

    var cards: [WatchCard] = []
    var snippets: [WatchSnippet] = [] {
        didSet { if snippets.count > Self.maxSnippets { snippets = Array(snippets.prefix(Self.maxSnippets)) } }
    }
    var generatedAt = Date()

    init(cards: [WatchCard] = [], snippets: [WatchSnippet] = [], generatedAt: Date = Date()) {
        self.cards = cards
        self.snippets = Array(snippets.prefix(Self.maxSnippets))
        self.generatedAt = generatedAt
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data?) -> WatchPack? { data.flatMap { try? JSONDecoder().decode(WatchPack.self, from: $0) } }

    /// The watch's local copy (shared with its complications).
    static var folder: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Watch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var manifestURL: URL { folder.appendingPathComponent("pack.json") }

    static func loadLocal() -> WatchPack { decode(try? Data(contentsOf: manifestURL)) ?? WatchPack() }
    func saveLocal() { try? encoded().write(to: Self.manifestURL, options: .atomic) }

    /// Unique file name per card version, so an updated card replaces its image.
    static func imageFile(for id: UUID, updatedAt: Date) -> String {
        "card-\(id.uuidString)-\(Int(updatedAt.timeIntervalSince1970)).png"
    }
}
