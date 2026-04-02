import SwiftUI

struct AlertsView: View {
    @EnvironmentObject private var engine: EngineService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerts")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Button("Refresh") {
                Task { await engine.refreshAlerts() }
            }

            if engine.hasCompletedInitialAlertsFetch, engine.alerts.isEmpty {
                if let err = engine.lastOperationError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(Theme.blocked)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.allowed.opacity(0.85))
                        Text("No alerts")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("The rules engine is not emitting alerts yet — nothing to show here.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else if !engine.alerts.isEmpty {
                List(engine.alerts) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.severity.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(severityColor(a.severity))
                            Text(a.category)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(a.message)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.cardBackground)
                }
                .scrollContentBackground(.hidden)
            } else if engine.lastOperationError == nil {
                ProgressView("Loading alerts…")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 24)
            }

            if !engine.alerts.isEmpty, let e = engine.lastOperationError {
                Text(e).font(.caption).foregroundStyle(Theme.blocked)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task { await engine.refreshAlerts() }
    }

    private func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical", "alert", "error": return Theme.blocked
        case "warning", "warn": return Theme.warning
        case "info", "informational": return Theme.infoMuted
        default: return Theme.accent
        }
    }
}
