import Foundation
import SwiftData

/// Builds the SwiftData container for each process.
///
/// Design:
/// - The **app** (iOS and macOS) owns the store and syncs it to the user's private
///   CloudKit database.
/// - The **keyboard** opens the same store read-only and without CloudKit, so it
///   never runs sync work inside the keyboard's tight memory limit.
/// - The **share extension** never writes to the store. It drops files into the
///   App Group inbox (see `Inbox`) and the app imports them. This avoids two
///   processes running CloudKit mirroring on one store.
enum TypoStore {
    enum Role { case app, readOnly }

    static let schema = Schema([TypoItem.self, Tag.self, TypoCollection.self, CodeItem.self])

    static func makeContainer(role: Role) throws -> ModelContainer {
        // Same layout on iPhone, iPad and Mac: the store lives in the App Group so
        // the keyboard and share extensions (iOS and Mac) can read it.
        let config: ModelConfiguration
        switch role {
        case .app:
            config = ModelConfiguration(
                "Typo",
                schema: schema,
                groupContainer: .identifier(AppGroup.id),
                cloudKitDatabase: .private(AppGroup.cloudKitContainer)
            )
        case .readOnly:
            config = ModelConfiguration(
                "Typo",
                schema: schema,
                allowsSave: false,
                groupContainer: .identifier(AppGroup.id),
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor
    static func preview() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext
        let work = Tag(name: "Work", hueName: "Mist")
        ctx.insert(work)
        let a = TypoItem(kind: .text, text: "Thanks for getting in touch. I'll reply by end of day.")
        a.tags = [work]
        ctx.insert(a)
        let b = TypoItem(kind: .link, title: "Swift documentation", text: "https://www.swift.org/documentation/")
        b.isPinned = true
        ctx.insert(b)
        return container
    }
}
