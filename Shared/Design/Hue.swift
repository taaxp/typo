import SwiftUI

extension Color {
    /// `#RRGGBB` → Color. Falls back to grey for bad input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// A named, soothing two-stop gradient. Used for categories and tags instead of flat colours.
///
/// Every hue has a one-word name people can remember ("Sage", "Lagoon"), a light
/// `top` and deeper `bottom` stop, and an `ink` colour dark enough for readable text
/// on top of the soft gradient.
struct Hue: Identifiable, Hashable, Sendable {
    let name: String
    let top: String
    let bottom: String
    let ink: String

    var id: String { name }

    var topColor: Color { Color(hex: top) }
    var bottomColor: Color { Color(hex: bottom) }
    var inkColor: Color { Color(hex: ink) }
    /// Representative solid colour (icons, dots, accessibility fallbacks).
    var base: Color { bottomColor }

    /// The full gradient, top-leading to bottom-trailing.
    var gradient: LinearGradient {
        LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A paler version for chips and selected backgrounds.
    var softGradient: LinearGradient {
        LinearGradient(colors: [topColor.opacity(0.55), bottomColor.opacity(0.35)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Hues {
    static let all: [Hue] = [
        Hue(name: "Sage",   top: "#B7D3B0", bottom: "#6FA287", ink: "#2E5B47"),
        Hue(name: "Lagoon", top: "#8EE3E0", bottom: "#2F9FB4", ink: "#135E6C"),
        Hue(name: "Ocean",  top: "#8FB8FF", bottom: "#4B63E6", ink: "#213A9E"),
        Hue(name: "Dusk",   top: "#C7B6F2", bottom: "#7C6AD6", ink: "#3F318F"),
        Hue(name: "Plum",   top: "#E0A9DC", bottom: "#9C5BAF", ink: "#5B2A6B"),
        Hue(name: "Blush",  top: "#FFC2CF", bottom: "#E7779A", ink: "#8A2A4A"),
        Hue(name: "Coral",  top: "#FFC1A8", bottom: "#F2766A", ink: "#8E2F25"),
        Hue(name: "Amber",  top: "#FFD99A", bottom: "#F0A044", ink: "#7A4A0E"),
        Hue(name: "Honey",  top: "#FBE7A4", bottom: "#E3B94A", ink: "#6B5212"),
        Hue(name: "Sand",   top: "#EADBC8", bottom: "#B99A7A", ink: "#5E4630"),
        Hue(name: "Mist",   top: "#D5E9F6", bottom: "#8DBBDD", ink: "#24506F"),
        Hue(name: "Fog",    top: "#D7DCE3", bottom: "#8D97A6", ink: "#3D4654"),
    ]

    static let fallback = all[0]

    static func named(_ name: String) -> Hue {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? fallback
    }

    /// Order new tags are given hues in, chosen so neighbours look distinct.
    static let tagRotation = ["Sage", "Dusk", "Coral", "Mist", "Plum", "Honey", "Lagoon", "Blush", "Ocean", "Amber", "Sand", "Fog"]
}

// MARK: - Reusable pieces

/// A capsule chip with a soft gradient and readable ink text. Used for tags.
struct HueChip: View {
    let title: String
    let hue: Hue
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            // Dark ink on the pale gradient in light mode; white on the full gradient in dark mode.
            .foregroundStyle(scheme == .dark ? Color.white : hue.inkColor)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 2 : 4)
            .background(scheme == .dark ? AnyShapeStyle(hue.gradient.opacity(0.75)) : AnyShapeStyle(hue.softGradient), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
    }
}

/// A round gradient dot, e.g. in the sidebar.
struct HueDot: View {
    let hue: Hue
    var size: CGFloat = 12

    var body: some View {
        Circle().fill(hue.gradient)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A rounded gradient tile with a white symbol, styled like an app icon.
struct HueTile: View {
    let hue: Hue
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(hue.gradient)
            .overlay {
                // Soft top highlight gives the tile depth.
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            }
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: hue.base.opacity(0.35), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Grid of named swatches for picking a hue.
struct HuePicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
            ForEach(Hues.all) { hue in
                Button { selection = hue.name } label: {
                    VStack(spacing: 6) {
                        Circle().fill(hue.gradient)
                            .frame(width: 40, height: 40)
                            .overlay {
                                if selection == hue.name {
                                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(selection == hue.name ? hue.inkColor : .clear, lineWidth: 2).padding(-4))
                        Text(hue.name).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hue.name)
                .accessibilityAddTraits(selection == hue.name ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Soft, blurred colour field behind content so Liquid Glass and materials have
/// something to refract. Tinted by the current category's hue.
struct AmbientBackground: View {
    var hues: [Hue]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                scheme == .dark ? Color(white: 0.05) : Color(white: 0.97)
                ForEach(Array(hues.prefix(3).enumerated()), id: \.offset) { index, hue in
                    Circle()
                        .fill(hue.gradient)
                        .frame(width: w * 0.9, height: w * 0.9)
                        .offset(x: [-0.35, 0.4, -0.1][index] * w, y: [-0.3, 0.05, 0.42][index] * h)
                        .opacity(scheme == .dark ? 0.32 : 0.45)
                }
            }
            .blur(radius: 80)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
