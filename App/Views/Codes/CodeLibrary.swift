import Foundation
import SwiftData
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Saves codes, keeps Wi-Fi passwords in the Keychain and refreshes the widget.
@MainActor
struct CodeLibrary {
    let context: ModelContext

    func secret(for item: CodeItem) -> String? {
        item.secretRef.flatMap { Keychain.string(service: .wifi, account: $0) }
    }

    func draft(for item: CodeItem) -> CodeDraft {
        CodeDraft(item: item, secret: secret(for: item))
    }

    @discardableResult
    func save(_ draft: CodeDraft, into existing: CodeItem? = nil) throws -> CodeItem {
        let item = existing ?? CodeItem(title: "", kind: draft.isMember ? "member" : "qr",
                                        payloadType: draft.type.rawValue, payload: "", symbology: draft.symbology.rawValue)
        item.title = draft.suggestedTitle
        item.kindRaw = draft.isMember ? "member" : "qr"
        item.payloadTypeRaw = draft.type.rawValue
        item.symbologyRaw = draft.symbology.rawValue
        item.payload = draft.storedPayload()
        item.styleData = draft.style.encoded()
        item.hueName = draft.style.fillHue ?? (draft.isMember ? "Amber" : draft.type.hueName)
        item.modifiedAt = .now

        if let secret = draft.secret {
            let account = item.secretRef ?? item.uuid.uuidString
            try Keychain.setString(secret, service: .wifi, account: account)
            item.secretRef = account
        } else if let ref = item.secretRef {
            Keychain.delete(service: .wifi, account: ref)
            item.secretRef = nil
        }
        if existing == nil { context.insert(item) }
        try context.save()
        TypoShortcuts.updateAppShortcutParameters()   // "Show my <code>" phrases
        if item.showOnWidget { refreshWidget(with: item) }
        return item
    }

    func delete(_ item: CodeItem) {
        if let ref = item.secretRef { Keychain.delete(service: .wifi, account: ref) }
        if item.showOnWidget { WidgetSnapshot.clear(); reloadWidgets() }
        context.delete(item)
        try? context.save()
        TypoShortcuts.updateAppShortcutParameters()
    }

    /// Only one code is on the widget at a time.
    func setOnWidget(_ item: CodeItem, _ on: Bool) {
        let all = (try? context.fetch(FetchDescriptor<CodeItem>())) ?? []
        all.forEach { $0.showOnWidget = false }
        item.showOnWidget = on
        try? context.save()
        if on { refreshWidget(with: item) } else { WidgetSnapshot.clear(); reloadWidgets() }
    }

    func refreshWidget(with item: CodeItem) {
        let draft = self.draft(for: item)
        guard let matrix = try? CodeGenerator.matrix(for: draft.message, symbology: draft.symbology, correction: draft.style.correction),
              let png = CodeExporter.png(matrix: matrix, symbology: draft.symbology, style: draft.style,
                                         humanReadable: draft.symbology.isLinear ? draft.message : nil, width: 600) else { return }
        let caption = draft.type == .wifi && !draft.isMember ? "Scan to join \(draft.wifi.ssid)" : draft.style.caption
        try? WidgetSnapshot.save(WidgetSnapshot(title: item.title, caption: caption, hueName: item.hueName, updatedAt: .now), png: png)
        reloadWidgets()
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
