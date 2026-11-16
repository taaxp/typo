import AppIntents
import Foundation
import SwiftData

enum CopyIntentError: LocalizedError {
    case notFound
    case needsFields(String)
    case notWiFi
    case noPassword

    var errorDescription: String? {
        switch self {
        case .notFound: "That item isn't in Typo any more."
        case .needsFields(let title): "“\(title)” has fields to fill in. Open it in Typo to copy it."
        case .notWiFi: "That code isn't a Wi-Fi network."
        case .noPassword: "That network has no password saved."
        }
    }
}

/// "Copy my address from Typo". Copies the item and also returns its text, so a
/// Shortcut can follow with its own Copy to Clipboard step if iOS blocks a
/// background clipboard write (not yet verified on device).
struct CopyItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy from Typo"
    static let description = IntentDescription("Copies a saved snippet, link, photo or file to the clipboard.")

    @Parameter(title: "Item")
    var item: TypoItemEntity

    static var parameterSummary: some ParameterSummary { Summary("Copy \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let id = item.id
        guard let model = try TypoItemQuery.fetch(#Predicate { $0.uuid == id }).first else { throw CopyIntentError.notFound }
        if model.isTemplate && !Template.fields(in: model.text).isEmpty {
            throw CopyIntentError.needsFields(model.displayTitle)
        }
        Clipboard.copy([model])
        let value = model.kind.isInsertableAsText
            ? (model.isTemplate ? Template.render(model.text).text : model.text)
            : model.displayTitle
        return .result(value: value, dialog: "Copied \(model.displayTitle).")
    }
}

/// "Copy my Guest Wi-Fi password with Typo". The password comes from the Keychain,
/// is copied for 60 seconds, and is never spoken.
struct CopyWiFiPasswordIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Wi-Fi Password"
    static let description = IntentDescription("Copies the password of a Wi-Fi network saved in Typo. It clears from the clipboard after 60 seconds.")

    @Parameter(title: "Network")
    var code: CodeEntity

    static var parameterSummary: some ParameterSummary { Summary("Copy the password for \(\.$code)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = code.id
        let context = try SharedContainer.app().mainContext
        guard let item = try context.fetch(FetchDescriptor<CodeItem>(predicate: #Predicate { $0.uuid == id })).first else {
            throw CopyIntentError.notFound
        }
        guard item.payloadTypeRaw == QRPayloadType.wifi.rawValue, !item.isMemberCard else { throw CopyIntentError.notWiFi }
        guard let ref = item.secretRef, let password = Keychain.string(service: .wifi, account: ref), !password.isEmpty else {
            throw CopyIntentError.noPassword
        }
        Clipboard.copySensitive(password)
        return .result(dialog: "Copied the password for \(item.title). It clears in 60 seconds.")
    }
}
