import Testing
import Foundation
import SwiftData
@testable import Typo

@Suite("Collections")
@MainActor
struct CollectionTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: TypoStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: TypoStore.schema, configurations: [config]))
    }

    @Test func keepsManualOrderAndCounts() throws {
        let context = try makeContext()
        let library = CollectionLibrary(context: context)
        let jobs = library.create(name: "Steve Jobs")
        let quote = TypoItem(kind: .text, text: "Stay hungry, stay foolish.")
        let speech = TypoItem(kind: .link, title: "Commencement speech", text: "https://www.youtube.com/watch?v=example")
        let photo = TypoItem(kind: .photo, title: "Keynote")
        [quote, speech, photo].forEach(context.insert)

        library.add([quote], to: jobs)
        library.add([speech], to: jobs)
        library.add([photo], to: jobs)
        // Newest additions go to the front.
        #expect(library.orderedItems(jobs).map(\.title) == ["Keynote", "Commencement speech", ""])

        library.move(in: jobs, from: IndexSet(integer: 2), to: 0)
        #expect(library.orderedItems(jobs).first?.kind == .text)

        let summary = library.summary(jobs)
        #expect(summary.map(\.kind) == [.text, .link, .photo])
        #expect(speech.isVideoLink)
    }

    @Test func removingAnItemKeepsItInTheLibrary() throws {
        let context = try makeContext()
        let library = CollectionLibrary(context: context)
        let c = library.create(name: "Trip")
        let item = TypoItem(kind: .text, text: "Booking ref ABC123")
        context.insert(item)
        library.add([item], to: c)
        library.remove([item], from: c)
        #expect(c.count == 0)
        #expect(try context.fetch(FetchDescriptor<TypoItem>()).count == 1)
    }
}
