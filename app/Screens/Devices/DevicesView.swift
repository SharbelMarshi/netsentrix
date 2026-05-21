import SwiftUI

private enum DeviceDnsPolicyOption: String, CaseIterable {
    case normal
    case restricted
    case paused
    case blocked

    var menuTitle: String {
        switch self {
        case .normal: return "Normal (default filtering)"
        case .restricted: return "Restricted (allowlist only)"
        case .paused: return "Paused (SERVFAIL)"
        case .blocked: return "Blocked (sinkhole all)"
        }
    }

    /// Paused/blocked are the most disruptive; confirm before applying.
    var requiresConfirmation: Bool {
        switch self {
        case .paused, .blocked: return true
        case .normal, .restricted: return false
        }
    }
}

private struct PendingDevicePolicyChange: Identifiable {
    let deviceId: String
    let deviceLabel: String
    let nextPolicy: DeviceDnsPolicyOption

    var id: String { "\(deviceId)-\(nextPolicy.rawValue)" }
}

struct DevicesView: View {
    @EnvironmentObject private var engine: EngineService
    @EnvironmentObject private var appModel: AppViewModel
    @State private var renameId: String?
    @State private var renameText = ""
    @State private var detailDevice: DeviceDTO?
    @State private var detailRefreshing = false
    @State private var tagsEditText = ""
    @State private var pendingPolicyChange: PendingDevicePolicyChange?

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
            .disabled(engine.isApplyingDeviceChange)

