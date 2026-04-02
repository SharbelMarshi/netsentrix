import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var renameId: String?
    @State private var renameText = ""
    @State private var detailDevice: DeviceDTO?
    @State private var detailRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Devices")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(
                "Clients observed from DNS traffic through NetSentrix (IP-based). Counts come from logged queries — not packet discovery or DHCP."
            )
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

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
                        Text(d.name?.isEmpty == false ? d.name! : "—")
                    }
                    .width(min: 80, ideal: 120)
                    TableColumn("IP") { d in
                        Text(d.ipAddress).font(.body.monospaced())
                    }
                    .width(min: 100, ideal: 130)
                    TableColumn("DNS activity") { d in
                        Text(dnsActivityLabel(d))
                            .foregroundStyle(activityColor(d))
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("Last seen") { d in
                        Text(formatLastSeen(d.lastSeen))
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("Queries (total)") { d in
                        Text(formatCount(d.queryCountTotal))
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Last 24h") { d in
                        Text(formatCount(d.queryCount24h))
                    }
                    .width(min: 60, ideal: 72)
                    TableColumn("") { d in
                        HStack(spacing: 6) {
                            Button("Details") {
                                detailDevice = d
                                Task { await refreshDetailFromEngine() }
                            }
                            .buttonStyle(.borderless)
                            Button("Rename") {
                                renameId = d.id
                                renameText = d.name ?? ""
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .width(min: 140, ideal: 160)
                }
                .frame(minHeight: 220)
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
        .sheet(item: $detailDevice) { d in
            deviceDetailSheet(device: d)
        }
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
                                await engine.refreshDevices()
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

    private func refreshDetailFromEngine() async {
        guard let id = detailDevice?.id else { return }
        detailRefreshing = true
        defer { detailRefreshing = false }
        if let fresh = await engine.fetchDevice(id: id) {
            detailDevice = fresh
        }
    }

    @ViewBuilder
    private func deviceDetailSheet(device d: DeviceDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(d.name?.isEmpty == false ? d.name! : d.ipAddress)
                    .font(.headline)
                Spacer()
                if detailRefreshing {
                    ProgressView().scaleEffect(0.75)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Device key") { Text(d.id).font(.caption.monospaced()).textSelection(.enabled) }
                LabeledContent("IP") { Text(d.ipAddress).font(.body.monospaced()) }
                LabeledContent("Last seen") { Text(formatLastSeen(d.lastSeen)) }
                LabeledContent("First seen") { Text(formatLastSeen(d.firstSeen)) }
                LabeledContent("DNS activity") {
                    Text(dnsActivityLabel(d)).foregroundStyle(activityColor(d))
                }
                LabeledContent("Queries (total)") { Text(formatCount(d.queryCountTotal)) }
                LabeledContent("Queries (24h)") { Text(formatCount(d.queryCount24h)) }
            }

            Text(
                "Hostname, MAC, and vendor are not populated in the DNS-only MVP. Per-device “protection” policy is not implemented — the engine field is reserved."
            )
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

            HStack {
                Button("Refresh counts") {
                    Task { await refreshDetailFromEngine() }
                }
                Button("Rename…") {
                    renameId = d.id
                    renameText = d.name ?? ""
                }
                Spacer()
                Button("Done") { detailDevice = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No devices yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(
                "When LAN clients send DNS to NetSentrix, each source IP becomes a device here. Point your router’s DHCP DNS at this Mac, renew leases, then refresh."
            )
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func dnsActivityLabel(_ d: DeviceDTO) -> String {
        if d.recentlySeenDns { return "Active (24h)" }
        if d.queryCountTotal > 0 { return "Idle" }
        return "No queries"
    }

    private func activityColor(_ d: DeviceDTO) -> Color {
        if d.recentlySeenDns { return Theme.allowed }
        if d.queryCountTotal > 0 { return Theme.warning }
        return Theme.textSecondary
    }

    private func formatCount(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatLastSeen(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        return ProductStatusAdapter.formattedRelativeTime(epochMs: ms)
    }
}
