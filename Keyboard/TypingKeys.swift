import SwiftUI
import UIKit

/// A compact QWERTY layout with shift, caps lock, numbers/symbols and key repeat
/// on delete. Kept simple on purpose: no autocorrect or predictive text, which iOS
/// does not provide to third-party keyboards out of the box.
struct TypingKeys: View {
    let actions: KeyboardActions

    @State private var layer: Layer = .letters
    @State private var shift: Shift = .once
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    private let letters = [["q","w","e","r","t","y","u","i","o","p"],
                           ["a","s","d","f","g","h","j","k","l"],
                           ["z","x","c","v","b","n","m"]]
    private let numbers = [["1","2","3","4","5","6","7","8","9","0"],
                           ["-","/",":",";","(",")","$","&","@","\""],
                           [".",",","?","!","'"]]
    private let symbols = [["[","]","{","}","#","%","^","*","+","="],
                           ["_","\\","|","~","<",">","€","£","¥","•"],
                           [".",",","?","!","'"]]

    private var rows: [[String]] {
        switch layer {
        case .letters: letters
        case .numbers: numbers
        case .symbols: symbols
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            row(rows[0])
            row(rows[1]).padding(.horizontal, layer == .letters ? 16 : 0)
            HStack(spacing: 6) {
                if layer == .letters {
                    key(systemImage: shift == .off ? "shift" : (shift == .locked ? "capslock.fill" : "shift.fill"), wide: true) {
                        shift = shift == .off ? .once : .off
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { shift = .locked })
                    .accessibilityLabel(shift == .locked ? "Caps lock on" : "Shift")
                } else {
                    key(label: layer == .numbers ? "#+=" : "123", wide: true) {
                        layer = layer == .numbers ? .symbols : .numbers
                    }
                }
                row(rows[2])
                DeleteKey(actions: actions)
            }
            HStack(spacing: 6) {
                key(label: layer == .letters ? "123" : "ABC", wide: true) {
                    layer = layer == .letters ? .numbers : .letters
                }
                key(label: "space", flexible: true) {
                    actions.insert(" ")
                    if layer != .letters { layer = .letters }
                }
                key(label: returnLabel, wide: true, prominent: true) { actions.insert("\n") }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var returnLabel: String {
        switch actions.returnKeyType {
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .send: "send"
        case .done: "done"
        case .next: "next"
        case .join: "join"
        default: "return"
        }
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { char in
                let output = layer == .letters && shift != .off ? char.uppercased() : char
                key(label: output, flexible: true) {
                    actions.insert(output)
                    if shift == .once { shift = .off }
                }
            }
        }
    }

    private func key(label: String? = nil, systemImage: String? = nil, wide: Bool = false, flexible: Bool = false,
                     prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(label ?? "") }
            }
            .font(.system(size: label?.count == 1 ? 22 : 15))
            .frame(maxWidth: flexible ? .infinity : nil, minHeight: 42)
            .frame(width: wide ? 50 : nil)
            .background(prominent ? Color.accentColor : Color(uiColor: .systemBackground),
                        in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(prominent ? .white : .primary)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// Delete with hold-to-repeat.
private struct DeleteKey: View {
    let actions: KeyboardActions
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 17))
            .frame(width: 50, height: 42)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35, perform: {}, onPressingChanged: { pressing in
                if pressing {
                    actions.deleteBackward()
                    UIDevice.current.playInputClick()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in
                        MainActor.assumeIsolated { actions.deleteBackward() }
                    }
                    timer?.fireDate = Date().addingTimeInterval(0.4)
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            })
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.deleteBackward() }
    }
}
