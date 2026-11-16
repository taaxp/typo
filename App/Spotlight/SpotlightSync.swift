import Foundation
import SwiftData

/// Keeps the Spotlight index in step with the library, debounced so a burst of
/// saves becomes one update.
@MainActor
final class SpotlightSync {
    private var observers: [NSObjectProtocol] = []
    private var pendingIDs: [PersistentIdentifier] = []
    private var fullReindexPending = false
    private var task: Task<Void, Never>?
    private weak var container: ModelContainer?

    static let didInitialIndexKey = "spotlight.didInitialIndex"

    func start(container: ModelContainer) {
        self.container = container
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .typoItemSaved, object: nil, queue: .main) { [weak self] note in
            guard let id = note.object as? PersistentIdentifier else { return }
            MainActor.assumeIsolated { self?.pendingIDs.append(id); self?.schedule() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .typoLibraryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fullReindexPending = true; self?.schedule() }
        })
        if !AppGroup.defaults.bool(forKey: Self.didInitialIndexKey) {
            fullReindexPending = true
            schedule()
        }
    }

    /// Settings › Spotlight › Rebuild, or the toggle.
    func rebuild() {
        fullReindexPending = true
        schedule(delay: .zero)
    }

    private func schedule(delay: Duration = .seconds(2)) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        if fullReindexPending {
            fullReindexPending = false
            pendingIDs.removeAll()
            try? await SpotlightIndex.reindexAll()
            AppGroup.defaults.set(true, forKey: Self.didInitialIndexKey)
            return
        }
        guard let container else { return }
        let items = pendingIDs.compactMap { container.mainContext.model(for: $0) as? TypoItem }
        pendingIDs.removeAll()
        await SpotlightIndex.update(items)
        TypoShortcuts.updateAppShortcutParameters()
    }
}
