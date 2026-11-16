import SwiftUI
import SwiftData

/// Create and decorate a QR code (or edit a member card's barcode).
struct QRStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var draft: CodeDraft
    var editing: CodeItem?

    @State private var matrix: ModuleMatrix?
    @State private var error: String?
    @State private var scan: ScanCheck.Result?
    @State private var presenting = false
    @State private var emojiBadge = ""
    @State private var png: Data?

    init(draft: CodeDraft = CodeDraft(), editing: CodeItem? = nil) {
        _draft = State(initialValue: draft)
        self.editing = editing
    }

    private var hue: Hue { Hues.named(draft.style.fillHue ?? draft.type.hueName) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                if !draft.isMember { typePicker }
                contentPanel
                if !draft.symbology.isLinear { stylePanel }
            }
            .padding(20)
        }
        .background { AmbientBackground(hues: [hue, Hues.named("Mist"), hue]) }
        .navigationTitle(editing == nil ? (draft.isMember ? "New Member Card" : "New QR Code") : "Edit")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }.disabled(matrix == nil)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task(id: draft.message + "\(draft.style.correction)" + draft.symbology.rawValue) { await regenerate() }
        .task(id: draft) { await verify() }
        #if os(iOS)
        .fullScreenCover(isPresented: $presenting) { PresentCodeView(draft: draft) }
        #else
        .sheet(isPresented: $presenting) { PresentCodeView(draft: draft).frame(minWidth: 520, minHeight: 640) }
        #endif
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 12) {
            if let matrix {
                CodeCard(matrix: matrix, symbology: draft.symbology, style: draft.style,
                         humanReadable: draft.symbology.isLinear ? draft.message : nil)
                    .frame(maxWidth: 300)
                    .animation(.smooth, value: draft.style)
            } else {
                ContentUnavailableView("Add some content", systemImage: "qrcode",
                                       description: Text(error ?? "Your code appears here as you type."))
                    .frame(height: 260)
            }
            scanBadge
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    @ViewBuilder
    private var scanBadge: some View {
        switch scan {
        case .scans:
            Label("Scans", systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(Hues.named("Sage").inkColor)
                .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.tint(Hues.named("Sage").base.opacity(0.2)))
        case .unreadable, .wrongContent:
            Label("May not scan: try a simpler style or a smaller badge", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(Hues.named("Coral").inkColor)
                .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.tint(Hues.named("Coral").base.opacity(0.2)))
        case nil:
            EmptyView()
        }
    }

    // MARK: Type

    private var typePicker: some View {
        GlassEffectContainer(spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(QRPayloadType.allCases) { type in
                    let on = draft.type == type
                    Button { withAnimation(.smooth) { draft.type = type } } label: {
                        Label(type.title, systemImage: type.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Hues.named(type.hueName).inkColor : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(Hues.named(type.hueName).base.opacity(0.25)).interactive() : .regular.interactive())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Content

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (optional)", text: $draft.title)
            Divider()
            if draft.isMember {
                Picker("Barcode type", selection: $draft.symbology) {
                    ForEach(Symbology.allCases) { Text($0.title).tag($0) }
                }
                TextField("Member number", text: $draft.text)
                    #if os(iOS)
                    .keyboardType(draft.symbology == .ean13 || draft.symbology == .upcA ? .numberPad : .asciiCapable)
                    #endif
            } else {
                switch draft.type {
                case .link: TextField("https://", text: $draft.text).urlField()
                case .text: TextField("Text", text: $draft.text, axis: .vertical).lineLimit(3...8)
                case .wifi: WiFiForm(network: $draft.wifi)
                case .contact: ContactForm(contact: $draft.contact)
                case .email:
                    TextField("To", text: $draft.emailTo).emailField()
                    TextField("Subject", text: $draft.emailSubject)
                    TextField("Message", text: $draft.emailBody, axis: .vertical).lineLimit(2...5)
                case .phone: TextField("Phone number", text: $draft.text).phoneField()
                case .sms:
                    TextField("Phone number", text: $draft.smsNumber).phoneField()
                    TextField("Message", text: $draft.smsBody, axis: .vertical).lineLimit(2...5)
                case .location:
                    TextField("Latitude, e.g. -37.8226", text: $draft.latitude)
                    TextField("Longitude, e.g. 144.9654", text: $draft.longitude)
                case .event:
                    TextField("Event name", text: $draft.event.title)
                    DatePicker("Starts", selection: $draft.event.start)
                    DatePicker("Ends", selection: $draft.event.end, in: draft.event.start...)
                    TextField("Location", text: $draft.event.location)
                }
            }
        }
        .textFieldStyle(.plain)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Style

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CodeStyle.presets) { preset in
                        Button {
                            var style = preset.style
                            style.badge = draft.style.badge
                            style.caption = draft.style.caption
                            withAnimation(.smooth) { draft.style = style }
                        } label: {
                            VStack(spacing: 6) {
                                PresetSwatch(style: preset.style).frame(width: 64, height: 64)
                                Text(preset.name).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Picker("Dots", selection: $draft.style.moduleShape) {
                Text("Square").tag(CodeStyle.ModuleShape.square)
                Text("Rounded").tag(CodeStyle.ModuleShape.rounded)
                Text("Dots").tag(CodeStyle.ModuleShape.dots)
                Text("Fluid").tag(CodeStyle.ModuleShape.fluid)
            }
            .pickerStyle(.segmented)
            Picker("Eyes", selection: $draft.style.eyeShape) {
                Text("Square").tag(CodeStyle.EyeShape.square)
                Text("Rounded").tag(CodeStyle.EyeShape.rounded)
                Text("Circle").tag(CodeStyle.EyeShape.circle)
                Text("Leaf").tag(CodeStyle.EyeShape.leaf)
            }
            .pickerStyle(.segmented)

            Text("Colour").font(.subheadline.weight(.semibold))
            Toggle("Plain ink", isOn: Binding(get: { draft.style.fillHue == nil },
                                              set: { draft.style.fillHue = $0 ? nil : draft.type.hueName }))
            if draft.style.fillHue != nil {
                HuePicker(selection: Binding(get: { draft.style.fillHue ?? "Ocean" }, set: { draft.style.fillHue = $0 }))
            }
            Picker("Background", selection: $draft.style.background) {
                Text("White").tag(CodeStyle.Background.white)
                Text("Soft tint").tag(CodeStyle.Background.soft)
                Text("Clear").tag(CodeStyle.Background.clear)
            }

            Text("Centre badge").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    badgeButton(nil, label: Image(systemName: "nosign"))
                    ForEach(["wifi", "heart.fill", "star.fill", "cup.and.saucer.fill", "house.fill", "person.fill", "link"], id: \.self) { name in
                        badgeButton(.symbol(name), label: Image(systemName: name))
                    }
                    TextField("Emoji", text: $emojiBadge)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .onChange(of: emojiBadge) { _, new in
                            if let first = new.first { draft.style.badge = .emoji(String(first)) }
                        }
                }
            }

            Toggle("Frame with caption", isOn: $draft.style.showFrame)
            if draft.style.showFrame {
                TextField(draft.type == .wifi ? "Scan for Wi-Fi" : "Caption", text: $draft.style.caption)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func badgeButton(_ badge: CodeStyle.Badge?, label: Image) -> some View {
        let on = draft.style.badge == badge
        return Button { draft.style.badge = badge; emojiBadge = "" } label: {
            label.font(.title3).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(hue.base.opacity(0.3)).interactive() : .regular.interactive(), in: Circle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Actions

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let png {
                    ShareLink(item: ShareablePNG(data: png, name: draft.suggestedTitle),
                              preview: SharePreview(draft.suggestedTitle)) {
                        Label("Share", systemImage: "square.and.arrow.up").padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                }
                Button { presenting = true } label: {
                    Label("Present", systemImage: "rectangle.portrait.and.arrow.forward").padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .disabled(matrix == nil)
            }
            .controlSize(.large)
        }
        .padding(.bottom, 8)
    }

    private func regenerate() async {
        let message = draft.message
        guard !message.isEmpty else { matrix = nil; error = nil; return }
        do {
            matrix = try CodeGenerator.matrix(for: message, symbology: draft.symbology, correction: draft.style.correction)
            error = nil
        } catch {
            matrix = nil
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        try? await Task.sleep(for: .milliseconds(350))   // debounce while editing
        guard !Task.isCancelled, let matrix else { scan = nil; png = nil; return }
        // Rendered once per edit (debounced) and reused by Share.
        png = CodeExporter.png(matrix: matrix, symbology: draft.symbology, style: draft.style,
                               humanReadable: draft.symbology.isLinear ? draft.message : nil)
        guard let image = CodeExporter.cgImage(matrix: matrix, symbology: draft.symbology, style: draft.style) else {
            scan = nil
            return
        }
        scan = await ScanCheck.verify(image, expecting: draft.message)
    }

    private func save() {
        do {
            try CodeLibrary(context: context).save(draft, into: editing)
            model.show("Saved")
            dismiss()
        } catch {
            model.show("Couldn't save: \(error.localizedDescription)")
        }
    }
}

/// Tiny QR preview for a style preset.
private struct PresetSwatch: View {
    let style: CodeStyle
    private static let sample = try? CodeGenerator.matrix(for: "https://typo.app", symbology: .qr)

    var body: some View {
        if let m = Self.sample {
            CodeCanvas(matrix: m, symbology: .qr, style: style)
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }
}

/// A PNG that ShareLink can hand to AirDrop, Messages, Mail and Files.
struct ShareablePNG: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { "\($0.name).png" }
    }
}

struct WiFiForm: View {
    @Binding var network: WiFiNetwork
    @State private var reveal = false

    var body: some View {
        TextField("Network name (SSID)", text: $network.ssid)
            .autocorrectionDisabled()
        Picker("Security", selection: $network.security) {
            ForEach(WiFiNetwork.Security.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if network.security != .open {
            HStack {
                Group {
                    if reveal { TextField("Password", text: $network.password) } else { SecureField("Password", text: $network.password) }
                }
                .autocorrectionDisabled()
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        Toggle("Hidden network", isOn: $network.hidden)
        Label("Anyone who sees this code can join the network. The password is kept in your iCloud Keychain, not in Typo's library.",
              systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct ContactForm: View {
    @Binding var contact: ContactCard

    var body: some View {
        HStack {
            TextField("First name", text: $contact.givenName)
            TextField("Last name", text: $contact.familyName)
        }
        TextField("Company", text: $contact.organisation)
        TextField("Job title", text: $contact.jobTitle)
        TextField("Phone", text: $contact.phone).phoneField()
        TextField("Email", text: $contact.email).emailField()
        TextField("Website", text: $contact.url).urlField()
        TextField("Address", text: $contact.address, axis: .vertical).lineLimit(1...3)
    }
}

extension View {
    func urlField() -> some View {
        #if os(iOS)
        self.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
    func emailField() -> some View {
        #if os(iOS)
        self.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
    func phoneField() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad)
        #else
        self
        #endif
    }
}
