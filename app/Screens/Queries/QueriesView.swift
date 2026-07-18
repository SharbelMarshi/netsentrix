import SwiftUI

struct QueriesView: View {
    @EnvironmentObject private var engine: EngineService
    @EnvironmentObject private var appModel: AppViewModel
    @State private var lastRefreshedAt = Date()
    @State private var selectedQueryIds = Set<Int64>()
    /// Stable snapshot for `Table` — updated only when engine data or filters change (avoids identity churn from recomputing `body`).
    @State private var tableRows: [DnsQueryItem] = []

    private var deviceFilter: String? {
        let s = appModel.queriesDeviceFilterId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    private var highlightDomain: String? {
        let s = appModel.queriesHighlightDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    private func rebuildTableRows() {
        var rows = engine.mergedDisplayQueries(deviceFilter: deviceFilter)
        if let h = highlightDomain?.lowercased() {
            rows.sort { a, b in
                let ma = a.domain.lowercased() == h
                let mb = b.domain.lowercased() == h
                if ma != mb { return ma && !mb }
                return a.id > b.id
            }
        }
        tableRows = rows
        let valid = Set(rows.map(\.id))
        selectedQueryIds = selectedQueryIds.intersection(valid)
    }

    private var liveFeedBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(liveFeedColor)
                .frame(width: 8, height: 8)
            Text(liveFeedLabel)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .help("Connection state of the live query stream (GET /ws)")
    }

    private var liveFeedColor: Color {
        switch engine.liveFeedStatus {
        case .live: return Theme.allowed
        case .connecting, .reconnecting: return Theme.warning
        case .idle: return Theme.infoMuted
        }
    }

    private var liveFeedLabel: String {
        switch engine.liveFeedStatus {
        case .live: return "Live"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .idle: return "Live stream off"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queries")
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
                liveFeedBadge
                Text("·")
                    .foregroundStyle(Theme.textSecondary)
                Text("Updated \(relativeRefreshString())")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Live stream via WebSocket when the engine is reachable; list still polls every 10s to stay in sync. Right-click a row or select one and use Block / Allow — rules apply immediately.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            if deviceFilter != nil || highlightDomain != nil {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(Theme.accent.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        if let d = deviceFilter {
                            Text("Filtered to device \(Self.shortDeviceLabel(d))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if let h = highlightDomain {
                            Text("Highlight: \(h)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Clear") {
                        appModel.clearQueriesNavigationContext()
                        Task {
                            await engine.refreshQueries(limit: 100, deviceId: nil)
                            lastRefreshedAt = Date()
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardBackground))
            }

            HStack(spacing: 10) {
                Button("Refresh now") {
                    Task {
                        await engine.refreshQueries(limit: 100, deviceId: deviceFilter)
                        lastRefreshedAt = Date()
                    }
                }
                .disabled(engine.isRefreshingQueries)

                let domain = primarySelectedDomain(in: tableRows)
                Button("Block domain") {
                    guard let domain else { return }
                    Task { await engine.blockDomain(domain) }
                }
                .disabled(domain == nil || engine.isApplyingDomainRule || engine.isEngineUnreachable)

                Button("Allow domain") {
                    guard let domain else { return }
                    Task { await engine.allowDomain(domain) }
                }
                .disabled(domain == nil || engine.isApplyingDomainRule || engine.isEngineUnreachable)

                if engine.isApplyingDomainRule {
                    ProgressView().scaleEffect(0.85)
                    Text("Applying rule…").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            legendRow

            if let ok = engine.lastDomainRuleSuccess {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.allowed)
                    Text(ok)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Dismiss") {
                        engine.clearDomainRuleSuccess()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.allowed.opacity(0.12)))
            }

            if let e = engine.lastOperationError {
                Text(e)
                    .font(.subheadline)
                    .foregroundStyle(Theme.blocked)
            }

            if engine.hasCompletedInitialQueriesFetch, tableRows.isEmpty, engine.queriesFetchError == nil {
                emptyState
            } else if !tableRows.isEmpty {
                Table(tableRows, selection: $selectedQueryIds) {
                    TableColumn("Device") { row in
                        queryRowChrome(for: row, highlightDomain: highlightDomain) {
                            Text(row.deviceId ?? "—").lineLimit(1)
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                    TableColumn("Domain") { row in
                        queryRowChrome(for: row, highlightDomain: highlightDomain) {
                            HStack(spacing: 6) {
                                Text(row.domain).lineLimit(1)
                                outcomeBadge(for: row)
                            }
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                    TableColumn("Action") { row in
                        queryRowChrome(for: row, highlightDomain: highlightDomain) {
                            Text(row.action)
                                .foregroundStyle(
                                    row.isBlockedOutcome
                                        ? Theme.blocked
                                        : (row.isAllowedOutcome ? Theme.allowed : Theme.textSecondary)
                                )
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                    TableColumn("Type") { row in
                        queryRowChrome(for: row, highlightDomain: highlightDomain) {
                            Text(row.queryType)
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                }
                .frame(minHeight: 200)
            } else if engine.queriesFetchError == nil {
                ProgressView("Loading queries…")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 24)
            }

            if let e = engine.queriesFetchError {
                Text(e).font(.caption).foregroundStyle(Theme.blocked)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .onChange(of: engine.queriesDisplayRevision) { _ in rebuildTableRows() }
        .onChange(of: appModel.queriesDeviceFilterId) { _ in rebuildTableRows() }
        .onChange(of: appModel.queriesHighlightDomain) { _ in rebuildTableRows() }
        .onAppear { rebuildTableRows() }
        .task(id: "\(appModel.queriesDeviceFilterId ?? "")|\(appModel.queriesHighlightDomain ?? "")") {
            engine.retainDnsEventsWebSocket()
            defer { engine.releaseDnsEventsWebSocket() }
            while !Task.isCancelled {
                let trimmed = appModel.queriesDeviceFilterId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let did = (trimmed?.isEmpty == false) ? trimmed : nil
                await engine.refreshQueries(limit: 100, deviceId: did)
                lastRefreshedAt = Date()
                rebuildTableRows()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
            }
        }
    }

    private static func shortDeviceLabel(_ deviceId: String) -> String {
        if deviceId.hasPrefix("ip:") {
            return String(deviceId.dropFirst(3))
        }
        return deviceId
    }

    @ViewBuilder
    private func domainRuleMenu(for row: DnsQueryItem) -> some View {
        Button("Block «\(row.domain)»") {
            Task { await engine.blockDomain(row.domain) }
        }
        .disabled(engine.isApplyingDomainRule || engine.isEngineUnreachable)
        Button("Allow «\(row.domain)»") {
            Task { await engine.allowDomain(row.domain) }
        }
        .disabled(engine.isApplyingDomainRule || engine.isEngineUnreachable)
    }

    @ViewBuilder
    private func outcomeBadge(for row: DnsQueryItem) -> some View {
        if row.isBlockedOutcome {
            Text("BLOCKED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.blocked)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.blocked.opacity(0.15)))
        } else if row.isAllowedOutcome {
            Text("ALLOWED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.allowed)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.allowed.opacity(0.15)))
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            Text("Row tint reflects that DNS answer (blocked vs allowed), not the full rules list.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.blocked.opacity(0.2))
                    .frame(width: 14, height: 10)
                Text("Blocked").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.allowed.opacity(0.15))
                    .frame(width: 14, height: 10)
                Text("Allowed").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func queryRowChrome<Content: View>(for row: DnsQueryItem, highlightDomain: String?, @ViewBuilder content: () -> Content) -> some View {
        let matchHighlight: Bool = {
            guard let h = highlightDomain?.lowercased(), !h.isEmpty else { return false }
            return row.domain.lowercased() == h
        }()
        let bg: Color = {
            if row.isBlockedOutcome { Theme.blocked.opacity(0.12) }
            else if row.isAllowedOutcome { Theme.allowed.opacity(0.1) }
            else if matchHighlight { Theme.accent.opacity(0.14) }
            else { Color.clear }
        }()
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }

    private func primarySelectedDomain(in rows: [DnsQueryItem]) -> String? {
        for row in rows where selectedQueryIds.contains(row.id) {
            return row.domain
        }
        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No DNS queries yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("No DNS queries — check dns.listen_addr and router DHCP DNS. Open Setup for step-by-step guidance.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func relativeRefreshString() -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: lastRefreshedAt, relativeTo: Date())
    }
}
