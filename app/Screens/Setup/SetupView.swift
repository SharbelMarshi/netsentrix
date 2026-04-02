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

                Text("Use your router’s DHCP DNS settings so devices on your network send DNS to NetSentrix on this Mac.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)

                SetupCard(title: "Protection") {
                    if !engine.hasCompletedInitialHealthFetch {
                        Label("Checking…", systemImage: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        protectionSummary(snap: snap)
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

    private var engineAvailabilityBlock: some View {
        Group {
            if !engine.hasCompletedInitialHealthFetch {
                Text("Checking engine…").foregroundStyle(Theme.textSecondary)
            } else if let h = engine.lastHealth {
                LabeledContent("Status") {
                    Text("Reachable (v\(h.version))")
                        .foregroundStyle(Theme.allowed)
                }
                Text("The control API on this Mac can talk to NetSentrix Core.")
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
        VStack(alignment: .leading, spacing: 8) {
            if !engine.hasCompletedInitialStatsFetch || !engine.hasCompletedInitialQueriesFetch {
                Text("Checking DNS traffic…")
                    .foregroundStyle(Theme.textSecondary)
            } else if let s = engine.lastStats {
                if s.totalQueries > 0 {
                    Text("DNS queries are reaching NetSentrix.")
                        .foregroundStyle(Theme.allowed)
                    Text("Seen \(s.distinctDevices) device(s) in stats; last activity is reflected on the Dashboard.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No DNS queries detected yet.")
                        .foregroundStyle(Theme.warning)
                    Text("After router DNS points here, reconnect Wi‑Fi or renew DHCP on a device, then wait a minute.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Couldn’t load verification stats.")
                    .foregroundStyle(Theme.textSecondary)
            }
            if snap.traffic == .receiving {
                Label("Traffic: receiving DNS through NetSentrix", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.allowed)
            }
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
            if let tok = h.apiTokenFile {
                Text("API token path: \(tok)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
