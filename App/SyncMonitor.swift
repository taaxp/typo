import Foundation
import CoreData
import CloudKit
import SwiftData
import Observation

/// Watches iCloud sync for the Sync status screen.
///
/// SwiftData's CloudKit sync is built on `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for setup, import (received) and export (sent) events.
/// There is no API to ask "is item X synced?" or to force a sync on demand, so this
/// reports the last completed send/receive, the iCloud account state and the last
/// error, and offers a repair that re-queues every item for upload.
@MainActor
@Observable
final class SyncMonitor {
    struct Activity: Identifiable {
        let id = UUID()
        let kind: String
        let started: Date
        let ended: Date?
        let succeeded: Bool
        let error: String?
    }

    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var lastSent: Date?
    private(set) var lastReceived: Date?
    private(set) var lastError: String?
    private(set) var inProgress: Set<String> = []
    private(set) var log: [Activity] = []
    private(set) var isRepairing = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let d = AppGroup.defaults
        lastSent = d.object(forKey: AppGroup.Key.lastExport) as? Date
        lastReceived = d.object(forKey: AppGroup.Key.lastImport) as? Date
        lastError = d.string(forKey: AppGroup.Key.lastSyncError)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refreshAccountStatus() }
        })
        Task { await refreshAccountStatus() }
    }

    var accountDescription: String {
        switch accountStatus {
        case .available: "Signed in to iCloud"
        case .noAccount: "Not signed in to iCloud. Your library stays on this device until you sign in."
        case .restricted: "iCloud is restricted on this device (for example by Screen Time or a device profile)."
        case .temporarilyUnavailable: "iCloud is temporarily unavailable. Sync resumes automatically."
        case .couldNotDetermine: "Checking iCloud…"
        @unknown default: "Unknown iCloud state."
        }
    }

    func refreshAccountStatus() async {
        accountStatus = (try? await CKContainer(identifier: AppGroup.cloudKitContainer).accountStatus()) ?? .couldNotDetermine
    }

    /// Re-queues every item and tag for upload by touching them, which creates new
    /// local history that the sync engine exports. Safe: no data is deleted.
    func repair(context: ModelContext) async {
        isRepairing = true
        defer { isRepairing = false }
        await refreshAccountStatus()
        let now = Date()
        for item in (try? context.fetch(FetchDescriptor<TypoItem>())) ?? [] { item.modifiedAt = now }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] { tag.modifiedAt = now }
        do {
            try context.save()
            lastError = nil
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.lastSyncError)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: String
        switch event.type {
        case .setup: kind = "Setup"
        case .import: kind = "Receive"
        case .export: kind = "Send"
        @unknown default: kind = "Other"
        }
        guard let ended = event.endDate else {
            inProgress.insert(kind)
            return
        }
        inProgress.remove(kind)
        let d = AppGroup.defaults
        if event.succeeded {
            if event.type == .export { lastSent = ended; d.set(ended, forKey: AppGroup.Key.lastExport) }
            if event.type == .import { lastReceived = ended; d.set(ended, forKey: AppGroup.Key.lastImport) }
        } else if let error = event.error {
            lastError = Self.describe(error)
            d.set(lastError, forKey: AppGroup.Key.lastSyncError)
        }
        log.insert(Activity(kind: kind, started: event.startDate, ended: ended, succeeded: event.succeeded,
                            error: event.error.map(Self.describe)), at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .quotaExceeded: return "Your iCloud storage is full. Free up space to resume sync."
            case .networkUnavailable, .networkFailure: return "No network connection. Sync resumes when you're back online."
            case .notAuthenticated: return "Sign in to iCloud to sync."
            default: break
            }
        }
        return error.localizedDescription
    }
}
