import SwiftUI

private struct NetsentrixCard<Content: View>: View {
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
                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

struct DashboardView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var lastRefreshedAt = Date()
    @State private var showTechnical = false

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
                headerRow

                if !engine.hasCompletedInitialHealthFetch && engine.isRefreshingHealth {
                    ProgressView("Loading status…")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    NetsentrixCard(title: "Protection") {
                        protectionBlock(snap: snap)
                    }

                    NetsentrixCard(title: "Engine") {
                        engineBlock(snap: snap)
                    }

                    NetsentrixCard(title: "Traffic") {
                        trafficBlock(snap: snap)
                    }

                    NetsentrixCard(title: "Activity summary") {
                        activityBlock()
                    }

                    NetsentrixCard(title: "Last DNS query") {
                        lastQueryBlock
                    }
                }

                if let err = engine.statsFetchError {
                    Text(err).font(.caption).foregroundStyle(Theme.warning)
                }
                if let qe = engine.queriesFetchError {
                    Text(qe).font(.caption).foregroundStyle(Theme.warning)
                }

                refreshRow
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task {
            engine.retainDnsEventsWebSocket()
            defer { engine.releaseDnsEventsWebSocket() }
            await engine.refreshAllDashboardData()
            lastRefreshedAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await engine.refreshAllDashboardData()
                lastRefreshedAt = Date()
            }
        }
    }

    private func relativeRefreshString() -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: lastRefreshedAt, relativeTo: Date())
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                Circle()
                    .fill(engine.isEngineUnreachable ? Theme.blocked : Theme.allowed)
                    .frame(width: 8, height: 8)
                Text(engine.isEngineUnreachable ? "Can’t reach engine" : "Engine reachable")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textSecondary)
                Text("Updated \(relativeRefreshString())")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Refreshes about every 12 seconds while this screen is open, or press ⌘R.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
        }
    }

    private func protectionColor(_ snap: ProductStatusSnapshot) -> Color {
        switch snap.protection {
        case .active: return Theme.allowed
        case .partial: return Theme.warning
        case .notActive: return Theme.blocked
        }
    }

    private func protectionBlock(snap: ProductStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Protection:")
                    .foregroundStyle(Theme.textSecondary)
                Text(snap.protection.rawValue)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(protectionColor(snap))
            }
            Text(snap.protectionReason)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
            if let next = snap.protectionNextStep {
                Text(next)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            Text("Setup: \(snap.setup.rawValue) — \(snap.setupReason)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let sNext = snap.setupNextStep {
                Text(sNext)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func engineBlock(snap: ProductStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snap.engineTitle)
                    .font(.headline)
                    .foregroundStyle(engineTitleColor(snap.engine))
                if engine.isRefreshingHealth {
                    ProgressView().scaleEffect(0.7)
                }
            }
            Text(snap.dnsSummaryPrimary)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)

            if let h = engine.lastHealth {
                DisclosureGroup(isExpanded: $showTechnical) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("API listen") { Text(h.apiListen).font(.caption.monospaced()) }
                        LabeledContent("DNS listen") { Text(h.dnsListen).font(.caption.monospaced()) }
                        LabeledContent("DNS UDP") {
                            Text(dnsBindStatus(h.dnsUdpBound, fallback: h.dnsBound)).font(.caption)
                        }
                        LabeledContent("DNS TCP") {
                            Text(dnsTcpBindStatus(h.dnsTcpBound)).font(.caption)
                        }
                        if let te = h.dnsTcpLastError, !te.isEmpty {
                            LabeledContent("TCP bind error") {
                                Text(te).font(.caption2).foregroundStyle(Theme.warning)
                            }
                        }
                        LabeledContent("Version") { Text(h.version).font(.caption) }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Technical details")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func dnsBindStatus(_ explicit: Bool?, fallback: Bool) -> String {
        let v = explicit ?? fallback
        return v ? "Listening" : "Not listening"
    }

    private func dnsTcpBindStatus(_ v: Bool?) -> String {
        guard let v else { return "Unknown (older engine)" }
        return v ? "Listening" : "Not listening"
    }

    private func engineTitleColor(_ e: ProductEngineState) -> Color {
        switch e {
        case .running: return Theme.allowed
        case .starting: return Theme.warning
        case .stopped, .error: return Theme.blocked
        }
    }

    private func trafficBlock(snap: ProductStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snap.traffic.rawValue)
                .font(.headline)
                .foregroundStyle(snap.traffic == .receiving ? Theme.allowed : Theme.textSecondary)

            let spark = engine.trafficSparklineBuckets
            let sparkMax = spark.max() ?? 0
            if sparkMax > 0 {
                GeometryReader { geo in
                    let barW = max(2, (geo.size.width - 22) / 12)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0 ..< 12, id: \.self) { i in
                            let v = spark[i]
                            let h = max(3, CGFloat(v) / CGFloat(sparkMax) * (geo.size.height - 2))
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Theme.accent.opacity(0.75))
                                .frame(width: barW, height: h)
                        }
                    }
                }
                .frame(height: 36)
                Text("DNS events in the last minute (12×5s buckets, live stream).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))
            }

            if let q = engine.queries.first {
                Text("Last query \(ProductStatusAdapter.formattedRelativeTime(epochMs: q.timestampMs))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if let ts = engine.lastHealth?.lastClientQueryMs {
                Text("Last logged query \(ProductStatusAdapter.formattedRelativeTime(epochMs: ts))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if snap.traffic == .noneYet {
                Text("No traffic detected yet. Configure your router DNS to start seeing network activity.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func activityBlock() -> some View {
        Group {
            if let s = engine.lastStats {
                LabeledContent("Total queries") { Text("\(s.totalQueries)") }
                LabeledContent("Blocked") {
                    Text("\(s.blockedQueries) (\(String(format: "%.1f", s.blockedPercent))%)")
                }
                LabeledContent("Devices seen") { Text("\(s.distinctDevices)") }
                LabeledContent("Alerts (24h)") { Text("\(s.alertsLast24h)") }

                if s.totalQueries == 0 {
                    Text("No queries yet — normal right after install. Go to Setup to point your router at this Mac.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            } else if engine.statsFetchError != nil {
                Text("Couldn’t load activity.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Loading activity…").foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var lastQueryBlock: some View {
        Group {
            if let q = engine.queries.first {
                LabeledContent("Device") { Text(q.deviceId ?? "—").font(.body) }
                LabeledContent("Domain") { Text(q.domain).lineLimit(2) }
                LabeledContent("Action") {
                    Text(q.action)
                        .foregroundStyle(q.action.lowercased().contains("block") ? Theme.blocked : Theme.allowed)
                }
                LabeledContent("Time") {
                    Text(ProductStatusAdapter.formattedAbsoluteTime(epochMs: q.timestampMs))
                        .font(.caption)
                }
            } else if engine.hasCompletedInitialQueriesFetch {
                Text("No DNS queries have been detected yet.")
                    .foregroundStyle(Theme.textPrimary)
                Text("Configure your router DNS to start seeing activity, or open Setup for step-by-step guidance.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Loading…").foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var refreshRow: some View {
        Button("Refresh") {
            Task {
                await engine.refreshAllDashboardData()
                lastRefreshedAt = Date()
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(engine.isRefreshingDashboard)
    }

}
