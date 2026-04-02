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
                        Text("No alerts right now")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(
                            "NetSentrix raises alerts from live DNS patterns: bursts from one device, many different domains in a short window, repeated blocked lookups, or a spike in total queries. Nothing has crossed those thresholds recently."
                        )
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else if !engine.alerts.isEmpty {
                List(engine.alerts) { a in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatAlertTime(a.timestampMs))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 8)
                            Text(a.severity.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(severityColor(a.severity))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(categoryTitle(a.category))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent.opacity(0.95))
                            if let line = deviceContextLine(a.deviceId) {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Text(a.message)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = alertDetailLine(a) {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
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

    private func formatAlertTime(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    /// Short line for list rows: IP or id fragment (engine message already uses friendly names when available).
    private func deviceContextLine(_ deviceId: String?) -> String? {
        guard let raw = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "All devices"
        }
        if raw.hasPrefix("ip:") {
            let ip = String(raw.dropFirst(3))
            return ip.isEmpty ? nil : "Device \(ip)"
        }
        return "Device \(raw)"
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "dns_burst": return "High DNS activity"
        case "dns_many_domains": return "Many domains"
        case "dns_repeat_block": return "Blocked retries"
        case "dns_global_spike": return "Network-wide spike"
        default:
            return category
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    private func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical", "alert", "error": return Theme.blocked
        case "warning", "warn": return Theme.warning
        case "info", "informational": return Theme.infoMuted
        default: return Theme.accent
        }
    }

    private func alertDetailLine(_ alert: AlertDTO) -> String? {
        guard
            let raw = alert.detailsJson?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else {
            return nil
        }

        guard let profile = trafficProfileLabel(object["traffic_profile"] as? String) else {
            return nil
        }

        let families = (object["common_families"] as? [String])?
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if let families, !families.isEmpty {
            return "\(profile) · Common families: \(families)"
        }
        return profile
    }

    private func trafficProfileLabel(_ profile: String?) -> String? {
        switch profile {
        case "mostly_common": return "Mostly common service traffic"
        case "mostly_unknown": return "Mostly unknown-domain activity"
        case "mixed": return "Mixed common and unknown traffic"
        default: return nil
        }
    }
}
