import SwiftUI
import SwiftData

/// Opened from Control Centre, the Lock Screen, the Action button or typo://quicksave.
/// One tap on Paste saves the clipboard (no "Allow Paste?" prompt) with the chosen tags.
struct QuickSaveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [Tag] = []
    @State private var collections: [TypoCollection] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    HueTile(hue: Hues.named("Ocean"), symbol: "doc.on.clipboard.fill", size: 64)
                    Text("Save your clipboard").font(.title2.weight(.bold))
                    Text("Pick tags first if you want them, then tap Paste.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    PasteButton(supportedContentTypes: [.item]) { providers in
                        Task { await save(providers) }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .tint(Hues.named("Ocean").base)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tag on the way in").font(.headline)
                    TagPicker(selection: $tags)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add to collections").font(.headline)
                    CollectionPicker(selection: $collections)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .padding(20)
        }
        .background { AmbientBackground(hues: [Hues.named("Ocean"), Hues.named("Lagoon"), Hues.named("Dusk")]) }
        .navigationTitle("Quick Save")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
        }
    }

    private func save(_ providers: [NSItemProvider]) async {
        let drafts = await Ingest.drafts(from: providers)
        guard !drafts.isEmpty else { model.show("Clipboard is empty"); return }
        let saved = TypoLibrary(context: context).save(drafts, tags: tags)
        collections.forEach { CollectionLibrary(context: context).add(saved, to: $0) }
        model.show(drafts.count == 1 ? "Saved" : "Saved \(drafts.count) items")
        dismiss()
    }
}
