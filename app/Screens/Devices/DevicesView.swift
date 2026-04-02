import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var renameId: String?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Devices")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 8) {
                Circle()
                    .fill(engine.isEngineUnreachable ? Theme.blocked : Theme.allowed)
                    .frame(width: 8, height: 8)
                Text(engine.isEngineUnreachable ? "Can’t reach engine" : "Engine reachable")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("Refresh") {
                Task { await engine.refreshDevices() }
            }

            if engine.hasCompletedInitialDevicesFetch, engine.devices.isEmpty {
                if engine.lastOperationError != nil {
                    Text("Couldn’t load the device list.")
                        .foregroundStyle(Theme.blocked)
                } else {
                    emptyState
                }
            } else if !engine.devices.isEmpty {
                Table(engine.devices) {
                    TableColumn("Name") { d in
                        Text(d.name ?? "—")
                    }
                    TableColumn("IP") { d in
                        Text(d.ipAddress)
                    }
                    TableColumn("Protected") { d in
                        Text(d.isProtected ? "Yes" : "—")
                    }
                    TableColumn("Last seen") { d in
                        Text(formatLastSeen(d.lastSeen))
                    }
                    // Future: per-device query_count from API — show placeholder until available.
                    TableColumn("Queries") { _ in
                        Text("—")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    TableColumn("") { d in
                        Button("Rename") {
                            renameId = d.id
                            renameText = d.name ?? ""
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(minHeight: 200)
            } else if !engine.hasCompletedInitialDevicesFetch {
                ProgressView("Loading devices…")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 24)
            }

            if let e = engine.lastOperationError {
                Text(e).font(.caption).foregroundStyle(Theme.blocked)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task { await engine.refreshDevices() }
        .sheet(isPresented: Binding(
            get: { renameId != nil },
            set: { if !$0 { renameId = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename device").font(.headline)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { renameId = nil }
                    Button("Save") {
                        if let id = renameId {
                            Task {
                                await engine.renameDevice(id: id, name: renameText)
                                renameId = nil
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 320)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No devices detected yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("No devices seen yet — DNS clients will appear after queries reach NetSentrix. Finish router setup, then refresh.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func formatLastSeen(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        return ProductStatusAdapter.formattedRelativeTime(epochMs: ms)
    }
}
