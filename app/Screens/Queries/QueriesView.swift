import SwiftUI

struct QueriesView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var lastRefreshedAt = Date()
    @State private var selectedQueryIds = Set<Int64>()

    var body: some View {
        let displayQueries = engine.mergedDisplayQueries()
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
                Text("Updated \(relativeRefreshString())")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Live stream via WebSocket when the engine is reachable; list still polls every 10s to stay in sync. Right-click a row or select one and use Block / Allow — rules apply immediately.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                Button("Refresh now") {
                    Task {
                        await engine.refreshQueries(limit: 100)
                        lastRefreshedAt = Date()
                    }
                }
                .disabled(engine.isRefreshingQueries)

                let domain = primarySelectedDomain(in: displayQueries)
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

            if engine.hasCompletedInitialQueriesFetch, displayQueries.isEmpty, engine.queriesFetchError == nil {
                emptyState
            } else if !displayQueries.isEmpty {
                Table(displayQueries, selection: $selectedQueryIds) {
                    TableColumn("Device") { row in
                        queryRowChrome(for: row) {
                            Text(row.deviceId ?? "—").lineLimit(1)
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                    TableColumn("Domain") { row in
                        queryRowChrome(for: row) {
                            HStack(spacing: 6) {
                                Text(row.domain).lineLimit(1)
                                outcomeBadge(for: row)
                            }
                        }
                        .contextMenu { domainRuleMenu(for: row) }
                    }
                    TableColumn("Action") { row in
                        queryRowChrome(for: row) {
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
                        queryRowChrome(for: row) {
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
        .task {
            engine.retainDnsEventsWebSocket()
            await engine.refreshQueries(limit: 100)
            lastRefreshedAt = Date()
            defer { engine.releaseDnsEventsWebSocket() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await engine.refreshQueries(limit: 100)
                lastRefreshedAt = Date()
            }
        }
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
    private func queryRowChrome<Content: View>(for row: DnsQueryItem, @ViewBuilder content: () -> Content) -> some View {
        let bg: Color = {
            if row.isBlockedOutcome { Theme.blocked.opacity(0.12) }
            else if row.isAllowedOutcome { Theme.allowed.opacity(0.1) }
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