            if let s = engine.lastDeviceControlSuccess {
                HStack(spacing: 8) {
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(Theme.allowed)
                    Button("Dismiss") {
                        engine.clearDeviceControlSuccess()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
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
                        HStack(spacing: 6) {
                            Text(d.name?.isEmpty == false ? d.name! : "—")
                            if effectivePolicyKey(d) == "blocked" {
                                Text("BLOCKED")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.blocked.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                        }
                        .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 80, ideal: 160)
                    TableColumn("IP") { d in
                        Text(d.ipAddress).font(.body.monospaced())
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 100, ideal: 130)
                    TableColumn("DNS activity") { d in
                        Text(dnsActivityLabel(d))
                            .foregroundStyle(activityColor(d))
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("Mode (now)") { d in
                        HStack(spacing: 6) {
                            Text(dnsPolicyShortLabel(effectivePolicyKey(d)))
                                .foregroundStyle(policyForeground(effectivePolicyKey(d)))
                            if d.scheduleOverrideActive {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warning)
                                    .help("A schedule override is active now (engine local time).")
                            }
                        }
                        .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 88, ideal: 112)
                    TableColumn("Saved") { d in
                        Text(dnsPolicyShortLabel(d.dnsPolicy))
                            .foregroundStyle(
                                d.effectiveDiffersFromStored ? Theme.warning : Theme.textSecondary
                            )
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 72, ideal: 88)
                    TableColumn("Tags") { d in
                        Text(d.tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : d.tags)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textSecondary)
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Last seen") { d in
                        Text(formatLastSeen(d.lastSeen))
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("Queries (total)") { d in
                        Text(formatCount(d.queryCountTotal))
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Last 24h") { d in
                        Text(formatCount(d.queryCount24h))
                            .contextMenu { deviceContextMenu(for: d) }
                    }
                    .width(min: 60, ideal: 72)
                    TableColumn("") { d in
                        HStack(spacing: 6) {
                            Menu("Mode") {
                                devicePolicyButtons(for: d, includeRestoreLabel: true)
                            }
                            .disabled(engine.isEngineUnreachable || engine.isApplyingDeviceChange)
                            Button("Details") {
                                detailDevice = d
                                Task { await refreshDetailFromEngine() }
                            }
                            .buttonStyle(.borderless)
                            .disabled(engine.isApplyingDeviceChange)
                            Button("Rename") {
                                renameId = d.id
                                renameText = d.name ?? ""
                            }
                            .buttonStyle(.borderless)
                            .disabled(engine.isApplyingDeviceChange)
                        }
                    }
                    .width(min: 200, ideal: 240)
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
        .onChange(of: detailDevice?.id) { _ in
            tagsEditText = detailDevice?.tags ?? ""
        }
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
                                await refreshDetailIfOpen(deviceId: id)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 320)
        }
        .confirmationDialog(
            "Change DNS mode?",
            isPresented: Binding(
                get: { pendingPolicyChange != nil },
                set: { if !$0 { pendingPolicyChange = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingPolicyChange
        ) { p in
            Button("Set to \(dnsPolicyShortLabel(p.nextPolicy.rawValue))") {
                Task {
                    await engine.setDeviceDnsPolicy(id: p.deviceId, dnsPolicy: p.nextPolicy.rawValue)
                    await refreshDetailIfOpen(deviceId: p.deviceId)
                    pendingPolicyChange = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPolicyChange = nil
            }
        } message: { p in
            Text(policyConfirmMessage(p))
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

    private func refreshDetailIfOpen(deviceId: String) async {
        guard detailDevice?.id == deviceId else { return }
        await refreshDetailFromEngine()
    }

    private func deviceLabel(_ d: DeviceDTO) -> String {
        if let n = d.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
        return d.ipAddress
    }

    private func effectivePolicyKey(_ d: DeviceDTO) -> String {
        d.effectiveDnsPolicy.lowercased()
    }

    private func requestPolicyChange(deviceId: String, deviceLabel: String, next: DeviceDnsPolicyOption, storedPolicy: String) {
        let stored = storedPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard stored != next.rawValue else { return }
        if next.requiresConfirmation {
            pendingPolicyChange = PendingDevicePolicyChange(
                deviceId: deviceId,
                deviceLabel: deviceLabel,
                nextPolicy: next
            )
        } else {
            Task {
                await engine.setDeviceDnsPolicy(id: deviceId, dnsPolicy: next.rawValue)
                await refreshDetailIfOpen(deviceId: deviceId)
            }
        }
    }

    private func policyConfirmMessage(_ p: PendingDevicePolicyChange) -> String {
        let who = p.deviceLabel
        switch p.nextPolicy {
        case .blocked:
            return "\(who): all queries for this device are answered as blocked. Allow rules can still permit specific names."
        case .paused:
            return "\(who): DNS returns SERVFAIL for this device (nothing is forwarded upstream)."
        case .restricted, .normal:
            return ""
        }
    }

    @ViewBuilder
    private func devicePolicyButtons(for d: DeviceDTO, includeRestoreLabel: Bool) -> some View {
        let label = deviceLabel(d)
        let stored = d.dnsPolicy.lowercased()
        ForEach(DeviceDnsPolicyOption.allCases, id: \.rawValue) { opt in
            Button {
                requestPolicyChange(deviceId: d.id, deviceLabel: label, next: opt, storedPolicy: stored)
            } label: {
                HStack {
                    Text(opt.menuTitle)
                    Spacer()
                    if effectivePolicyKey(d) == opt.rawValue {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(
                engine.isEngineUnreachable
                    || engine.isApplyingDeviceChange
                    || stored == opt.rawValue
            )
        }
        if includeRestoreLabel, stored != DeviceDnsPolicyOption.normal.rawValue {
            Divider()
            Button("Restore — saved mode Normal") {
                requestPolicyChange(
                    deviceId: d.id,
                    deviceLabel: label,
                    next: .normal,
                    storedPolicy: stored
                )
            }
            .disabled(engine.isEngineUnreachable || engine.isApplyingDeviceChange)
        }
    }

    @ViewBuilder
    private func deviceContextMenu(for d: DeviceDTO) -> some View {
        devicePolicyButtons(for: d, includeRestoreLabel: true)
        Divider()
        Button("Details…") {
            detailDevice = d
            Task { await refreshDetailFromEngine() }
        }
        Button("Rename…") {
            renameId = d.id
            renameText = d.name ?? ""
        }
        Button("View queries for this device") {
            appModel.openQueries(deviceFilter: d.id, highlightDomain: nil)
        }
    }

    @ViewBuilder
    private func deviceDetailSheet(device d: DeviceDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deviceLabel(d))
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text("Mode now: \(dnsPolicyShortLabel(effectivePolicyKey(d)))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(policyForeground(effectivePolicyKey(d)))
                        if effectivePolicyKey(d) == "blocked" {
                            Text("BLOCKED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.blocked.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
                if detailRefreshing {
                    ProgressView().scaleEffect(0.75)
                }
            }

            if d.scheduleOverrideActive {
                Label(
                    "A schedule override is active right now (engine local wall time). Saved mode may differ from what you see above.",
                    systemImage: "clock.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(Theme.warning)
            }

            if d.effectiveDiffersFromStored {
                Text("Saved in database: \(dnsPolicyShortLabel(d.dnsPolicy)) — effective now: \(dnsPolicyShortLabel(effectivePolicyKey(d))).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
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
                LabeledContent("Effective mode") {
                    Text(dnsPolicyDescription(effectivePolicyKey(d)))
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags (comma-separated)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("e.g. Child, Guest", text: $tagsEditText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save tags") {
                        Task {
                            await engine.setDeviceTags(id: d.id, tags: tagsEditText)
                            await refreshDetailFromEngine()
                        }
                    }
                    .disabled(engine.isEngineUnreachable || engine.isApplyingDeviceChange)
                }
            }

            Text(
                "Hostname, MAC, and vendor are not populated from DNS alone. Restricted = allowlist-only (add Allow rules for names this device may resolve). Global block/allow lists still apply on top of device mode."
            )
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

            Text("Set saved mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(DeviceDnsPolicyOption.allCases, id: \.rawValue) { opt in
                    Button {
                        requestPolicyChange(
                            deviceId: d.id,
                            deviceLabel: deviceLabel(d),
                            next: opt,
                            storedPolicy: d.dnsPolicy
                        )
                    } label: {
                        HStack {
                            Text(opt.menuTitle)
                            Spacer()
                            if d.dnsPolicy.lowercased() == opt.rawValue {
                                Text("saved")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        engine.isEngineUnreachable
                            || engine.isApplyingDeviceChange
                            || d.dnsPolicy.lowercased() == opt.rawValue
                    )
                }
            }

            HStack {
                Button("Refresh") {
                    Task { await refreshDetailFromEngine() }
                }
                .disabled(engine.isApplyingDeviceChange)
                Button("View queries…") {
                    appModel.openQueries(deviceFilter: d.id, highlightDomain: nil)
                    detailDevice = nil
                }
                .disabled(engine.isEngineUnreachable)
                Button("Rename…") {
                    renameId = d.id
                    renameText = d.name ?? ""
                }
                .disabled(engine.isApplyingDeviceChange)
                Spacer()
                Button("Done") { detailDevice = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
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

    private func dnsPolicyShortLabel(_ p: String) -> String {
        switch p.lowercased() {
        case "normal": return "Normal"
        case "restricted": return "Restricted"
        case "paused": return "Paused"
        case "blocked": return "Blocked"
        default: return p
        }
    }

    private func dnsPolicyDescription(_ p: String) -> String {
        switch p.lowercased() {
        case "normal":
            return "Standard block/allow rules apply."
        case "restricted":
            return "Only names on the allowlist resolve; everything else is blocked."
        case "paused":
            return "DNS queries get SERVFAIL (no upstream) for this device."
        case "blocked":
            return "All queries answered as blocked (sinkhole / NXDOMAIN per policy)."
        default:
            return p
        }
    }

    private func policyForeground(_ p: String) -> Color {
        switch p.lowercased() {
        case "blocked": return Theme.blocked
        case "paused": return Theme.warning
        case "restricted": return Theme.warning
        default: return Theme.textSecondary
        }
    }
}
