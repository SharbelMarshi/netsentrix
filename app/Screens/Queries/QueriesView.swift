import SwiftUI

struct QueriesView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var lastRefreshedAt = Date()

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
                Text("Updated \(relativeRefreshString())")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Live stream via WebSocket when the engine is reachable; list still polls every 10s to stay in sync.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            Button("Refresh now") {
                Task {
                    await engine.refreshQueries(limit: 100)
                    lastRefreshedAt = Date()
                }
            }

            let displayQueries = engine.mergedDisplayQueries()
            if engine.hasCompletedInitialQueriesFetch, displayQueries.isEmpty, engine.queriesFetchError == nil {
                emptyState
            } else if !displayQueries.isEmpty {
                Table(displayQueries) {
                    TableColumn("Device") { row in
                        Text(row.deviceId ?? "—").lineLimit(1)
                    }
                    TableColumn("Domain") { row in
                        Text(row.domain).lineLimit(1)
                    }
                    TableColumn("Action") { row in
                        Text(row.action)
                            .foregroundStyle(row.action.lowercased().contains("block") ? Theme.blocked : Theme.allowed)
                    }
                    TableColumn("Type") { row in
                        Text(row.queryType)
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
