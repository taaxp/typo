#if os(iOS)
import SwiftUI
import VisionKit

/// Reads a card's number, expiry and name with the camera. Security codes are
/// ignored. Nothing is saved until the user confirms in `CardEditor`.
struct CardScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var found: (number: String?, expiry: String?, name: String?)?
    @State private var confirming = false

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                CardTextScanner { lines in
                    let result = CardNumber.extract(fromLines: lines)
                    if result.number != nil && !confirming {
                        found = result
                        confirming = true
                    }
                }
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("Scanning isn't supported on this device", systemImage: "camera.metering.unknown")
            }
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                .aspectRatio(1.586, contentMode: .fit)   // ISO/IEC 7810 ID-1 card shape
                .padding(28)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Close")
                Spacer()
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            Label("Hold the front of the card inside the frame. Typo ignores the security code.", systemImage: "creditcard.viewfinder")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect()
                .padding(24)
        }
        .sheet(isPresented: $confirming, onDismiss: { dismiss() }) {
            NavigationStack { CardEditor(card: nil, prefill: found) }
        }
    }
}

private struct CardTextScanner: UIViewControllerRepresentable {
    let onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false)
        controller.delegate = context.coordinator
        DispatchQueue.main.async { try? controller.startScanning() }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onLines: ([String]) -> Void
        init(onLines: @escaping ([String]) -> Void) { self.onLines = onLines }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            let lines: [String] = items.compactMap {
                if case .text(let text) = $0 { return text.transcript }
                return nil
            }
            onLines(lines)
        }
    }
}
#endif
