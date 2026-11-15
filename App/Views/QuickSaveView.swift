import SwiftUI
import SwiftData

/// Opened from Control Centre, the Lock Screen, the Action button or stash://quicksave.
/// One tap on Paste saves the clipboard (no "Allow Paste?" prompt) with the chosen tags.
struct QuickSaveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [Tag] = []

    var body: some View {
        Form {
            Section {
                PasteButton(supportedContentTypes: [.item]) { providers in
                    Task { await save(providers) }
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            } footer: {
                Text("Saves whatever is on your clipboard. Choose tags first if you want them.")
            }
            Section("Tag on the way in") {
                TagPicker(selection: $tags)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Quick Save")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func save(_ providers: [NSItemProvider]) async {
        let drafts = await Ingest.drafts(from: providers)
        guard !drafts.isEmpty else { model.show("Clipboard is empty"); return }
        _ = StashLibrary(context: context).save(drafts, tags: tags)
        model.show(drafts.count == 1 ? "Saved" : "Saved \(drafts.count) items")
        dismiss()
    }
}
