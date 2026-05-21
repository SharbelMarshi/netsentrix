import Foundation

// MARK: - Product-facing status (derived from engine health + stats)
//
// When `GET /health` includes `protection`, that object is the source of truth for the
// protection tier; the app only falls back to legacy heuristics for older engines.

enum ProductEngineState: String {
    case starting = "Starting"
    case running = "Running"
    case stopped = "Stopped"
    case error = "Error"
}

enum ProductProtectionState: String {
    case active = "Active"
    case partial = "Partial"
    case notActive = "Not Active"
}

enum ProductTrafficState: String {
    case receiving = "Receiving Traffic"
    case noneYet = "No Traffic Yet"
}

enum ProductSetupState: String {
    case complete = "Complete"
    case incomplete = "Incomplete"
    case needsAttention = "Needs Attention"
}

/// LAN-focused proof fields from engine `protection` (non-loopback clients only).
struct ProtectionVerification: Sendable {
    let windowSecs: UInt64
    let distinctLanClients: Int64
    let lanQueriesInWindow: Int64
    let lastLanQueryMs: Int64?
    let protectionState: String
    let lanCapable: Bool
}

struct ProductStatusSnapshot: Sendable {
    let engine: ProductEngineState
    let protection: ProductProtectionState
    let traffic: ProductTrafficState
    let setup: ProductSetupState

    let protectionReason: String
    let protectionNextStep: String?

    let setupReason: String
    let setupNextStep: String?

    /// User-facing engine line (e.g. "Running").
    let engineTitle: String
    /// Plain-language DNS / listener summary for primary UI.
    let dnsSummaryPrimary: String
    /// Present when `GET /health` includes `protection` — use for Setup / Dashboard proof lines.
    let verification: ProtectionVerification?
}

enum ProductStatusAdapter {
    static func snapshot(
        health: HealthResponse?,
        stats: StatsPayload?,
        lastQuery: DnsQueryItem?,
        healthFetchFailed: Bool,
        healthErrorMessage: String?
    ) -> ProductStatusSnapshot {
        let engine = resolveEngine(health: health, healthFetchFailed: healthFetchFailed)
        let totalQ = stats.map(\.totalQueries) ?? 0
        let dnsPaused = health?.dnsPaused == true
        let dnsUdpOk = health.map { $0.dnsUdpBound ?? $0.dnsBound } ?? false
        let dnsBound = dnsUdpOk
        let running = health.map { $0.engineStatus.lowercased() == "running" } ?? false
        let starting = health.map { $0.engineStatus.lowercased() == "starting" } ?? false
        let stopped = health.map { $0.engineStatus.lowercased() == "stopped" } ?? false
        let dnsErr = health?.dnsLastError?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tcpErr = health?.dnsTcpLastError?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUdpDnsError = !(dnsErr ?? "").isEmpty
        let hasExplicitTcpFailure = health?.dnsTcpBound == false && dnsUdpOk

        let (protection, pReason, pNext) = resolveProtection(
            health: health,
            engine: engine,
            dnsBound: dnsBound,
            dnsPaused: dnsPaused,
            running: running,
            starting: starting,
            stopped: stopped,
            totalQueries: totalQ,
            healthFetchFailed: healthFetchFailed,
            hasUdpDnsError: hasUdpDnsError,
            hasExplicitTcpFailure: hasExplicitTcpFailure,
            tcpErrorDetail: tcpErr
        )

        let traffic: ProductTrafficState = resolveTraffic(
            health: health,
            protection: health?.protection,
            totalQueries: totalQ
        )

        let verification: ProtectionVerification? = health?.protection.map { p in
            ProtectionVerification(
                windowSecs: p.windowSeconds,
                distinctLanClients: p.distinctClientsInWindow,
                lanQueriesInWindow: p.lanQueryCountInWindow ?? 0,
                lastLanQueryMs: p.lastQueryMs,
                protectionState: p.state.lowercased(),
                lanCapable: p.lanCapable
            )
        }

        let (setup, sReason, sNext) = resolveSetup(
            health: health,
            healthFetchFailed: healthFetchFailed,
            dnsBound: dnsBound,
            dnsPaused: dnsPaused,
            running: running,
            stopped: stopped,
            totalQueries: totalQ,
            hasUdpDnsError: hasUdpDnsError,
            hasExplicitTcpFailure: hasExplicitTcpFailure,
            tcpErrorDetail: tcpErr,
            healthErrorMessage: healthErrorMessage,
            protection: health?.protection
        )

        let engineTitle = engine.rawValue
        let dnsSummaryPrimary = dnsSummary(
            health: health,
            dnsBound: dnsBound,
            dnsPaused: dnsPaused,
            running: running,
            healthFetchFailed: healthFetchFailed
        )

        return ProductStatusSnapshot(
            engine: engine,
            protection: protection,
            traffic: traffic,
            setup: setup,
            protectionReason: pReason,
            protectionNextStep: pNext,
            setupReason: sReason,
            setupNextStep: sNext,
            engineTitle: engineTitle,
            dnsSummaryPrimary: dnsSummaryPrimary,
            verification: verification
        )
    }

