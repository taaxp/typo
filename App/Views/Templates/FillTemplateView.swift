import SwiftUI

/// Fill in a template's fields, preview the result, then copy it.
struct FillTemplateView: View {
    let item: TypoItem
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var fields: [TemplateField] {
        #if os(macOS)
        Template.fields(in: item.text, clipboardReadable: true)
        #else
        Template.fields(in: item.text)
        #endif
    }

    private var clipboard: String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        nil   // reading it on iOS would show the paste prompt; the field has a Paste button instead
        #endif
    }

    private var rendered: Template.Rendered {
        Template.render(item.text, values: values, clipboard: clipboard)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(field.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack {
                                TextField(field.defaultValue.isEmpty ? field.name : field.defaultValue,
                                          text: Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 }))
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                if field.id == "clipboard" {
                                    PasteButton(payloadType: String.self) { strings in
                                        values["clipboard"] = strings.first ?? ""
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonBorderShape(.circle)
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Label("Preview", systemImage: "eye").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(rendered.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
                .background(Hues.named("Dusk").softGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(20)
        }
        .background { AmbientBackground(hues: [Hues.named("Dusk"), Hues.named("Mist"), Hues.named("Ocean")]) }
        .navigationTitle(item.displayTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text: rendered.text)
                    model.show("Copied")
                    dismiss()
                }
            }
        }
    }
}
