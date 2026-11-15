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
enum StashStore {
    enum Role { case app, readOnly }

    static let schema = Schema([StashItem.self, Tag.self])

    static func makeContainer(role: Role) throws -> ModelContainer {
        let config: ModelConfiguration
        #if os(iOS)
        switch role {
        case .app:
            config = ModelConfiguration(
                "Stash",
                schema: schema,
                groupContainer: .identifier(AppGroup.id),
                cloudKitDatabase: .private(AppGroup.cloudKitContainer)
            )
        case .readOnly:
            config = ModelConfiguration(
                "Stash",
                schema: schema,
                allowsSave: false,
                groupContainer: .identifier(AppGroup.id),
                cloudKitDatabase: .none
            )
        }
        #else
        config = ModelConfiguration(
            "Stash",
            schema: schema,
            cloudKitDatabase: .private(AppGroup.cloudKitContainer)
        )
        #endif
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor
    static func preview() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext
        let work = Tag(name: "Work", colorHex: "#007AFF")
        ctx.insert(work)
        let a = StashItem(kind: .text, text: "Thanks for getting in touch. I'll reply by end of day.")
        a.tags = [work]
        ctx.insert(a)
        let b = StashItem(kind: .link, title: "Swift documentation", text: "https://www.swift.org/documentation/")
        b.isPinned = true
        ctx.insert(b)
        return container
    }
}
