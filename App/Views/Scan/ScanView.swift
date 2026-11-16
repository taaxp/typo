#if os(iOS)
import SwiftUI
import SwiftData
import VisionKit
import Vision
import Contacts
import ContactsUI

/// Point the camera at a QR code, barcode, printed text or a business card.
/// Tap what it finds; Typo routes each result to the right place.
struct ScanView: View {
    enum Mode: String, CaseIterable { case codes = "Codes & Text", card = "Business Card" }

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .codes
    @State private var results: [ScanResult] = []
    @State private var scanner: DataScannerViewController?
    @State private var newContact: CNContact?
    @State private var studioDraft: CodeDraft?
    @State private var capturing = false

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                LiveScanner(mode: mode, scanner: $scanner) { add($0) }
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Scanning isn't supported on this device", systemImage: "camera.metering.unknown",
                                       description: Text("Live scanning needs an iPhone or iPad with an A12 chip or later."))
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomPanel }
        .sheet(item: Binding(get: { newContact.map(IdentifiedContact.init) }, set: { newContact = $0?.contact })) { wrapped in
            NewContactView(contact: wrapped.contact) { newContact = nil }
        }
        .sheet(item: $studioDraft) { draft in NavigationStack { QRStudioView(draft: draft) } }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                .buttonStyle(.plain).glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Close")
            Spacer()
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .padding(4)
            .glassEffect()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if mode == .card {
                Button { Task { await captureCard() } } label: {
                    ZStack {
                        Circle().fill(Hues.named("Dusk").gradient).frame(width: 70, height: 70)
                        if capturing { ProgressView().tint(.white) } else {
                            Image(systemName: "person.text.rectangle").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        }
                    }
                    .padding(8)
                    .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read business card")
                Text("Fill the frame with the card, then tap").font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6).glassEffect()
            } else if results.isEmpty {
                Label("Tap a highlighted code or text to save it", systemImage: "hand.tap")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect()
            }
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results.reversed()) { result in ScanResultRow(result: result, actions: actions(for: result)) }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .padding(16)
    }

    // MARK: Results

    private func add(_ item: RecognizedItem) {
        let result: ScanResult
        switch item {
        case .barcode(let barcode):
            guard let raw = barcode.payloadStringValue else { return }
            let symbology = SymbologyMapper.from(visionName: barcode.observation.symbology.rawValue)
            result = ScanResult(kind: .code(QRPayload.parse(raw), raw: raw, symbology: symbology))
        case .text(let text):
            result = ScanResult(kind: .text(text.transcript))
        @unknown default:
            return
        }
        guard !results.contains(where: { $0.title == result.title }) else { return }
        withAnimation(.smooth) { results.append(result) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func actions(for result: ScanResult) -> [ScanResultRow.Action] {
        let library = TypoLibrary(context: context)
        var actions: [ScanResultRow.Action] = []
        switch result.kind {
        case .code(let parsed, let raw, _):
            switch parsed {
            case .link(let url):
                actions.append(.init(title: "Save link", symbol: "tray.and.arrow.down") { library.save(Ingest.draft(fromURL: url)); done("Saved") })
                actions.append(.init(title: "Open", symbol: "safari") { UIApplication.shared.open(url) })
            case .wifi(let network):
                actions.append(.init(title: "Save Wi-Fi", symbol: "wifi") {
                    var draft = CodeDraft(); draft.type = .wifi; draft.wifi = network
                    draft.style.caption = "Scan for Wi-Fi"
                    studioDraft = draft
                })
                if !network.password.isEmpty {
                    actions.append(.init(title: "Copy password", symbol: "key") { Clipboard.copySensitive(network.password); done("Copied for 60 seconds") })
                }
            case .contact(let vCard):
                actions.append(.init(title: "Add to Contacts", symbol: "person.badge.plus") {
                    newContact = (try? CNContactVCardSerialization.contacts(with: Data(vCard.utf8)))?.first
                })
                actions.append(saveText(raw, library))
            default:
                if let symbology = result.memberSymbology {
                    actions.append(.init(title: "Save as member card", symbol: "creditcard") {
                        var draft = CodeDraft(); draft.isMember = true; draft.symbology = symbology; draft.text = raw
                        draft.style = CodeStyle(fillHue: nil, showFrame: false)
                        studioDraft = draft
                    })
                }
                actions.append(saveText(raw, library))
            }
            actions.append(.init(title: "Copy", symbol: "doc.on.doc") { Clipboard.copy(text: raw); done("Copied") })
        case .text(let text):
            actions.append(saveText(text, library))
            actions.append(.init(title: "Copy", symbol: "doc.on.doc") { Clipboard.copy(text: text); done("Copied") })
        case .contact(let card):
            actions.append(.init(title: "Add to Contacts", symbol: "person.badge.plus") {
                newContact = (try? CNContactVCardSerialization.contacts(with: Data(QRPayload.contact(card).utf8)))?.first
            })
            actions.append(.init(title: "Save as snippet", symbol: "text.quote") {
                library.save(IngestDraft(kind: .text, title: card.displayName, text: Self.summary(of: card)))
                done("Saved")
            })
            actions.append(.init(title: "Make QR", symbol: "qrcode") {
                var draft = CodeDraft(); draft.type = .contact; draft.contact = card; studioDraft = draft
            })
        }
        return actions
    }

    private func saveText(_ text: String, _ library: TypoLibrary) -> ScanResultRow.Action {
        .init(title: "Save", symbol: "tray.and.arrow.down") {
            if let draft = Ingest.draft(fromText: text) { library.save(draft) }
            done("Saved")
        }
    }

    private func done(_ message: String) { model.show(message) }

    private static func summary(of c: ContactCard) -> String {
        [c.displayName, c.jobTitle, c.organisation, c.phone, c.email, c.url, c.address].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: Business card

    private func captureCard() async {
        guard let scanner, !capturing else { return }
        capturing = true
        defer { capturing = false }
        do {
            let photo = try await scanner.capturePhoto()
            guard let cg = photo.cgImage else { return }
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            let observations = try await request.perform(on: cg, orientation: nil)
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let card = BusinessCardReader.contact(fromLines: lines)
            withAnimation(.smooth) { results.append(ScanResult(kind: .contact(card))) }
        } catch {
            model.show("Couldn't read the card. Try more light.")
        }
    }
}

private struct IdentifiedContact: Identifiable {
    let contact: CNContact
    var id: String { contact.identifier }
}

struct ScanResultRow: View {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let run: () -> Void
    }

    let result: ScanResult
    let actions: [Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HueTile(hue: Hues.named("Lagoon"), symbol: result.symbol, size: 32)
                Text(result.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button(action.title, systemImage: action.symbol, action: action.run)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// VisionKit's live scanner.
private struct LiveScanner: UIViewControllerRepresentable {
    let mode: ScanView.Mode
    @Binding var scanner: DataScannerViewController?
    let onTap: (RecognizedItem) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        DispatchQueue.main.async {
            scanner = controller
            try? controller.startScanning()
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTap: (RecognizedItem) -> Void
        init(onTap: @escaping (RecognizedItem) -> Void) { self.onTap = onTap }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            onTap(item)
        }
    }
}

/// System "New Contact" card, prefilled.
private struct NewContactView: UIViewControllerRepresentable {
    let contact: CNContact
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) { onDone() }
    }
}
#endif
