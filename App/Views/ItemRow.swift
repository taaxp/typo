import SwiftUI

struct ItemRow: View {
    let item: StashItem

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(item: item, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Pinned")
                    }
                    Text(item.displayTitle).font(.body).lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !item.sortedTags.isEmpty { TagChips(tags: item.sortedTags) }
            }
            Spacer(minLength: 0)
            if !item.isReviewed {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("New")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        switch item.kind {
        case .text:
            return item.title.isEmpty ? nil : item.text
        case .link:
            return item.text
        case .photo, .gif, .document:
            let size = item.byteCount > 0 ? ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file) : nil
            let type = item.utType?.localizedDescription
            return [type, size].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct ItemThumbnail: View {
    let item: StashItem
    var size: CGFloat = 44

    var body: some View {
        let colour = CategoryColours.color(for: item.kind)
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(colour.opacity(0.15))
            if let data = item.thumbnail, let image = PlatformImage.from(data) {
                image.resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                Image(systemName: item.kind.symbol).foregroundStyle(colour)
            }
            if item.kind == .gif {
                Text("GIF").font(.system(size: 9, weight: .bold)).padding(.horizontal, 3)
                    .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(3)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(colour.opacity(0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct TagChips: View {
    let tags: [Tag]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(4)) { tag in
                Text(tag.name)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(hex: tag.colorHex).opacity(0.2), in: Capsule())
                    .foregroundStyle(Color(hex: tag.colorHex))
            }
            if tags.count > 4 { Text("+\(tags.count - 4)").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct ToastView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
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
