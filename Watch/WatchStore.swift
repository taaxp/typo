import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit
import Observation

/// Receives cards and snippets from the iPhone and keeps a local copy in the
/// App Group (shared with the complications).
@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    private(set) var pack = WatchPack.loadLocal()
    @ObservationIgnored private var imageCache: [String: Image] = [:]

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func image(for card: WatchCard) -> Image? {
        if let cached = imageCache[card.imageFile] { return cached }
        let url = WatchPack.folder.appendingPathComponent(card.imageFile)
        guard let data = try? Data(contentsOf: url), let ui = UIImage(data: data) else { return nil }
        let image = Image(uiImage: ui)
        imageCache[card.imageFile] = image
        return image
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context[WatchPack.contextKey] as? Data, let newPack = WatchPack.decode(data) else { return }
        pack = newPack
        pack.saveLocal()
        removeStaleImages()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func removeStaleImages() {
        let keep = Set(pack.cards.map(\.imageFile) + ["pack.json"])
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: WatchPack.folder, includingPropertiesForKeys: nil)) ?? []
        where !keep.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
        imageCache = imageCache.filter { keep.contains($0.key) }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    /// The transferred file is deleted when this method returns, so move it now.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let name = file.metadata?["file"] as? String else { return }
        let destination = WatchPack.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: file.fileURL, to: destination)
        Task { @MainActor in
            self.imageCache[name] = nil
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
