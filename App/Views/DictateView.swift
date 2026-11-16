import SwiftUI
import SwiftData

/// Tap the orb, speak, then let Apple Intelligence tidy it up or turn it into a
/// well-formed prompt. Save as a snippet or copy.
struct DictateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var dictation = Dictation()
    @State private var draft = ""
    @State private var original: String?
    @State private var polishing: PolishStyle?
    @State private var tags: [Tag] = []
    @State private var collections: [TypoCollection] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                orb
                Text(statusText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

                // Transcript card
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty && dictation.state != .listening {
                                Text("Tap the orb and start talking, or type here.")
                                    .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    if original != nil {
                        Button("Undo Polish", systemImage: "arrow.uturn.backward") {
                            if let original { draft = original }
                            self.original = nil
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                polishStrip

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tags").font(.headline)
                    TagPicker(selection: $tags)
                    Text("Collections").font(.headline).padding(.top, 6)
                    CollectionPicker(selection: $collections)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(20)
        }
        .background { AmbientBackground(hues: [Hues.named("Dusk"), Hues.named("Ocean"), Hues.named("Blush")]) }
        .navigationTitle("Dictate")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { Task { await dictation.stop(); dismiss() } }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text: draft)
                    model.show("Copied")
                }
                .disabled(draft.isEmpty)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { Task { await save() } }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: dictation.transcript) { _, new in
            if dictation.state == .listening { draft = new }
        }
        .onDisappear { Task { await dictation.stop() } }
    }

    /// Gradient orb with a Liquid Glass ring. Pulses while listening.
    private var orb: some View {
        let listening = dictation.state == .listening
        let hue = listening ? Hues.named("Coral") : Hues.named("Dusk")
        return Button {
            Task {
                if !listening {
                    dictation.reset()
                    original = nil
                }
                await dictation.toggle()
            }
        } label: {
            ZStack {
                Circle().fill(hue.gradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: hue.base.opacity(0.5), radius: 24, y: 8)
                Image(systemName: listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: listening)
            }
            .padding(10)
            .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel(listening ? "Stop dictating" : "Start dictating")
    }

    /// One glass chip per polish style, each with its own hue.
    @ViewBuilder
    private var polishStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Polish with Apple Intelligence", systemImage: "sparkles")
                .font(.headline)
            switch TextPolisher.availability {
            case .available:
                GlassEffectContainer(spacing: 10) {
                    FlowLayout(spacing: 10) {
                        ForEach(PolishStyle.allCases) { style in
                            Button { Task { await polish(style) } } label: {
                                HStack(spacing: 6) {
                                    if polishing == style { ProgressView().controlSize(.small) }
                                    else { Image(systemName: style.symbol).foregroundStyle(style.hue.gradient) }
                                    Text(style.title).font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.tint(style.hue.base.opacity(0.18)).interactive())
                            .disabled(draft.isEmpty || polishing != nil)
                        }
                    }
                }
                Text("Runs on this device. Your words aren't sent anywhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .unavailable(let reason):
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        switch dictation.state {
        case .idle: "Tap to dictate"
        case .preparing: "Getting ready… (the first time downloads the speech model)"
        case .listening: "Listening. Tap to stop."
        case .failed(let message): message
        }
    }

    private func polish(_ style: PolishStyle) async {
        if dictation.state == .listening { await dictation.stop() }
        polishing = style
        defer { polishing = nil }
        do {
            let before = draft
            draft = try await TextPolisher.polish(draft, style: style)
            if original == nil { original = before }
        } catch {
            model.show("Couldn't polish: \(error.localizedDescription)")
        }
    }

    private func save() async {
        await dictation.stop()
        guard let snippet = Ingest.draft(fromText: draft) else { return }
        let item = TypoLibrary(context: context).save(snippet, tags: tags)
        collections.forEach { CollectionLibrary(context: context).add([item], to: $0) }
        model.show("Saved")
        dismiss()
    }
}