    private static func resolveEngine(health: HealthResponse?, healthFetchFailed: Bool) -> ProductEngineState {
        if healthFetchFailed { return .error }
        guard let h = health else { return .starting }
        switch h.engineStatus.lowercased() {
        case "starting": return .starting
        case "running": return .running
        case "stopped": return .stopped
        case "error": return .error
        default: return .running
        }
    }

    private static func resolveTraffic(
        health: HealthResponse?,
        protection: ProtectionSummaryDTO?,
        totalQueries: Int64
    ) -> ProductTrafficState {
        if let p = protection, p.state.lowercased() == "active" {
            return .receiving
        }
        if let p = protection, p.distinctClientsInWindow > 0 || (p.lanQueryCountInWindow ?? 0) > 0 {
            return .receiving
        }
        if health?.recentClientActivity == true { return .receiving }
        if totalQueries > 0 { return .receiving }
        return .noneYet
    }

    private static func reasonLine(for code: String) -> String {
        switch code {
        case "engine_starting": return "The engine is still starting."
        case "engine_stopped": return "The engine is stopped."
        case "engine_error": return "The engine reported an error (for example DNS could not bind)."
        case "dns_not_bound": return "DNS is not listening, so clients cannot use this resolver."
        case "dns_paused": return "DNS answering is paused; clients receive errors instead of filtered DNS."
        case "listen_loopback_only": return "DNS is bound to loopback only — network devices cannot reach it."
        case "no_recent_lan_queries":
            return "No recent DNS from LAN clients (non-loopback) in the verification window — DHCP DNS may not point here yet, or leases haven’t renewed."
        case "db_unavailable": return "Could not read verification data from the engine database."
        default: return "Code: \(code)"
        }
    }

    private static func protectionCopy(from p: ProtectionSummaryDTO, health: HealthResponse?) -> (String, String?) {
        let lines = p.reasons.map { reasonLine(for: $0) }
        let body = lines.isEmpty ? "See engine status for details." : lines.joined(separator: " ")
        var next: String?
        if p.reasons.contains("listen_loopback_only") {
            next = "Set dns.listen_addr to your LAN interface or 0.0.0.0:53 (see engine config), then reload."
        } else if p.reasons.contains("dns_not_bound") {
            next = "Fix the DNS bind error (port, permissions), then check health again."
        } else if p.reasons.contains("no_recent_lan_queries") {
            next =
                "Point your router’s DHCP DNS at this Mac, renew leases, and wait for queries (see Setup). Devices using DoH, IPv6 DNS outside DHCP, VPNs, or manual resolvers may not appear here — that is visibility, not silent protection."
        } else if p.reasons.contains("dns_paused") {
            next = "Call POST /dns/resume on the engine API to resume normal DNS."
        } else if p.state.lowercased() == "active" {
            next =
                "Applies to clients using this Mac as DNS (plain DNS on the LAN). Not every device is guaranteed — DoH, DoT, or manual DNS can bypass this resolver."
        }
        if let msg = health?.dnsLastError, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           p.reasons.contains("dns_not_bound") || p.reasons.contains("engine_error") {
            next = (next.map { $0 + "\n" } ?? "") + "Details: \(msg)"
        }
        return (body, next)
    }

