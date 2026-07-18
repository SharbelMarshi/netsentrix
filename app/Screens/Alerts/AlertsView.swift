import SwiftUI

struct AlertsView: View {
    @EnvironmentObject private var engine: EngineService
    @EnvironmentObject private var appModel: AppViewModel
    @State private var pendingBlockDomain: String?
    @State private var pendingAllowDomain: String?
    @State private var pendingBlockDeviceId: String?
    /// Avoid re-fetching alerts every time the view body re-evaluates (`.task`); manual Refresh still runs.
    @State private var didRunInitialAlertsFetch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if engine.hasCompletedInitialAlertsFetch, engine.alerts.isEmpty {
                if let err = engine.alertsFetchError {
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
                    let ctx = AlertActionContext(alert: a)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatAlertTime(a.timestampMs))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 8)
                            Text(a.severity.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(severityColor(a.severity))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(severityColor(a.severity).opacity(0.18))
                                )
                            if let pr = a.priority, !pr.isEmpty {
                                Text("P: \(pr.uppercased())")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.cardBackground.opacity(0.9)))
                            }
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
                        if let sig = intelSignalsLine(a) {
                            Text(sig)
                                .font(.caption2)
                                .foregroundStyle(Theme.infoMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let hint = ctx.actionHintLine {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 14) {
                            Button(ctx.viewQueriesTitle) {
                                appModel.openQueries(
                                    deviceFilter: ctx.filterDeviceId,
                                    highlightDomain: ctx.highlightDomain
                                )
                            }
                            .disabled(engine.isEngineUnreachable)

                            if let did = ctx.filterDeviceId {
                                Button("Block device…") {
                                    pendingBlockDeviceId = did
                                }
                                .disabled(engine.isEngineUnreachable)
                            }

                            if let dom = ctx.allowDomainCandidate {
                                Button("Allow domain…") {
                                    pendingAllowDomain = dom
                                }
                                .disabled(engine.isEngineUnreachable)
                            }

                            if let dom = ctx.blockDomainCandidate {
                                Button(ctx.blockButtonTitle) {
                                    pendingBlockDomain = dom
                                }
                                .disabled(engine.isEngineUnreachable)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.accent.opacity(0.95))
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(severityRowTint(a.severity))
                    )
                    .contextMenu {
                        if let dom = ctx.blockDomainCandidate ?? ctx.allowDomainCandidate {
                            Button("Mark «\(dom)» as locally safe (classifier hint)") {
                                Task { await engine.markDomainFeedback(pattern: dom, verdict: "safe") }
                            }
                            Button("Mark «\(dom)» as locally suspicious (classifier hint)") {
                                Task { await engine.markDomainFeedback(pattern: dom, verdict: "suspicious") }
                            }
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
                .scrollContentBackground(.hidden)
            } else if !engine.hasCompletedInitialAlertsFetch {
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
        .confirmationDialog(
            "Block this domain?",
            isPresented: Binding(
                get: { pendingBlockDomain != nil },
                set: { if !$0 { pendingBlockDomain = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                if let d = pendingBlockDomain {
                    Task { await engine.blockDomain(d) }
                }
                pendingBlockDomain = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBlockDomain = nil
            }
        } message: {
            Text(
                pendingBlockDomain.map {
                    "You are about to block «\($0)». New DNS lookups for that name will be filtered according to your block policy."
                } ?? ""
            )
        }
        .confirmationDialog(
            "Allow this domain?",
            isPresented: Binding(
                get: { pendingAllowDomain != nil },
                set: { if !$0 { pendingAllowDomain = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Allow") {
                if let d = pendingAllowDomain {
                    Task { await engine.allowDomain(d) }
                }
                pendingAllowDomain = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAllowDomain = nil
            }
        } message: {
            Text(
                pendingAllowDomain.map {
                    "Allow «\($0)» so new lookups can bypass block rules for that name (allowlist wins over blocks)."
                } ?? ""
            )
        }
        .confirmationDialog(
            "Block all DNS for this device?",
            isPresented: Binding(
                get: { pendingBlockDeviceId != nil },
                set: { if !$0 { pendingBlockDeviceId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block device", role: .destructive) {
                if let id = pendingBlockDeviceId {
                    Task { await engine.setDeviceDnsPolicy(id: id, dnsPolicy: "blocked") }
                }
                pendingBlockDeviceId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBlockDeviceId = nil
            }
        } message: {
            Text(
                "Queries from this client will get a blocked DNS response until you set the device back to Normal on the Devices screen. Allowlist entries still win for specific names."
            )
        }
        .onAppear {
            guard !didRunInitialAlertsFetch else { return }
            didRunInitialAlertsFetch = true
            Task { await engine.refreshAlerts() }
        }
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

    private func severityRowTint(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical", "alert", "error": return Theme.blocked.opacity(0.06)
        case "warning", "warn": return Theme.warning.opacity(0.07)
        case "info", "informational": return Theme.infoMuted.opacity(0.06)
        default: return Color.clear
        }
    }

    private func intelSignalsLine(_ alert: AlertDTO) -> String? {
        guard
            let raw = alert.detailsJson?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let arr = object["intel_signals"] as? [Any]
        else {
            return nil
        }
        let strings = arr.compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !strings.isEmpty else { return nil }
        return "Signals: " + strings.joined(separator: " · ")
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

// MARK: - Action context (details_json is best-effort; missing keys are safe)

private struct AlertActionContext {
    let filterDeviceId: String?
    let blockDomainCandidate: String?
    let allowDomainCandidate: String?
    let highlightDomain: String?
    let viewQueriesTitle: String
    let blockButtonTitle: String
    let actionHintLine: String?

    init(alert: AlertDTO) {
        let parsed = Self.parseDetails(alert.detailsJson)
        let col = alert.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let useCol = col.map { !$0.isEmpty } ?? false
        filterDeviceId = useCol ? col : (parsed.deviceId ?? parsed.relatedDeviceId)

        let domainField = parsed.domain.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let candidateBlock = parsed.candidateBlockDomain.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let firstUnknown = parsed.topUnknownDomains.compactMap { s -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }.first
        let trigger = parsed.triggerDomain.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }

        blockDomainCandidate = candidateBlock ?? domainField ?? firstUnknown

        if alert.category == "dns_repeat_block", let d = domainField {
            allowDomainCandidate = d
        } else {
            allowDomainCandidate = nil
        }

        if let d = blockDomainCandidate, !d.isEmpty {
            highlightDomain = d
        } else if let t = trigger {
            highlightDomain = t
        } else {
            let firstTop = parsed.topDomains.compactMap { s -> String? in
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }.first
            highlightDomain = firstTop
        }

        viewQueriesTitle = filterDeviceId != nil ? "View device activity" : "View queries"

        let suspiciousBlock = alert.category == "dns_repeat_block"
            || firstUnknown != nil
            || (parsed.trafficProfile == "mostly_unknown" || parsed.trafficProfile == "mixed")
        blockButtonTitle = suspiciousBlock ? "Block suspicious domain…" : "Block suggested domain…"

        if let dom = blockDomainCandidate, !dom.isEmpty {
            actionHintLine = "Quick action will affect: «\(dom)»"
        } else {
            actionHintLine = nil
        }
    }

    private static func parseDetails(_ json: String?) -> (
        deviceId: String?,
        relatedDeviceId: String?,
        topDomains: [String],
        topUnknownDomains: [String],
        domain: String?,
        candidateBlockDomain: String?,
        triggerDomain: String?,
        trafficProfile: String?
    ) {
        guard
            let raw = json,
            let data = raw.data(using: .utf8),
            let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil, [], [], nil, nil, nil, nil)
        }
        let deviceId = o["device_id"] as? String
        let relatedDeviceId = o["related_device_id"] as? String
        let topDomains = o["top_domains"] as? [String] ?? []
        let topUnknownDomains = o["top_unknown_domains"] as? [String] ?? []
        let domain = o["domain"] as? String
        let candidateBlockDomain = o["candidate_block_domain"] as? String
        let triggerDomain = o["trigger_domain"] as? String
        let trafficProfile = o["traffic_profile"] as? String
        return (
            deviceId,
            relatedDeviceId,
            topDomains,
            topUnknownDomains,
            domain,
            candidateBlockDomain,
            triggerDomain,
            trafficProfile
        )
    }
}
