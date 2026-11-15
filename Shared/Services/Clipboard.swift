import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Puts items on the system clipboard as the real thing: text as text, links as
/// URLs (with a text fallback), photos/GIFs/files as typed data, so pasting into
/// Messages, Mail or Notes gives the image or file, not a path.
@MainActor
enum Clipboard {
    static func copy(_ items: [TypoItem]) {
        guard !items.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.setItems(items.map(representations(for:)))
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map(pasteboardItem(for:)))
        #endif
    }

    static func copy(text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private static let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")

    /// Type identifier → value, for one pasteboard item.
    static func representations(for item: TypoItem) -> [String: Any] {
        switch item.kind {
        case .text:
            return [UTType.utf8PlainText.identifier: item.text]
        case .link:
            var reps: [String: Any] = [UTType.utf8PlainText.identifier: item.text]
            if let url = item.url { reps[UTType.url.identifier] = url }
            return reps
        case .photo, .gif, .document:
            guard let data = item.payload else { return [UTType.utf8PlainText.identifier: item.displayTitle] }
            let type = item.utType ?? (item.kind == .gif ? .gif : .data)
            var reps: [String: Any] = [type.identifier: data]
            // Many apps only accept PNG/JPEG for photos; add a PNG for HEIC etc.
            #if canImport(UIKit)
            // Skipped inside extensions (keyboard), where decoding a large photo could exceed the memory limit.
            if item.kind == .photo, !isExtension, !type.conforms(to: .png), !type.conforms(to: .jpeg),
               let png = UIImage(data: data)?.pngData() {
                reps[UTType.png.identifier] = png
            }
            #endif
            return reps
        }
    }

    #if canImport(AppKit) && !canImport(UIKit)
    private static func pasteboardItem(for item: TypoItem) -> NSPasteboardItem {
        let pbItem = NSPasteboardItem()
        for (type, value) in representations(for: item) {
            let pbType = NSPasteboard.PasteboardType(type)
            if let data = value as? Data { pbItem.setData(data, forType: pbType) }
            else if let url = value as? URL { pbItem.setString(url.absoluteString, forType: .URL) }
            else if let string = value as? String { pbItem.setString(string, forType: pbType == .init(UTType.utf8PlainText.identifier) ? .string : pbType) }
        }
        // Files also go on as a file so Finder and Mail accept them.
        if item.kind != .text && item.kind != .link, let url = TempFiles.url(for: item) {
            pbItem.setString(url.absoluteString, forType: .fileURL)
        }
        return pbItem
    }
    #endif
}

/// Writes item payloads to temporary files for Quick Look, drag out and sharing.
enum TempFiles {
    static func url(for item: TypoItem) -> URL? {
        guard let data = item.payload else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypoPreview", isDirectory: true)
            .appendingPathComponent(item.uuid.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = item.filename ?? Ingest.defaultFilename(for: item.utType ?? .data)
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url, options: .atomic) } catch { return nil }
        }
        return url
    }
}
