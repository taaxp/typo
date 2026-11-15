import UIKit
import SwiftUI
import SwiftData

/// "Share to Stash" from any app. Classifies what was shared, lets you tag it,
/// and drops it in the App Group inbox for the app to import.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let view = ShareView(providers: providers,
                             existingTags: Self.existingTagNames(),
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
    private static func existingTagNames() -> [(name: String, hex: String)] {
        guard let container = try? StashStore.makeContainer(role: .readOnly) else { return [] }
        let tags = (try? ModelContext(container).fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return tags.map { ($0.name, $0.colorHex) }
    }
}

private struct ShareView: View {
    let providers: [NSItemProvider]
    let existingTags: [(name: String, hex: String)]
    let finish: () -> Void
    let cancel: () -> Void

    @State private var drafts: [IngestDraft] = []
    @State private var loading = true
    @State private var selectedTags: Set<String> = []
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
                            Image(systemName: draft.kind.symbol).foregroundStyle(CategoryColours.color(for: draft.kind))
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
                                Circle().fill(Color(hex: tag.hex)).frame(width: 12, height: 12)
                                Text(tag.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedTags.contains(tag.name) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    TextField("New tag", text: $newTag)
                }
            }
            .navigationTitle("Stash")
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
        case .photo, .gif, .document:
            "\(draft.filename ?? draft.kind.title) · \(ByteCountFormatter.string(fromByteCount: Int64(draft.payload?.count ?? 0), countStyle: .file))"
        }
    }

    private func save() {
        var tags = Array(selectedTags)
        let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { tags.append(typed) }
        do {
            for draft in drafts { try Inbox.write(draft, tagNames: tags) }
            Inbox.notifyApp()
            finish()
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