    private static func resolveProtection(
        health: HealthResponse?,
        engine: ProductEngineState,
        dnsBound: Bool,
        dnsPaused: Bool,
        running: Bool,
        starting: Bool,
        stopped: Bool,
        totalQueries: Int64,
        healthFetchFailed: Bool,
        hasUdpDnsError: Bool,
        hasExplicitTcpFailure: Bool,
        tcpErrorDetail: String?
    ) -> (ProductProtectionState, String, String?) {
        if healthFetchFailed {
            return (.notActive, "Can’t tell — the NetSentrix engine isn’t reachable.", "Start NetSentrix Core on this Mac and try again.")
        }
        if let p = health?.protection {
            let ui: ProductProtectionState
            switch p.state.lowercased() {
            case "active": ui = .active
            case "partial": ui = .partial
            default: ui = .notActive
            }
            let (reason, next) = protectionCopy(from: p, health: health)
            return (ui, reason, next)
        }
        if dnsPaused {
            return (.notActive, "DNS is paused — clients receive errors instead of filtered DNS.", "Turn off pause in engine controls (when available) or restart the engine with DNS answering enabled.")
        }
        if hasUdpDnsError, let msg = health?.dnsLastError, !msg.isEmpty {
            return (.notActive, "DNS couldn’t bind or encountered an error.", "Check the DNS listen address in engine config and that the port is free. Details: \(msg)")
        }
        if hasExplicitTcpFailure {
            let detail = (tcpErrorDetail ?? "").isEmpty ? "See engine logs for TCP bind details." : tcpErrorDetail!
            return (.notActive, "UDP DNS is up, but the TCP listener failed — some clients may not get large answers.", detail)
        }
        if stopped || engine == .stopped {
            return (.notActive, "The engine is stopped — your network isn’t using NetSentrix for DNS.", "Start the NetSentrix engine.")
        }
        if starting || engine == .starting {
            return (.partial, "The engine is still starting.", "Wait a few seconds, then refresh.")
        }
        if !dnsBound {
            return (.notActive, "NetSentrix is not protecting your network yet — DNS isn’t listening on the configured interface.", "Fix DNS bind (permissions/port) in engine config, then finish router setup.")
        }
        if running && dnsBound && health?.recentClientActivity == true {
            return (
                .active,
                "Recent LAN DNS through NetSentrix within the engine window (see Setup for counts).",
                "Applies to clients using this resolver — not proof that the entire network is filtered."
            )
        }
        if running && dnsBound && totalQueries > 0 {
            return (
                .partial,
                "DNS is answering and queries are logged; LAN-specific proof may be missing or outside the window.",
                "Prefer the engine protection line when available; point router DHCP DNS here and renew leases."
            )
        }
        if running && dnsBound && totalQueries == 0 {
            return (.partial, "The engine is ready, but no DNS queries are logged yet.", "Configure your router’s DHCP DNS to this Mac’s IP (Setup), renew leases, then wait for activity.")
        }
        return (.notActive, "Protection isn’t active yet.", "Open Setup to finish activating protection.")
    }

    private static func resolveSetup(
        health: HealthResponse?,
        healthFetchFailed: Bool,
        dnsBound: Bool,
        dnsPaused: Bool,
        running: Bool,
        stopped: Bool,
        totalQueries: Int64,
        hasUdpDnsError: Bool,
        hasExplicitTcpFailure: Bool,
        tcpErrorDetail: String?,
        healthErrorMessage: String?,
        protection: ProtectionSummaryDTO?
    ) -> (ProductSetupState, String, String?) {
        if healthFetchFailed {
            let hint = healthErrorMessage.map { " (\($0))" } ?? ""
            return (.needsAttention, "Can’t reach the engine.\(hint)", "Start NetSentrix Core and confirm the API is listening on this machine.")
        }
        if let p = protection, p.state.lowercased() == "active" {
            return (
                .complete,
                "Engine reports Active: recent LAN DNS (non-loopback) in your verification window, with DNS listening on a LAN-reachable address.",
                "This is evidence for clients using this resolver — not a guarantee for every device. DoH, DoT, or static DNS can still bypass NetSentrix."
            )
        }
        if dnsPaused {
            return (.needsAttention, "DNS answering is paused.", "Resume normal DNS operation before validating setup.")
        }
        if hasUdpDnsError {
            return (.needsAttention, "DNS service needs attention before clients can use NetSentrix.", "Resolve the DNS bind error shown in Engine details, then try again.")
        }
        if hasExplicitTcpFailure {
            let hint = (tcpErrorDetail ?? "").isEmpty ? "Check engine logs and port conflicts." : tcpErrorDetail!
            return (.needsAttention, "TCP DNS listener is not running; UDP works but large responses may fail.", hint)
        }
        if stopped {
            return (.needsAttention, "The engine is stopped.", "Start the engine, then continue router DNS setup.")
        }
        if let p = protection, p.state.lowercased() == "partial" {
            return (
                .incomplete,
                "Engine reports Partial — LAN-reachable DNS without enough recent LAN client evidence in the window for Active.",
                "Use Setup verification (distinct LAN clients, lookups, last LAN DNS). Finish router DHCP DNS if needed."
            )
        }
        if dnsBound, health?.recentClientActivity == true {
            return (
                .complete,
                "Recent LAN client DNS in the engine’s verification window.",
                "If you expect more devices, confirm router DHCP DNS and lease renewal. Localhost-only tests do not count as LAN proof."
            )
        }
        if dnsBound && totalQueries > 0 {
            return (
                .incomplete,
                "DNS is up and the log has queries, but there is no recent LAN client activity in the verification window (or traffic may be local-only).",
                "Set router DHCP DNS to this Mac, renew leases, and wait — see Setup verification for distinct LAN clients."
            )
        }
        if dnsBound && totalQueries == 0 {
            return (.incomplete, "The engine is listening, but no queries have been logged.", "Point DHCP DNS at this host and reconnect devices (see Setup steps).")
        }
        return (.incomplete, "DNS isn’t listening yet — protection can’t activate.", "Fix engine DNS bind, then set your router to this Mac’s IP.")
    }

