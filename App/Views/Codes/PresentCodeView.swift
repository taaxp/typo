import SwiftUI

/// Full-screen code for someone else to scan. Turns screen brightness up on
/// iPhone and iPad and restores it when closed.
struct PresentCodeView: View {
    let draft: CodeDraft
    @Environment(\.dismiss) private var dismiss
    @State private var matrix: ModuleMatrix?
    @State private var savedBrightness: CGFloat?
    @State private var showPassword = false

    private var hue: Hue { Hues.named(draft.style.fillHue ?? (draft.isMember ? "Amber" : draft.type.hueName)) }

    var body: some View {
        ZStack {
            AmbientBackground(hues: [hue, Hues.named("Mist"), hue])
            VStack(spacing: 22) {
                Text(draft.suggestedTitle).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                if let matrix {
                    CodeCard(matrix: matrix, symbology: draft.symbology, style: draft.style,
                             humanReadable: draft.symbology.isLinear ? draft.message : nil)
                        .frame(maxWidth: draft.symbology.isLinear ? 520 : 360)
                        .padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                        .shadow(color: hue.base.opacity(0.25), radius: 30, y: 12)
                }
                if draft.type == .wifi && !draft.isMember {
                    wifiDetails
                } else if draft.isMember {
                    Text(draft.text).font(.system(.title, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                }
            }
            .padding(28)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(20)
                .accessibilityLabel("Close")
        }
        .task {
            matrix = try? CodeGenerator.matrix(for: draft.message, symbology: draft.symbology, correction: draft.style.correction)
        }
        .onAppear(perform: brighten)
        .onDisappear(perform: restore)
    }

    private var wifiDetails: some View {
        VStack(spacing: 8) {
            Text("Point your camera at the code to join").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(draft.wifi.ssid, systemImage: "wifi").font(.title3.weight(.semibold))
                if draft.wifi.security != .open {
                    Text("·").foregroundStyle(.secondary)
                    Text(showPassword ? draft.wifi.password : String(repeating: "•", count: min(draft.wifi.password.count, 12)))
                        .font(.system(.title3, design: .monospaced))
                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                        .buttonStyle(.glass)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassEffect()
        }
    }

    private func brighten() {
        #if os(iOS)
        guard let screen = Self.screen else { return }
        savedBrightness = screen.brightness
        screen.brightness = 1
        #endif
    }

    private func restore() {
        #if os(iOS)
        if let savedBrightness, let screen = Self.screen { screen.brightness = savedBrightness }
        #endif
    }

    #if os(iOS)
    private static var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }
    #endif
}
