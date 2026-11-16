import Foundation

/// Syncs category hues across the user's devices with iCloud key-value storage.
/// The App Group defaults stay the source the keyboard and extensions read.
@MainActor
final class HueSync {
    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private static let prefix = "categoryHue."

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        store.synchronize()
        pull()
    }

    /// Mirrors iCloud into the App Group defaults (iCloud wins once anything is
    /// stored there, so "Reset to Defaults" on one device resets them all).
    func pull() {
        guard ItemKind.allCases.contains(where: { store.object(forKey: Self.prefix + $0.rawValue) != nil })
                || store.bool(forKey: Self.prefix + "initialised") else { return }
        for kind in ItemKind.allCases {
            let key = Self.prefix + kind.rawValue
            if let name = store.string(forKey: key) {
                AppGroup.defaults.set(name, forKey: key)
            } else {
                AppGroup.defaults.removeObject(forKey: key)
            }
        }
    }

    /// Call after changing hues in Settings.
    func push() {
        for kind in ItemKind.allCases {
            let key = Self.prefix + kind.rawValue
            if let name = AppGroup.defaults.string(forKey: key) { store.set(name, forKey: key) } else { store.removeObject(forKey: key) }
        }
        store.set(true, forKey: Self.prefix + "initialised")
        store.synchronize()
    }
}
