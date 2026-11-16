import Foundation
import UniformTypeIdentifiers
import ImageIO

/// A save that hasn't been turned into a `TypoItem` yet. Produced by every input path
/// (share sheet, clipboard, drag and drop, Shortcuts, image URL) so classification
/// lives in one place.
struct IngestDraft: Sendable {
    var kind: ItemKind
    var title: String = ""
    var text: String = ""
    var payload: Data?
    var typeIdentifier: String?
    var filename: String?
}

enum IngestError: LocalizedError {
    case nothingUsable
    case notAnImage
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .nothingUsable: "There was nothing Typo could save."
        case .notAnImage: "That link didn't return an image."
        case .tooLarge(let mb): "That file is over \(mb) MB."
        }
    }
}

enum Ingest {
    /// iCloud handles large assets, but keep single items sensible. Extensions get a
    /// lower cap because the whole file is held in memory and extensions are
    /// terminated if they exceed their memory limit.
    static let maxBytes = Bundle.main.bundlePath.hasSuffix(".appex") ? 50 * 1024 * 1024 : 250 * 1024 * 1024

    // MARK: Classification

    /// Classifies a piece of text. A lone http(s) URL becomes a link.
    static func draft(fromText raw: String) -> IngestDraft? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = singleWebURL(in: text) {
            return IngestDraft(kind: .link, text: url.absoluteString)
        }
        return IngestDraft(kind: .text, text: raw)
    }

    static func draft(fromURL url: URL) -> IngestDraft {
        IngestDraft(kind: .link, text: url.absoluteString)
    }

    /// Classifies raw bytes by their type.
    static func draft(fromData data: Data, type: UTType, filename: String?) throws -> IngestDraft {
        guard data.count <= maxBytes else { throw IngestError.tooLarge(maxBytes / 1_048_576) }
        let kind: ItemKind
        if type.conforms(to: .gif) || isGIF(data) {
            kind = .gif
        } else if type.conforms(to: .image) {
            kind = .photo
        } else if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            kind = .video
        } else {
            kind = .document
        }
        let resolvedType = kind == .gif ? UTType.gif : type
        return IngestDraft(kind: kind, payload: data, typeIdentifier: resolvedType.identifier,
                           filename: filename ?? defaultFilename(for: resolvedType))
    }

    /// Classifies whatever an `NSItemProvider` offers (share sheet, drag and drop, paste).
    /// Prefers the richest representation: GIF > image > file > URL > text.
    static func drafts(from providers: [NSItemProvider]) async -> [IngestDraft] {
        var out: [IngestDraft] = []
        for provider in providers {
            if let draft = try? await draft(from: provider) { out.append(draft) }
        }
        return out
    }

    static func draft(from provider: NSItemProvider) async throws -> IngestDraft {
        let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        let name = provider.suggestedName

        if types.contains(where: { $0.conforms(to: .gif) }) {
            let data = try await loadData(provider, .gif)
            return try draft(fromData: data, type: .gif, filename: name.map { ensureExtension($0, .gif) })
        }
        if let imageType = types.first(where: { $0.conforms(to: .image) }) {
            let data = try await loadData(provider, imageType)
            return try draft(fromData: data, type: imageType, filename: name.map { ensureExtension($0, imageType) })
        }
        // A web URL (not a file URL) is a link.
        if types.contains(where: { $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }),
           let url = try? await loadURL(provider), !url.isFileURL {
            return draft(fromURL: url)
        }
        // Any other file-like content.
        if let fileType = types.first(where: { $0.conforms(to: .data) && !$0.conforms(to: .text) })
            ?? types.first(where: { $0.conforms(to: .content) && !$0.conforms(to: .plainText) }) {
            let (data, filename) = try await loadFile(provider, fileType)
            return try draft(fromData: data, type: fileType, filename: filename ?? name)
        }
        if types.contains(where: { $0.conforms(to: .text) }) {
            let data = try await loadData(provider, .plainText)
            if let string = String(data: data, encoding: .utf8), let draft = draft(fromText: string) {
                return draft
            }
        }
        throw IngestError.nothingUsable
    }

    // MARK: Image from a direct URL

    /// Downloads a photo or GIF from a direct image URL (e.g. https://…/cat.gif).
    static func draft(fromImageURL url: URL) async throws -> IngestDraft {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let mime = (response as? HTTPURLResponse)?.mimeType ?? response.mimeType
        let type = mime.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: url.pathExtension) ?? .data
        guard type.conforms(to: .image) || isGIF(data) else { throw IngestError.notAnImage }
        let name = url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
        return try draft(fromData: data, type: type, filename: name)
    }

    // MARK: Thumbnails

    /// A JPEG no larger than `maxPixel` on its longest side. Uses ImageIO so it runs in
    /// extensions and on both platforms without UIKit/AppKit.
    static func thumbnail(for data: Data, maxPixel: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    // MARK: Helpers

    static func singleWebURL(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    static func isGIF(_ data: Data) -> Bool {
        data.prefix(6) == Data("GIF87a".utf8) || data.prefix(6) == Data("GIF89a".utf8)
    }

    static func defaultFilename(for type: UTType) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Typo \(formatter.string(from: Date())).\(type.preferredFilenameExtension ?? "dat")"
    }

    static func ensureExtension(_ name: String, _ type: UTType) -> String {
        guard let ext = type.preferredFilenameExtension else { return name }
        return (name as NSString).pathExtension.isEmpty ? "\(name).\(ext)" : name
    }

    private static func loadData(_ provider: NSItemProvider, _ type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { cont.resume(returning: data) } else { cont.resume(throwing: error ?? IngestError.nothingUsable) }
            }
        }
    }

    private static func loadFile(_ provider: NSItemProvider, _ type: UTType) async throws -> (Data, String?) {
        try await withCheckedThrowingContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                // The file is deleted when this closure returns, so read it now.
                guard let url else { cont.resume(throwing: error ?? IngestError.nothingUsable); return }
                do {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size > maxBytes { throw IngestError.tooLarge(maxBytes / 1_048_576) }
                    cont.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? IngestError.nothingUsable) }
            }
        }
    }
}
