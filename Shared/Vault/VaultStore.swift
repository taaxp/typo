import Foundation
import Observation

/// A saved payment card. There is deliberately no field for the security code
/// (CVV/CVC): it can't be stored, even by accident.
struct VaultCard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var nickname: String
    var holder: String
    var number: String          // digits only
    var expiry: String          // MM/YY
    var network: CardNumber.Network
    var hueName: String = "Ocean"
    var addedAt = Date()

    var masked: String { CardNumber.masked(number) }
    var formatted: String { CardNumber.formatted(number) }
}

/// Cards live only in the (iCloud) Keychain, never in SwiftData or CloudKit.
/// Compiled into the app targets only: the keyboard, share extension and widgets
/// never include this file.
@MainActor
@Observable
final class VaultStore {
    private(set) var cards: [VaultCard] = []

    func reload() {
        let decoder = JSONDecoder()
        cards = Keychain.all(service: .vault)
            .compactMap { try? decoder.decode(VaultCard.self, from: $0.data) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    func save(_ card: VaultCard) throws {
        try Keychain.set(try JSONEncoder().encode(card), service: .vault, account: card.id.uuidString)
        reload()
    }

    func delete(_ card: VaultCard) {
        Keychain.delete(service: .vault, account: card.id.uuidString)
        reload()
    }

    /// Clears in-memory copies when the vault locks.
    func forget() { cards = [] }
}
