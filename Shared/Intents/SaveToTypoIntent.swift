import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// "Save to Typo" for Shortcuts and the Action button.
///
/// Typical Shortcut:  Get Clipboard → Save to Typo (Tags: Work)
/// Shortcuts passes text, URLs, images and files; each is classified like a share.
struct SaveToTypoIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Typo"
    static let description = IntentDescription("Saves text, links, photos, GIFs or files to Typo, optionally with tags.")

    @Parameter(title: "Text or Link")
    var text: String?

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]?

    @Parameter(title: "Tags")
    var tags: [TagEntity]?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) \(\.$files) to Typo") {
            \.$tags
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        var drafts: [IngestDraft] = []
        if let text, let draft = Ingest.draft(fromText: text) { drafts.append(draft) }
        for file in files ?? [] {
            let type = file.type ?? UTType(filenameExtension: (file.filename as NSString).pathExtension) ?? .data
            if type.conforms(to: .plainText), let string = String(data: file.data, encoding: .utf8),
               let draft = Ingest.draft(fromText: string) {
                drafts.append(draft)
            } else {
                drafts.append(try Ingest.draft(fromData: file.data, type: type, filename: file.filename))
            }
        }
        guard !drafts.isEmpty else { throw IngestError.nothingUsable }

        let container = try SharedContainer.app()
        let library = TypoLibrary(context: container.mainContext)
        let tagModels = (tags ?? []).compactMap { library.tag(named: $0.name, create: true) }
        let saved = library.save(drafts, tags: tagModels)
        let noun = saved.count == 1 ? "item" : "items"
        return .result(value: saved.count, dialog: "Saved \(saved.count) \(noun) to Typo.")
    }
}

/// One container per process, shared by the app UI and intents running in the app.
@MainActor
enum SharedContainer {
    private static var cached: ModelContainer?

    static func app() throws -> ModelContainer {
        if let cached { return cached }
        let container = try TypoStore.makeContainer(role: .app)
        cached = container
        return container
    }
}

// MARK: - Tags as Shortcuts entities

struct TagEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tag"
    static let defaultQuery = TagQuery()

    var id: String          // tag name, case-insensitive match
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TagQuery: EntityStringQuery {
    @MainActor
    private func all() throws -> [TagEntity] {
        let container = try SharedContainer.app()
        return TypoLibrary(context: container.mainContext).allTags().map { TagEntity(id: $0.name, name: $0.name) }
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TagEntity] {
        let wanted = Set(identifiers.map { $0.lowercased() })
        // Unknown names are still returned so a Shortcut can create a tag on the way in.
        let existing = try all().filter { wanted.contains($0.id.lowercased()) }
        let missing = identifiers.filter { id in !existing.contains { $0.id.lowercased() == id.lowercased() } }
        return existing + missing.map { TagEntity(id: $0, name: $0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TagEntity] {
        try all().filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TagEntity] { try all() }
}

// MARK: - App Shortcuts (appear in Spotlight, Shortcuts and the Action button picker)

struct TypoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenQuickSaveIntent(),
                    phrases: ["Quick save to \(.applicationName)", "Save clipboard to \(.applicationName)"],
                    shortTitle: "Quick Save", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: SaveToTypoIntent(),
                    phrases: ["Save to \(.applicationName)"],
                    shortTitle: "Save to Typo", systemImageName: "plus.square.on.square")
        AppShortcut(intent: ShowCodeIntent(),
                    phrases: ["Show my \(\.$code) in \(.applicationName)", "Show \(\.$code) from \(.applicationName)"],
                    shortTitle: "Show Code", systemImageName: "qrcode")
        AppShortcut(intent: CopyItemIntent(),
                    phrases: ["Copy \(\.$item) from \(.applicationName)", "Copy my \(\.$item) with \(.applicationName)"],
                    shortTitle: "Copy from Typo", systemImageName: "doc.on.doc")
        AppShortcut(intent: CopyWiFiPasswordIntent(),
                    phrases: ["Copy my \(\.$code) password with \(.applicationName)", "Copy the \(\.$code) Wi-Fi password from \(.applicationName)"],
                    shortTitle: "Copy Wi-Fi Password", systemImageName: "wifi")
        AppShortcut(intent: OpenCollectionIntent(),
                    phrases: ["Open my \(\.$target) collection in \(.applicationName)", "Show \(\.$target) in \(.applicationName)"],
                    shortTitle: "Open Collection", systemImageName: "square.stack.3d.up")
    }
}
