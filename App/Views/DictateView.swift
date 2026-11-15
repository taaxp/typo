import SwiftUI
import SwiftData

/// Tap the mic, speak, then let Apple Intelligence tidy it up or turn it into a
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

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    micButton
                    Text(statusText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Text") {
                TextEditor(text: $draft)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty && dictation.state != .listening {
                            Text("Tap the mic and start talking, or type here.")
                                .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                if original != nil {
                    Button("Undo Polish", systemImage: "arrow.uturn.backward") {
                        if let original { draft = original }
                        self.original = nil
                    }
                }
            }

            Section {
                switch TextPolisher.availability {
                case .available:
                    ForEach(PolishStyle.allCases) { style in
                        Button { Task { await polish(style) } } label: {
                            HStack {
                                Label(style.title, systemImage: style.symbol)
                                Spacer()
                                if polishing == style { ProgressView() }
                            }
                        }
                        .disabled(draft.isEmpty || polishing != nil)
                    }
                case .unavailable(let reason):
                    Text(reason).foregroundStyle(.secondary)
                }
            } header: {
                Text("Polish with Apple Intelligence")
            } footer: {
                Text("Runs on this device. Your words aren't sent anywhere.")
            }

            Section("Tags") { TagPicker(selection: $tags) }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictate")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { Task { await dictation.stop(); dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text: draft)
                    model.show("Copied")
                }
                .disabled(draft.isEmpty)
            }
        }
        .onChange(of: dictation.transcript) { _, new in
            if dictation.state == .listening { draft = new }
        }
        .onDisappear { Task { await dictation.stop() } }
    }

    private var micButton: some View {
        Button {
            Task {
                if dictation.state != .listening {
                    dictation.reset()
                    original = nil
                }
                await dictation.toggle()
            }
        } label: {
            Image(systemName: dictation.state == .listening ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(dictation.state == .listening ? Color.red : Color.accentColor, in: Circle())
                .symbolEffect(.pulse, isActive: dictation.state == .listening)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.state == .listening ? "Stop dictating" : "Start dictating")
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
        StashLibrary(context: context).save(snippet, tags: tags)
        model.show("Saved")
        dismiss()
    }
}
