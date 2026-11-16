import SwiftUI
import SwiftData

/// The "Share to Typo" sheet, used by the iOS and Mac share extensions.
/// It classifies what was shared, lets you tag it and pick collections, then
/// drops it in the App Group inbox for the app to import.
enum ShareData {
    /// Reads tag names (read-only) so you can pick existing tags.
    @MainActor
    static func existingTags() -> [(name: String, hue: String)] {
        guard let container = try? TypoStore.makeContainer(role: .readOnly) else { return [] }
        let tags = (try? ModelContext(container).fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return tags.map { ($0.name, $0.hueName) }
    }

    /// Collection names and hues, so a share can go straight into a collection.
    @MainActor
    static func existingCollections() -> [(name: String, hue: String)] {
        guard let container = try? TypoStore.makeContainer(role: .readOnly) else { return [] }
        let items = (try? ModelContext(container).fetch(FetchDescriptor<TypoCollection>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return items.map { ($0.name, $0.hueName) }
    }
}

struct ShareView: View {
    let providers: [NSItemProvider]
    let existingTags: [(name: String, hue: String)]
    let existingCollections: [(name: String, hue: String)]
    let finish: () -> Void
    let cancel: () -> Void

    @State private var drafts: [IngestDraft] = []
    @State private var loading = true
    @State private var selectedTags: Set<String> = []
    @State private var selectedCollections: Set<String> = []
    @State private var newCollection = ""
    @State private var newTag = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(loading ? "Reading…" : "Saving \(drafts.count) item\(drafts.count == 1 ? "" : "s")") {
                    if loading { ProgressView() }
                    ForEach(Array(drafts.enumerated()), id: \.offset) { _, draft in
                        Label {
                            Text(summary(of: draft)).lineLimit(2)
                        } icon: {
                            HueTile(hue: CategoryColours.hue(for: draft.kind), symbol: draft.kind.symbol, size: 28)
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("Tags") {
                    ForEach(existingTags, id: \.name) { tag in
                        Button {
                            if selectedTags.contains(tag.name) { selectedTags.remove(tag.name) } else { selectedTags.insert(tag.name) }
                        } label: {
                            HStack {
                                HueDot(hue: Hues.named(tag.hue), size: 12)
                                Text(tag.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedTags.contains(tag.name) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    TextField("New tag", text: $newTag)
                }
                Section("Collection") {
                    ForEach(existingCollections, id: \.name) { c in
                        Button {
                            if selectedCollections.contains(c.name) { selectedCollections.remove(c.name) } else { selectedCollections.insert(c.name) }
                        } label: {
                            HStack {
                                HueDot(hue: Hues.named(c.hue), size: 12)
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedCollections.contains(c.name) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    TextField("New collection", text: $newCollection)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Typo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(loading || drafts.isEmpty)
                }
            }
            .task {
                drafts = await Ingest.drafts(from: providers)
                loading = false
                if drafts.isEmpty { error = IngestError.nothingUsable.localizedDescription }
            }
        }
    }

    private func summary(of draft: IngestDraft) -> String {
        switch draft.kind {
        case .text: draft.text
        case .link: draft.text
        case .photo, .gif, .video, .document:
            "\(draft.filename ?? draft.kind.title) · \(ByteCountFormatter.string(fromByteCount: Int64(draft.payload?.count ?? 0), countStyle: .file))"
        }
    }

    private func save() {
        var tags = Array(selectedTags)
        let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { tags.append(typed) }
        do {
            var collections = Array(selectedCollections)
            let typedCollection = newCollection.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typedCollection.isEmpty { collections.append(typedCollection) }
            for draft in drafts { try Inbox.write(draft, tagNames: tags, collectionNames: collections) }
            Inbox.notifyApp()
            finish()
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
