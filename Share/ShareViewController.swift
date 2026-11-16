import UIKit
import SwiftUI
import SwiftData

/// "Share to Typo" from any app. Classifies what was shared, lets you tag it,
/// and drops it in the App Group inbox for the app to import.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let view = ShareView(providers: providers,
                             existingTags: Self.existingTagNames(),
                             existingCollections: Self.existingCollections(),
                             finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                             cancel: { [weak self] in
                                 self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                             })
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Reads tag names (read-only) so you can pick existing tags.
    @MainActor
    private static func existingTagNames() -> [(name: String, hue: String)] {
        guard let container = try? TypoStore.makeContainer(role: .readOnly) else { return [] }
        let tags = (try? ModelContext(container).fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return tags.map { ($0.name, $0.hueName) }
    }

    /// Collection names and hues, so a share can go straight into a collection.
    @MainActor
    private static func existingCollections() -> [(name: String, hue: String)] {
        guard let container = try? TypoStore.makeContainer(role: .readOnly) else { return [] }
        let items = (try? ModelContext(container).fetch(FetchDescriptor<TypoCollection>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return items.map { ($0.name, $0.hueName) }
    }
}

private struct ShareView: View {
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
            .navigationTitle("Typo")
            .navigationBarTitleDisplayMode(.inline)
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
