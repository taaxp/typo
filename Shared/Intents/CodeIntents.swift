import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

/// "Show my gym card" / "Show guest Wi-Fi" from Siri, Spotlight, Shortcuts or the
/// Action button. Opens Typo straight to the full-screen, bright code.
struct ShowCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Code"
    static let description = IntentDescription("Shows a saved member card or QR code full screen, ready to scan.")
    static let openAppWhenRun = true

    @Parameter(title: "Code")
    var code: CodeEntity

    static var parameterSummary: some ParameterSummary { Summary("Show \(\.$code)") }

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(code.id.uuidString, forKey: AppGroup.Key.pendingCodeID)
        return .result()
    }
}

struct CodeEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Code"
    static let defaultQuery = CodeQuery()

    var id: UUID
    var title: String
    var isMember: Bool

    /// Only the name and type are indexed: never the content or a Wi-Fi password.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.contentDescription = isMember ? "Member card" : "QR code"
        return attributes
    }

    var hideInSpotlight: Bool { !SpotlightSettings.isEnabled }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              subtitle: LocalizedStringResource(stringLiteral: isMember ? "Member card" : "QR code"),
                              image: .init(systemName: isMember ? "barcode" : "qrcode"))
    }
}

struct CodeQuery: EntityStringQuery, IndexedEntityQuery {
    @MainActor
    private func all() throws -> [CodeEntity] {
        let context = try SharedContainer.app().mainContext
        return try context.fetch(FetchDescriptor<CodeItem>(sortBy: [SortDescriptor(\.title)]))
            .map { CodeEntity(id: $0.uuid, title: $0.title, isMember: $0.isMemberCard) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CodeEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [CodeEntity] {
        try all().filter { $0.title.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CodeEntity] { try all() }

    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndex.index.indexAppEntities(try await entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndex.reindexAll()
    }
}
