import Charts
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

                    if let hints = engine.lastHealth?.setupHints, !hints.isEmpty {
                        NetsentrixCard(title: "Setup & diagnostics") {
                            setupHintsBlock(hints: hints)
                        }
                    }

                    NetsentrixCard(title: "Engine") {
                        engineBlock(snap: snap)
                    }

                    NetsentrixCard(title: "Traffic") {
                        trafficBlock(snap: snap)
                    }

                    if let ins = engine.lastInsights, !ins.topDomains.isEmpty {
                        NetsentrixCard(title: "Usage insights (rolling \(ins.windowHours)h)") {
                            insightsBlock(ins: ins)
                        }
                    } else if let ie = engine.insightsFetchError {
                        NetsentrixCard(title: "Usage insights") {
                            Text(ie).font(.caption).foregroundStyle(Theme.warning)
                        }
                    }

                    NetsentrixCard(title: "DNS cache & performance") {
                        dnsCachePerformanceBlock()
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
            Text("Protection proof is LAN-scoped (non-loopback clients in the engine window) — not a claim about every device on the network.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.85))
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
            if let v = snap.verification {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proof (engine, LAN-only)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(v.distinctLanClients) LAN client IP(s) in window · \(v.lanQueriesInWindow) lookups · window \(v.windowSecs / 60) min")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let t = v.lastLanQueryMs {
                        Text("Last LAN DNS \(ProductStatusAdapter.formattedRelativeTime(epochMs: t))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary.opacity(0.95))
                    }
                }
                .padding(.top, 4)
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

    @ViewBuilder
    private func setupHintsBlock(hints: [SetupHintDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine-derived hints — not a guarantee about every device or bypass path.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            ForEach(Array(hints.enumerated()), id: \.offset) { idx, h in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(h.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(h.severity == "warning" ? Theme.warning : Theme.textPrimary)
                        if h.severity == "warning" {
                            Text("Warning")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.warning.opacity(0.15)))
                        }
                    }
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
                .padding(.vertical, 4)
                if idx + 1 < hints.count {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    private func insightsBlock(ins: InsightsDailyDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let h = ins.peakHourLocal {
                Text("Peak local hour: \(h):00 · \(ins.peakHourQueryCount) queries sampled in window")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !ins.topDevices.isEmpty {
                Text("Top devices (by query count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(Array(ins.topDevices.prefix(5)), id: \.deviceId) { d in
                    HStack {
                        Text(insightsDeviceLabel(d.deviceId)).lineLimit(1)
                        Spacer()
                        Text("\(d.queryCount)").font(.caption.monospaced())
                    }
                    .font(.caption)
                }
            }
            Text("Top domains")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Chart(Array(ins.topDomains.prefix(8))) { row in
                BarMark(
                    x: .value("Queries", row.queryCount),
                    y: .value("Domain", row.domain)
                )
                .foregroundStyle(Theme.accent.opacity(0.85))
            }
            .chartXAxisLabel("Queries", position: .bottom, alignment: .center)
            .frame(height: 200)
            .animation(reduceMotion ? nil : .default, value: ins.untilMs)

            Text("Family labels are bundled rules only — not live threat feeds.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
        }
    }

    private func insightsDeviceLabel(_ deviceId: String) -> String {
        if deviceId.hasPrefix("ip:") { return String(deviceId.dropFirst(3)) }
        return deviceId
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
                        if let ue = h.dnsLastError, !ue.isEmpty {
                            LabeledContent("UDP bind error") {
                                Text(ue).font(.caption2).foregroundStyle(Theme.warning)
                            }
                        }
                        if let te = h.dnsTcpLastError, !te.isEmpty {
                            LabeledContent("TCP bind error") {
                                Text(te).font(.caption2).foregroundStyle(Theme.warning)
                            }
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
                        if let p = h.apiTokenFile {
                            LabeledContent("API token file") { Text(p).font(.caption2).textSelection(.enabled) }
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
                Text("Live stream: recent DNS events (may include any client; engine proof uses LAN-only counts on the Protection card).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))
            }

            if let q = engine.queries.first {
                Text("Last query \(ProductStatusAdapter.formattedRelativeTime(epochMs: q.timestampMs))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if let ts = engine.lastHealth?.lastClientQueryMs {
                Text("Last LAN client DNS (engine) \(ProductStatusAdapter.formattedRelativeTime(epochMs: ts))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if snap.traffic == .noneYet {
                Text("No traffic detected yet. Configure your router DNS to start seeing network activity.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func dnsCachePerformanceBlock() -> some View {
        Group {
            if let s = engine.lastStats {
                let hits = s.dnsCacheHits
                let misses = s.dnsCacheMisses
                let lookups = ProductStatusAdapter.dnsCacheLookupsTotal(hits: hits, misses: misses)
                let hitPct = ProductStatusAdapter.dnsCacheHitRatePercent(hits: hits, misses: misses)

                Text(ProductStatusAdapter.dnsCacheHeadline(hitRatePercent: hitPct, lookupsTotal: lookups))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                if lookups > 0, let h = hits, let m = misses {
                    HStack(spacing: 20) {
                        LabeledContent("Hits") { Text("\(h)").monospacedDigit() }
                        LabeledContent("Misses") { Text("\(m)").monospacedDigit() }
                        if let p = hitPct {
                            LabeledContent("Hit rate") {
                                Text(String(format: "%.1f%%", p)).monospacedDigit()
                            }
                        }
                    }
                    .font(.subheadline)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let hitFrac = CGFloat(h) / CGFloat(lookups)
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.allowed.opacity(0.85))
                                .frame(width: max(0, w * hitFrac))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.textSecondary.opacity(0.28))
                                .frame(width: max(0, w * (1 - hitFrac)))
                        }
                    }
                    .frame(height: 10)
                    .padding(.vertical, 4)
                }

                Text(ProductStatusAdapter.dnsCacheExplanation(lookupsTotal: lookups))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let lat = ProductStatusAdapter.dnsLatencyExplanation(
                    avgMs: s.dnsAvgLatencyMs,
                    sampleCount: s.resolvedLatencySampleCount
                ) {
                    Text(lat)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary.opacity(0.95))
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let hist = engine.dnsCacheHitRateHistory
                if hist.count >= 2 {
                    Text("Hit rate over recent refreshes (higher bar = better reuse)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.9))
                        .padding(.top, 6)
                    let hMax = max(hist.max() ?? 1, 1)
                    GeometryReader { geo in
                        let barW = max(2, (geo.size.width - CGFloat(hist.count - 1) * 2) / CGFloat(hist.count))
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(hist.enumerated()), id: \.offset) { _, v in
                                let height = max(3, CGFloat(v) / CGFloat(hMax) * (geo.size.height - 2))
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Theme.accent.opacity(0.8))
                                    .frame(width: barW, height: height)
                            }
                        }
                    }
                    .frame(height: 32)
                    .padding(.top, 2)
                } else if lookups > 0 {
                    Text("A simple hit-rate trend will appear after a few automatic refreshes.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.85))
                        .padding(.top, 4)
                }
            } else if engine.statsFetchError != nil {
                Text("Couldn’t load cache metrics.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Loading…").foregroundStyle(Theme.textSecondary)
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

                Text("Activity totals count all logged queries. Active protection uses LAN-only signals (see Protection card).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))
                    .padding(.top, 2)

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
                if isLikelyLoopbackQueryDevice(q.deviceId) {
                    Text("This sample is from a loopback / local client — Setup verification uses LAN-only stats for protection proof.")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 4)
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

    private func isLikelyLoopbackQueryDevice(_ id: String?) -> Bool {
        guard let id else { return false }
        if id.contains("127.") { return true }
        if id.contains("::1") { return true }
        return false
    }

}
