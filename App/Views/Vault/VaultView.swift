import SwiftUI

/// Saved payment cards, behind Face ID / Touch ID / passcode.
struct VaultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: VaultCard?
    @State private var addingManually = false
    @State private var scanning = false
    @State private var revealed: UUID?
    @State private var confirmDelete: VaultCard?

    private var lock: VaultLock { model.vaultLock }
    private var vault: VaultStore { model.vault }

    var body: some View {
        Group {
            if lock.isUnlocked { unlocked } else { locked }
        }
        .background { AmbientBackground(hues: [Hues.named("Fog"), Hues.named("Ocean"), Hues.named("Dusk")]) }
        .navigationTitle("Vault")
        .toolbar {
            if lock.isUnlocked {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        #if os(iOS)
                        Button("Scan a Card", systemImage: "camera.viewfinder") { scanning = true }
                        #endif
                        Button("Enter Manually", systemImage: "keyboard") { addingManually = true }
                    } label: { Label("Add Card", systemImage: "plus") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Lock", systemImage: "lock.fill") { lockNow() }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active:
                lock.didBecomeActive()
                if !lock.isUnlocked { vault.forget() }
            default: break
            }
        }
        .onChange(of: lock.isUnlocked) { _, unlocked in
            if unlocked { vault.reload() } else { vault.forget(); revealed = nil }
        }
        .sheet(item: $editing) { card in NavigationStack { CardEditor(card: card) } }
        .sheet(isPresented: $addingManually) { NavigationStack { CardEditor(card: nil) } }
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) { CardScannerView() }
        #endif
        .confirmationDialog("Delete this card?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { card in
            Button("Delete \(card.nickname.isEmpty ? card.masked : card.nickname)", role: .destructive) { vault.delete(card) }
        } message: { _ in
            Text("It's removed from your iCloud Keychain on all your devices.")
        }
    }

    // MARK: Locked

    private var locked: some View {
        VStack(spacing: 18) {
            HueTile(hue: Hues.named("Fog"), symbol: "lock.fill", size: 84)
            Text("Your cards are locked").font(.title2.weight(.bold))
            Text("Unlock with \(lock.biometryName) to see and copy your saved cards.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { Task { await lock.unlock() } } label: {
                Label("Unlock", systemImage: "faceid").font(.headline).padding(.horizontal, 22).padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            if let error = lock.lastError {
                Text(error).font(.footnote).foregroundStyle(Hues.named("Coral").inkColor)
            }
            privacyNote
        }
        .padding(32)
        .frame(maxWidth: 460)
        .task { if !lock.isUnlocked { await lock.unlock() } }
    }

    // MARK: Unlocked

    private var unlocked: some View {
        ScrollView {
            VStack(spacing: 18) {
                if vault.cards.isEmpty {
                    ContentUnavailableView("No cards yet", systemImage: "creditcard",
                                           description: Text("Scan a card with the camera or enter it by hand."))
                        .padding(.top, 40)
                }
                ForEach(vault.cards) { card in
                    VStack(spacing: 10) {
                        PaymentCardView(card: card, revealed: revealed == card.id)
                            .onTapGesture { withAnimation(.smooth) { revealed = revealed == card.id ? nil : card.id } }
                            .accessibilityHint("Shows or hides the full number")
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                Button("Number", systemImage: "doc.on.doc") {
                                    Clipboard.copySensitive(card.number)
                                    model.show("Number copied for 60 seconds")
                                }
                                Button("Expiry", systemImage: "calendar") {
                                    Clipboard.copySensitive(card.expiry)
                                    model.show("Expiry copied")
                                }
                                Button("Name", systemImage: "person") {
                                    Clipboard.copySensitive(card.holder)
                                    model.show("Name copied")
                                }
                                Menu {
                                    Button("Edit…", systemImage: "pencil") { editing = card }
                                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = card }
                                } label: { Image(systemName: "ellipsis") }
                                    .accessibilityLabel("More")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                }
                privacyNote
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var privacyNote: some View {
        Label("Cards are kept in your iCloud Keychain, never in Typo's library. Typo never saves security codes (CVV). Copied numbers clear from the clipboard after 60 seconds and stay on this device.",
              systemImage: "lock.shield")
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func lockNow() {
        lock.lock()
        vault.forget()
    }
}

/// A gradient glass payment card.
struct PaymentCardView: View {
    let card: VaultCard
    var revealed = false

    var body: some View {
        let hue = Hues.named(card.hueName)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(card.nickname.isEmpty ? card.network.title : card.nickname).font(.headline)
                Spacer()
                Text(card.network.title).font(.subheadline.weight(.bold)).opacity(0.85)
            }
            Spacer()
            Text(revealed ? card.formatted : card.masked)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .contentTransition(.numericText())
                .privacySensitive()
            Spacer().frame(height: 14)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARDHOLDER").font(.caption2.weight(.semibold)).opacity(0.7)
                    Text(card.holder.isEmpty ? "—" : card.holder).font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("EXPIRES").font(.caption2.weight(.semibold)).opacity(0.7)
                    Text(card.expiry).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(height: 210)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(hue.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.35), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.nickname.isEmpty ? card.network.title : card.nickname), ending \(String(card.number.suffix(4))), expires \(card.expiry)")
    }
}

/// Add or edit a card. There is no security code field on purpose.
struct CardEditor: View {
    let original: VaultCard?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var holder = ""
    @State private var number = ""
    @State private var expiry = ""
    @State private var network: CardNumber.Network = .unknown
    @State private var hueName = "Ocean"

    init(card: VaultCard?, prefill: (number: String?, expiry: String?, name: String?)? = nil) {
        original = card
        _nickname = State(initialValue: card?.nickname ?? "")
        _holder = State(initialValue: card?.holder ?? prefill?.name?.capitalized ?? "")
        let n = card?.number ?? prefill?.number ?? ""
        _number = State(initialValue: CardNumber.formatted(n))
        _expiry = State(initialValue: card?.expiry ?? prefill?.expiry ?? "")
        _network = State(initialValue: card?.network ?? CardNumber.network(n))
        _hueName = State(initialValue: card?.hueName ?? "Ocean")
    }

    private var numberValid: Bool { CardNumber.isValid(number) }
    private var expiryValid: Bool { CardNumber.normalisedExpiry(expiry) != nil }

    var body: some View {
        Form {
            Section {
                PaymentCardView(card: preview, revealed: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section("Card") {
                TextField("Nickname (e.g. Everyday)", text: $nickname)
                TextField("Name on card", text: $holder)
                    #if os(iOS)
                    .textContentType(.name)
                    #endif
                TextField("Card number", text: $number)
                    .font(.body.monospacedDigit())
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: number) { _, new in
                        let formatted = CardNumber.formatted(new)
                        if formatted != new { number = formatted }
                        if original == nil { network = CardNumber.network(new) }
                    }
                if !number.isEmpty && !numberValid {
                    Label("That number doesn't look right. Check each digit.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Hues.named("Coral").inkColor)
                }
                TextField("Expiry (MM/YY)", text: $expiry)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                Picker("Network", selection: $network) {
                    ForEach(CardNumber.Network.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Colour") { HuePicker(selection: $hueName) }
            Section {
                Label("Typo never asks for or saves the security code (CVV).", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(original == nil ? "Add Card" : "Edit Card")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }.disabled(!numberValid || !expiryValid)
            }
        }
    }

    private var preview: VaultCard {
        VaultCard(id: original?.id ?? UUID(), nickname: nickname, holder: holder, number: CardNumber.digits(number),
                  expiry: CardNumber.normalisedExpiry(expiry) ?? expiry, network: network, hueName: hueName,
                  addedAt: original?.addedAt ?? .now)
    }

    private func save() {
        do {
            try model.vault.save(preview)
            model.show("Card saved")
            dismiss()
        } catch {
            model.show("Couldn't save: \(error.localizedDescription)")
        }
    }
}
