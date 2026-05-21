import SwiftUI
import AppKit

private struct SetupCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

struct SetupView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var showAdvanced = false

    var body: some View {
        let healthFailed = engine.hasCompletedInitialHealthFetch
            && engine.lastHealth == nil
            && engine.healthFetchError != nil
        let snap = ProductStatusAdapter.snapshot(
            health: engine.lastHealth,
            stats: engine.lastStats,
            lastQuery: engine.queries.first,
            healthFetchFailed: healthFailed,
            healthErrorMessage: engine.healthFetchError
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Setup")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Point your router’s DHCP DNS at this Mac so LAN devices use NetSentrix as their resolver. The app can only observe and filter DNS that actually reaches this engine — not traffic that bypasses it.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)

                Text("Full appliance / operator steps live in the repo: `packaging/macos/MAC_MINI_APPLIANCE.md`.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))

                SetupCard(title: "Protection") {
                    if !engine.hasCompletedInitialHealthFetch {
                        Label("Checking…", systemImage: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        protectionSummary(snap: snap)
                    }
                }

                if let hints = engine.lastHealth?.setupHints, !hints.isEmpty {
                    SetupCard(title: "Guided checks") {
                        setupHintsContent(hints: hints)
                    }
                }

                SetupCard(title: "Engine availability") {
                    engineAvailabilityBlock
                }

                SetupCard(title: "Suggested router DNS IP") {
                    suggestedIpBlock
                }

                SetupCard(title: "Live verification") {
                    verificationBlock(snap: snap)
                }

                SetupCard(title: "Setup guidance") {
                    guidanceSteps
                }

                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedBlock
                } label: {
                    Text("Advanced")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Button("Refresh") {
                    Task { await engine.refreshAllDashboardData() }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task {
            await engine.refreshAllDashboardData()
        }
    }

    private func protectionSummary(snap: ProductStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snap.protection.rawValue)
                .font(.title3.weight(.semibold))
                .foregroundStyle(
                    snap.protection == .active ? Theme.allowed
                        : snap.protection == .partial ? Theme.warning : Theme.blocked
                )
            Text(snap.protectionReason)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
            if let n = snap.protectionNextStep {
                Text(n)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private func setupHintsContent(hints: [SetupHintDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These messages match what the engine can observe — they are hints, not proof of misconfiguration on every device.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(hints.enumerated()), id: \.offset) { idx, h in
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(h.severity == "warning" ? Theme.warning : Theme.textPrimary)
                    Text(h.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fix = h.suggestedFix, !fix.isEmpty {
                        Text(fix)
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if idx + 1 < hints.count {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    private var engineAvailabilityBlock: some View {
        Group {
            if !engine.hasCompletedInitialHealthFetch {
                Text("Checking engine…").foregroundStyle(Theme.textSecondary)
            } else if let h = engine.lastHealth {
                LabeledContent("Status") {
                    Text("Reachable (v\(h.version))")
                        .foregroundStyle(Theme.allowed)
                }
                Text("The control API on this Mac can talk to NetSentrix Core. If the app cannot save settings, the token file on disk must match the engine’s path (see Advanced).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if let err = engine.healthFetchError {
                Text("Can’t reach the NetSentrix engine.")
                    .foregroundStyle(Theme.blocked)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("Start NetSentrix Core, then tap Refresh.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private var suggestedIpBlock: some View {
        if let ip = engine.lastHealth?.suggestedLanIp {
            HStack {
                Text(ip).font(.body.monospaced())
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                }
            }
            Text("In your router, set DHCP DNS (primary) to this address — the machine running NetSentrix.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } else if engine.lastHealth != nil {
            Text("No LAN hint available from the engine.")
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text("—").foregroundStyle(Theme.textSecondary)
        }
    }

    private func verificationBlock(snap: ProductStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !engine.hasCompletedInitialHealthFetch {
                Text("Waiting for engine…")
                    .foregroundStyle(Theme.textSecondary)
            } else if let h = engine.lastHealth, let v = snap.verification {
                Text("Engine verification window: \(formatWindowMins(v.windowSecs)) (rolling). Counts are LAN clients only (loopback / localhost test queries excluded).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                let udpOk = h.dnsUdpBound ?? h.dnsBound
                if let tcp = h.dnsTcpBound {
                    HStack(spacing: 12) {
                        Label(udpOk ? "UDP DNS listening" : "UDP not bound", systemImage: udpOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(udpOk ? Theme.allowed : Theme.blocked)
                        Label(tcp ? "TCP DNS listening" : "TCP not bound", systemImage: tcp ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(tcp ? Theme.allowed : Theme.warning)
                    }
                } else {
                    Label(udpOk ? "UDP DNS listening" : "UDP not bound", systemImage: udpOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(udpOk ? Theme.allowed : Theme.blocked)
                }

                LabeledContent("Distinct LAN clients (window)") {
                    Text("\(v.distinctLanClients)").font(.body.monospaced())
                }
                LabeledContent("LAN DNS lookups (window)") {
                    Text("\(v.lanQueriesInWindow)").font(.body.monospaced())
                }
                if let t = v.lastLanQueryMs {
                    LabeledContent("Last LAN client DNS") {
                        Text(ProductStatusAdapter.formattedRelativeTime(epochMs: t))
                    }
                } else {
                    Text("No LAN client DNS logged yet (only loopback or no queries).")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }

                Text(partialVsActiveHint(v: v))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)

                if snap.traffic == .receiving {
                    Label("Traffic: LAN or logged DNS activity in scope", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.allowed)
                }
            } else if !engine.hasCompletedInitialStatsFetch {
                Text("Loading stats…")
                    .foregroundStyle(Theme.textSecondary)
            } else if engine.lastStats != nil {
                Text("Protection summary not available from this engine — update NetSentrix Core for LAN-specific verification.")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            } else {
                Text("Couldn’t load verification data.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func formatWindowMins(_ secs: UInt64) -> String {
        let m = secs / 60
        if m >= 60, m % 60 == 0 { return "\(m / 60) hour(s)" }
        if m >= 60 { return "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    private func partialVsActiveHint(v: ProtectionVerification) -> String {
        switch v.protectionState {
        case "active":
            return "Active means recent LAN client DNS in this window with DNS bound on a non-loopback address. It does not mean every device on the network is forced through NetSentrix — DoH, DoT, or static DNS can bypass."
        case "partial":
            if !v.lanCapable {
                return "Partial: DNS may be bound to loopback only, so other devices cannot reach this resolver — or LAN traffic has not appeared in the window yet."
            }
            return "Partial: DNS is LAN-reachable, but the engine has not seen enough recent LAN client queries in the window to report Active."
        default:
            return "Not Active: fix engine/DNS errors or pause state first, then revisit router DHCP DNS."
        }
    }

    private var guidanceSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(1, "Open your router’s admin page (often printed on the device).")
            stepRow(2, "Find LAN / DHCP settings and set the DNS server to the IP shown above (this Mac).")
            stepRow(3, "Reconnect devices or renew DHCP so they pick up the new DNS.")
            stepRow(4, "Return here and refresh — queries and devices should appear when traffic flows.")
        }
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var advancedBlock: some View {
        if let h = engine.lastHealth {
            LabeledContent("API listen") { Text(h.apiListen).font(.caption.monospaced()) }
            LabeledContent("DNS listen") { Text(h.dnsListen).font(.caption.monospaced()) }
            LabeledContent("Engine status") { Text(h.engineStatus).font(.caption.monospaced()) }
            LabeledContent("DNS UDP") {
                Text((h.dnsUdpBound ?? h.dnsBound) ? "bound" : "not bound").font(.caption)
            }
            LabeledContent("DNS TCP") {
                Text(h.dnsTcpBound.map { $0 ? "bound" : "not bound" } ?? "unknown").font(.caption)
            }
            if let p = h.configPath {
                LabeledContent("Config file") { Text(p).font(.caption2).textSelection(.enabled) }
            }
            if let p = h.netsentrixDataDir {
                LabeledContent("NetSentrix data dir") { Text(p).font(.caption2).textSelection(.enabled) }
            }
            if let p = h.dbPath {
                LabeledContent("Database") { Text(p).font(.caption2).textSelection(.enabled) }
            }
            if let tok = h.apiTokenFile {
                LabeledContent("API token file") { Text(tok).font(.caption2).textSelection(.enabled) }
            }
            Text("Unreachable means the HTTP API did not respond; not bound means DNS listeners failed while the API may still be up — check UDP/TCP errors above.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