    private static func dnsSummary(
        health: HealthResponse?,
        dnsBound: Bool,
        dnsPaused: Bool,
        running: Bool,
        healthFetchFailed: Bool
    ) -> String {
        if healthFetchFailed { return "Unknown — engine unreachable." }
        if health?.engineStatus.lowercased() == "error" {
            return "Engine error — check DNS bind and engine logs."
        }
        if dnsPaused { return "Paused — not accepting DNS." }
        if !running { return "Engine not running — DNS inactive." }
        if dnsBound, let listen = health?.dnsListen {
            if health?.dnsTcpBound == false {
                return "NetSentrix is accepting DNS on \(listen) (UDP up; TCP listener failed — large answers may not work for some clients)."
            }
            return "NetSentrix is accepting DNS on \(listen)."
        }
        if let listen = health?.dnsListen {
            return "DNS is not listening yet (configured: \(listen))."
        }
        return "DNS status unknown."
    }

    static func formattedRelativeTime(epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func formattedAbsoluteTime(epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    static func blockPolicyDescription(_ raw: String) -> String {
        switch raw.lowercased() {
        case "a_zero":
            return "Returns 0.0.0.0 (and :: for AAAA) — fast, silent blocking."
        case "nx_domain":
            return "Returns NXDOMAIN — more standards-like blocked response."
        default:
            return raw
        }
    }

    // MARK: - DNS cache & performance (stats)

    static func dnsCacheHitRatePercent(hits: UInt64?, misses: UInt64?) -> Double? {
        guard let h = hits, let m = misses else { return nil }
        let t = h + m
        guard t > 0 else { return nil }
        return Double(h) / Double(t) * 100.0
    }

    static func dnsCacheLookupsTotal(hits: UInt64?, misses: UInt64?) -> UInt64 {
        guard let h = hits, let m = misses else { return 0 }
        return h + m
    }

    /// Short headline for hit rate + qualitative label.
    static func dnsCacheHeadline(hitRatePercent: Double?, lookupsTotal: UInt64) -> String {
        guard lookupsTotal > 0, let p = hitRatePercent else {
            return "No cache lookups recorded yet"
        }
        if lookupsTotal < 15 {
            return String(format: "%.0f%% hit rate (early sample)", min(100, max(0, p)))
        }
        if p >= 70 {
            return String(format: "%.0f%% hit rate — high cache efficiency", p)
        }
        if p >= 35 {
            return String(format: "%.0f%% hit rate — moderate cache use", p)
        }
        return String(format: "%.0f%% hit rate — low cache usage", p)
    }

    static func dnsCacheExplanation(lookupsTotal: UInt64) -> String {
        if lookupsTotal == 0 {
            return "Counters reset when the engine starts. Hit rate shows how often repeated questions are answered from the in-memory cache instead of upstream."
        }
        return "Higher hit rates mean less upstream work for repeat names. Misses are normal for new or rarely seen domains."
    }

    /// Human line for DB-backed average latency, or nil when no samples (do not invent a number).
    static func dnsLatencyExplanation(avgMs: Double?, sampleCount: Int64) -> String? {
        guard sampleCount > 0, let avg = avgMs, avg >= 0 else { return nil }
        let r = (avg * 10).rounded() / 10
        return String(
            format: "%.1f ms average from %lld logged upstream answers (timing is not stored for every path; cache hits are often unmeasured here).",
            r,
            sampleCount
        )
    }
}
