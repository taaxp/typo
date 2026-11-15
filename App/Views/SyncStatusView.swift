import SwiftUI
import SwiftData

struct SyncStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [StashItem]
    @State private var confirmRepair = false

    private var sync: SyncMonitor { model.sync }

    var body: some View {
        Form {
            Section("iCloud") {
                Label(sync.accountDescription,
                      systemImage: sync.accountStatus == .available ? "checkmark.icloud" : "exclamationmark.icloud")
                LabeledContent("Items in library", value: "\(items.count)")
            }

            Section("Activity") {
                LabeledContent("Last sent") { timestamp(sync.lastSent, active: sync.inProgress.contains("Send")) }
                LabeledContent("Last received") { timestamp(sync.lastReceived, active: sync.inProgress.contains("Receive")) }
                if let error = sync.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    confirmRepair = true
                } label: {
                    HStack {
                        Label("Repair Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                        Spacer()
                        if sync.isRepairing { ProgressView() }
                    }
                }
                .disabled(sync.isRepairing)
            } footer: {
                Text("Re-checks your iCloud account and queues every item to be sent again. Nothing is deleted. Sync runs on Apple's schedule, so changes can take a minute to arrive on your other devices.")
            }

            if !sync.log.isEmpty {
                Section("This session") {
                    ForEach(sync.log) { entry in
                        HStack {
                            Image(systemName: entry.succeeded ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(entry.succeeded ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(entry.kind)
                                if let error = entry.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text((entry.ended ?? entry.started).formatted(date: .omitted, time: .standard))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("Your library is stored in your own private iCloud database and on your devices. Stash has no account, no server, no analytics and no tracking.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync Status")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog("Repair sync?", isPresented: $confirmRepair) {
            Button("Repair") { Task { await sync.repair(context: context) } }
        } message: {
            Text("All items will be uploaded to iCloud again. This can use mobile data if you have large files.")
        }
        .refreshable { await sync.refreshAccountStatus() }
    }

    @ViewBuilder
    private func timestamp(_ date: Date?, active: Bool) -> some View {
        if active {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("In progress") }
        } else if let date {
            Text(date, format: .relative(presentation: .named)).help(date.formatted())
        } else {
            Text("Not yet").foregroundStyle(.secondary)
        }
    }
}
