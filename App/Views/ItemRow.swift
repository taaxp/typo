import SwiftUI

/// One saved item, drawn as a frosted card. Content sits on material; Liquid Glass
/// is kept for the controls layer above it (toolbars, dock, filter bar), as Apple's
/// guidance recommends.
struct ItemRow: View {
    let item: TypoItem
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 14) {
            ItemThumbnail(item: item, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if item.isPinned {
                        Image(systemName: "pin.fill").font(.caption2.weight(.bold))
                            .foregroundStyle(Hues.named("Amber").gradient)
                            .accessibilityLabel("Pinned")
                    }
                    Text(item.displayTitle).font(.body.weight(.semibold)).lineLimit(1)
                    if item.isTemplate {
                        Image(systemName: "curlybraces").font(.caption2.weight(.bold))
                            .foregroundStyle(Hues.named("Dusk").gradient)
                            .accessibilityLabel("Template")
                    }
                    if !item.shortcut.isEmpty {
                        Text(";" + item.shortcut).font(.caption2.monospaced().weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if !item.sortedTags.isEmpty { TagChips(tags: item.sortedTags) }
                if hasSuggestions { suggestions }
            }
            Spacer(minLength: 0)
            if !item.isReviewed {
                Circle().fill(CategoryColours.hue(for: item.kind).gradient)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("New")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var hasSuggestions: Bool {
        !item.suggestedTags.isEmpty || !item.suggestedCollectionName.isEmpty
    }

    /// Apple Intelligence suggestions, shown as dashed chips. Tap to accept.
    private var suggestions: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").font(.caption2).foregroundStyle(Hues.named("Dusk").gradient)
            ForEach(item.suggestedTags, id: \.self) { name in
                Text("+ \(name)").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary))
            }
            if !item.suggestedCollectionName.isEmpty {
                Label(item.suggestedCollectionName, systemImage: "square.stack.3d.up").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary))
            }
            Button("Add") { model.assistant.accept(item, context: context) }
                .font(.caption2.weight(.bold)).buttonStyle(.plain).foregroundStyle(Hues.named("Dusk").inkColor)
            Button { model.assistant.dismiss(item) } label: { Image(systemName: "xmark").font(.caption2) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss suggestions")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested")
    }

    private var subtitle: String? {
        switch item.kind {
        case .text:
            return item.title.isEmpty ? nil : item.text
        case .link:
            return URL(string: item.text)?.host() ?? item.text
        case .photo where !item.summary.isEmpty:
            return item.summary
        case .photo, .gif, .video, .document:
            let size = item.byteCount > 0 ? ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file) : nil
            let type = item.utType?.localizedDescription
            return [type, size].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// Photo/GIF thumbnail, or a gradient tile with the category symbol.
struct ItemThumbnail: View {
    let item: TypoItem
    var size: CGFloat = 48

    var body: some View {
        let hue = CategoryColours.hue(for: item.kind)
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Group {
            if let data = item.thumbnail, let image = PlatformImage.from(data) {
                image.resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            } else {
                HueTile(hue: hue, symbol: item.kind.symbol, size: size)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if item.kind == .gif {
                Text("GIF").font(.system(size: size * 0.19, weight: .heavy))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TagChips: View {
    let tags: [Tag]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tags.prefix(3)) { tag in HueChip(title: tag.name, hue: tag.hue, compact: true) }
            if tags.count > 3 { Text("+\(tags.count - 3)").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Floating confirmation, on Liquid Glass.
struct ToastView: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassEffect()
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Decodes image bytes on either platform.
enum PlatformImage {
    static func from(_ data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}
