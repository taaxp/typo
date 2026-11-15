import SwiftUI
import SwiftData

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [TypoItem]
    @State private var confirmRepair = false

    private var sync: SyncMonitor { model.sync }
    private var healthy: Bool { sync.accountStatus == .available && sync.lastError == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero
                VStack(spacing: 10) {
                    HueTile(hue: healthy ? Hues.named("Lagoon") : Hues.named("Amber"),
                            symbol: healthy ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill", size: 68)
                    Text(healthy ? "Up to date" : "Needs attention").font(.title2.weight(.bold))
                    Text(sync.accountDescription).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(24).frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                // Stats
                HStack(spacing: 12) {
                    stat("Sent", date: sync.lastSent, active: sync.inProgress.contains("Send"), hue: Hues.named("Ocean"), symbol: "arrow.up")
                    stat("Received", date: sync.lastReceived, active: sync.inProgress.contains("Receive"), hue: Hues.named("Sage"), symbol: "arrow.down")
                }
                HStack {
                    Text("Items in library")
                    Spacer()
                    Text("\(items.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if let error = sync.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Hues.named("Coral").inkColor)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Hues.named("Coral").softGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Button {
                    confirmRepair = true
                } label: {
                    HStack {
                        if sync.isRepairing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath.icloud") }
                        Text("Repair Sync").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(sync.isRepairing)

                Text("Re-checks your iCloud account and queues every item to be sent again. Nothing is deleted. Sync runs on Apple's schedule, so changes can take a minute to arrive on your other devices.")
                    .font(.footnote).foregroundStyle(.secondary)

                if !sync.log.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("This session").font(.headline).padding(.bottom, 8)
                        ForEach(sync.log) { entry in
                            HStack {
                                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(entry.succeeded ? Hues.named("Sage").gradient : Hues.named("Coral").gradient)
                                VStack(alignment: .leading) {
                                    Text(entry.kind)
                                    if let error = entry.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text((entry.ended ?? entry.started).formatted(date: .omitted, time: .standard))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Label("Your library lives in your own private iCloud and on your devices. No account, no server, no analytics, no tracking.",
                      systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background { AmbientBackground(hues: [Hues.named("Lagoon"), Hues.named("Mist"), Hues.named("Sage")]) }
        .navigationTitle("Sync")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
        }
        .confirmationDialog("Repair sync?", isPresented: $confirmRepair) {
            Button("Repair") { Task { await sync.repair(context: context) } }
        } message: {
            Text("All items will be uploaded to iCloud again. This can use mobile data if you have large files.")
        }
        .refreshable { await sync.refreshAccountStatus() }
    }

    private func stat(_ title: String, date: Date?, active: Bool, hue: Hue, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HueTile(hue: hue, symbol: symbol, size: 30)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Group {
                if active {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("In progress") }
                } else if let date {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Not yet").foregroundStyle(.secondary)
                }
            }
            .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
