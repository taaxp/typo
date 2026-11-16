#if os(iOS)
import Foundation
import SwiftData
import WatchConnectivity

/// Sends cards and pinned snippets to the Apple Watch.
///
/// - Codes marked "Show on Apple Watch" are rendered here (the watch has no Core
///   Image) and sent with `transferFile`, only when they've changed.
/// - The manifest goes with `updateApplicationContext`, so the watch always has
///   the latest state, even if it was asleep.
/// - Payment cards and Wi-Fi passwords as text are never sent. A guest Wi-Fi QR
///   image contains the password by design.
@MainActor
final class WatchSync: NSObject, WCSessionDelegate {
    static let snippetsKey = "watch.pinnedSnippets"
    private static let sentKey = "watch.sentFiles"

    private weak var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?

    static var sendsSnippets: Bool { AppGroup.defaults.object(forKey: snippetsKey) as? Bool ?? true }

    private static var outbox: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func start(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported(), observers.isEmpty else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        for name in [Notification.Name.typoLibraryChanged, .typoItemSaved] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
    }

    func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private func push() {
        let session = WCSession.default
        guard let container, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = container.mainContext
        let codeLibrary = CodeLibrary(context: context)

        // Cards
        let codes = (try? context.fetch(FetchDescriptor<CodeItem>(predicate: #Predicate { $0.showOnWatch },
                                                                   sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]))) ?? []
        var sent = Set(AppGroup.defaults.stringArray(forKey: Self.sentKey) ?? [])
        var cards: [WatchCard] = []
        for code in codes {
            let draft = codeLibrary.draft(for: code)
            let file = WatchPack.imageFile(for: code.uuid, updatedAt: code.modifiedAt)
            if !sent.contains(file) {
                var style = draft.style
                style.showFrame = false            // just the code, as large as possible on the watch
                guard let matrix = try? CodeGenerator.matrix(for: draft.message, symbology: draft.symbology, correction: style.correction),
                      let png = CodeExporter.png(matrix: matrix, symbology: draft.symbology, style: style,
                                                 humanReadable: draft.symbology.isLinear ? draft.message : nil, width: 400) else { continue }
                let url = Self.outbox.appendingPathComponent(file)
                guard (try? png.write(to: url, options: .atomic)) != nil else { continue }
                session.transferFile(url, metadata: ["file": file])
                sent.insert(file)
            }
            let kind: WatchCard.Kind = code.isMemberCard ? .member : (draft.type == .wifi ? .wifi : .qr)
            let caption = kind == .wifi ? "Scan to join \(draft.wifi.ssid)" : (draft.isMember ? draft.text : draft.style.caption)
            cards.append(WatchCard(id: code.uuid, title: code.title, kind: kind, hueName: code.hueName,
                                   caption: caption, imageFile: file, updatedAt: code.modifiedAt))
        }
        let current = Set(cards.map(\.imageFile))
        AppGroup.defaults.set(Array(sent.intersection(current)), forKey: Self.sentKey)
        cleanOutbox(keeping: current)

        // Pinned snippets
        var snippets: [WatchSnippet] = []
        if Self.sendsSnippets {
            let pinned = (try? context.fetch(FetchDescriptor<TypoItem>(predicate: #Predicate { $0.isPinned },
                                                                        sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]))) ?? []
            snippets = pinned.filter { $0.kind == .text || $0.kind == .link }.map { item in
                WatchSnippet(id: item.uuid, title: item.displayTitle,
                             // Capped so the application context stays well under its size limit.
                             text: String((item.isTemplate ? Template.render(item.text).text : item.text).prefix(1000)),
                             hueName: CategoryColours.hueName(for: item.kind))
            }
        }

        let pack = WatchPack(cards: cards, snippets: snippets)
        try? session.updateApplicationContext([WatchPack.contextKey: pack.encoded()])
    }

    private func cleanOutbox(keeping files: Set<String>) {
        let fm = FileManager.default
        let pending = Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in (try? fm.contentsOfDirectory(at: Self.outbox, includingPropertiesForKeys: nil)) ?? []
        where !files.contains(url.lastPathComponent) && !pending.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: WCSessionDelegate (support for switching between paired watches)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.schedule() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A different watch became active: reconnect and resend everything.
        session.activate()
        Task { @MainActor in
            AppGroup.defaults.removeObject(forKey: Self.sentKey)
            self.schedule()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.schedule() }
    }
}
#endif
