import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EngineService: ObservableObject {
    private let client: EngineAPIClient

    @Published private(set) var lastHealth: HealthResponse?
    @Published private(set) var lastStats: StatsPayload?
    @Published private(set) var queries: [DnsQueryItem] = []
    @Published private(set) var devices: [DeviceDTO] = []
    @Published private(set) var alerts: [AlertDTO] = []
    @Published private(set) var settings: SettingsPayload?
    @Published private(set) var lastInsights: InsightsDailyDTO?
    @Published private(set) var insightsFetchError: String?

    /// Set when `GET /health` fails after an attempt (engine unreachable).
    @Published private(set) var healthFetchError: String?
    /// Set when `GET /stats` fails.
    @Published private(set) var statsFetchError: String?
    /// Set when `GET /queries` fails.
    @Published private(set) var queriesFetchError: String?
    /// Set when `GET /alerts` fails (kept separate from `lastOperationError` for mutations).
    @Published private(set) var alertsFetchError: String?

    /// Bumps when REST `queries` or live WebSocket rows change — drives stable Queries table updates.
    @Published private(set) var queriesDisplayRevision: UInt = 0

    @Published private(set) var isRefreshingHealth = false
    @Published private(set) var isRefreshingStats = false
    @Published private(set) var isRefreshingQueries = false
    @Published private(set) var isRefreshingDashboard = false
    @Published private(set) var isRefreshingInsights = false

    /// Live DNS rows from WebSocket (prepended to REST `queries` in the Queries screen).
    @Published private(set) var liveWsQueries: [DnsQueryItem] = []
    /// Mirrors the last `device_id` used for `GET /queries` so block/allow refreshes keep the same scope.
    private var lastQueriesDeviceId: String?
    /// Twelve five-second buckets over the last minute (for Dashboard sparkline).
    @Published private(set) var trafficSparklineBuckets: [Int] = Array(repeating: 0, count: 12)

    /// Recent DNS cache hit-rate samples (%), one per successful stats refresh (Dashboard cadence).
    @Published private(set) var dnsCacheHitRateHistory: [Double] = []

    private var dnsWebSocketTask: URLSessionWebSocketTask?
    private var dnsSocketSupervisorTask: Task<Void, Never>?
    private var sparklineTimerTask: Task<Void, Never>?
    private var sparklineEventTimes: [Date] = []
    private var dnsWebSocketRetainCount = 0
    private let dnsCacheHitRateHistoryMax = 12

    /// Connection state of the live `GET /ws` feed (drives the live/disconnected indicator).
    enum LiveFeedStatus: Equatable {
        case idle
        case connecting
        case live
        case reconnecting
    }

    @Published private(set) var liveFeedStatus: LiveFeedStatus = .idle

    @Published private(set) var hasCompletedInitialHealthFetch = false
    @Published private(set) var hasCompletedInitialStatsFetch = false
    @Published private(set) var hasCompletedInitialQueriesFetch = false
    @Published private(set) var hasCompletedInitialDevicesFetch = false
    @Published private(set) var hasCompletedInitialAlertsFetch = false

    /// Last mutation / auxiliary endpoint error (settings, devices, alerts).
    @Published private(set) var lastOperationError: String?

    /// Shown after a successful POST `/block` or `/allow` (Queries + Settings).
    @Published private(set) var lastDomainRuleSuccess: String?

    /// Shown after a successful device rename, DNS policy change, or tags save.
    @Published private(set) var lastDeviceControlSuccess: String?

    /// True while PATCH `/devices/:id` is in flight (rename, policy, or tags).
    @Published private(set) var isApplyingDeviceChange = false

    /// True while POST `/settings`, `/reload`, or DNS pause/resume is in flight.
    @Published private(set) var isSavingSettings = false

    /// True while POST `/block` or `/allow` is in flight.
    @Published private(set) var isApplyingDomainRule = false

    @Published private(set) var timeOverrides: [TimeOverrideDTO] = []
    @Published private(set) var timeOverridesFetchError: String?

    private var alertsPollTask: Task<Void, Never>?

    init(client: EngineAPIClient = EngineAPIClient()) {
        self.client = client
        startAlertsBackgroundPoll()
    }

    /// Polls `/alerts` once a minute so notifications fire even when the
    /// Alerts screen is closed. Skips work while notifications are disabled.
    private func startAlertsBackgroundPoll() {
        guard AlertNotifier.isSupported else { return }
        alertsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                if AlertNotifier.isEnabled {
                    await self?.refreshAlerts()
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    /// True after first health attempt and engine appears unreachable.
    var isEngineUnreachable: Bool {
        hasCompletedInitialHealthFetch && lastHealth == nil && healthFetchError != nil
    }

    func refreshHealth() async {
        isRefreshingHealth = true
        defer {
            isRefreshingHealth = false
            hasCompletedInitialHealthFetch = true
        }
        do {
            lastHealth = try await client.health()
            healthFetchError = nil
        } catch {
            lastHealth = nil
            healthFetchError = error.localizedDescription
        }
    }

    func refreshStats() async {
        isRefreshingStats = true
        defer {
            isRefreshingStats = false
            hasCompletedInitialStatsFetch = true
        }
        do {
            let s = try await client.stats()
            lastStats = s
            statsFetchError = nil
            recordDnsCacheHitRateSample(stats: s)
        } catch {
            lastStats = nil
            statsFetchError = error.localizedDescription
        }
    }

    private func recordDnsCacheHitRateSample(stats: StatsPayload) {
        guard let h = stats.dnsCacheHits, let m = stats.dnsCacheMisses else { return }
        let total = h + m
        guard total > 0 else { return }
        let pct = Double(h) / Double(total) * 100.0
        var next = dnsCacheHitRateHistory
        next.append(pct)
        if next.count > dnsCacheHitRateHistoryMax {
            next.removeFirst(next.count - dnsCacheHitRateHistoryMax)
        }
        dnsCacheHitRateHistory = next
    }

    func refreshQueries(limit: Int = 100, deviceId: String? = nil) async {
        lastQueriesDeviceId = deviceId
        isRefreshingQueries = true
        defer {
            isRefreshingQueries = false
            hasCompletedInitialQueriesFetch = true
        }
        do {
            queries = try await client.queries(limit: limit, deviceId: deviceId)
            queriesFetchError = nil
            bumpQueriesDisplayRevision()
        } catch {
            queriesFetchError = error.localizedDescription
        }
    }

    private func bumpQueriesDisplayRevision() {
        queriesDisplayRevision &+= 1
    }

    /// Queries for UI: WebSocket-first (deduped by id), then REST sample. Optionally restrict to one `device_id`.
    func mergedDisplayQueries(deviceFilter: String? = nil) -> [DnsQueryItem] {
        var seen = Set<Int64>()
        var out: [DnsQueryItem] = []
        for q in liveWsQueries + queries {
            if let f = deviceFilter, !f.isEmpty, q.deviceId != f { continue }
            if seen.insert(q.id).inserted {
                out.append(q)
            }
        }
        return out
    }

    /// Share one WebSocket across screens (Dashboard sparkline + Queries list).
    func retainDnsEventsWebSocket() {
        dnsWebSocketRetainCount += 1
        if dnsWebSocketRetainCount == 1 {
            startQueriesWebSocketIfNeeded()
            startSparklineTimer()
        }
    }

    func releaseDnsEventsWebSocket() {
        dnsWebSocketRetainCount = max(0, dnsWebSocketRetainCount - 1)
        if dnsWebSocketRetainCount == 0 {
            stopQueriesWebSocket()
            stopSparklineTimer()
        }
    }

    private func startQueriesWebSocketIfNeeded() {
        guard dnsSocketSupervisorTask == nil else { return }
        dnsSocketSupervisorTask = Task { [weak self] in
            await self?.runDnsSocketSupervisor()
        }
    }

    private func stopQueriesWebSocket() {
        dnsSocketSupervisorTask?.cancel()
        dnsSocketSupervisorTask = nil
        dnsWebSocketTask?.cancel(with: .goingAway, reason: nil)
        dnsWebSocketTask = nil
        liveFeedStatus = .idle
    }

    /// Owns the socket lifecycle: connect, drain, and reconnect with exponential
    /// backoff (1s → 30s) until released. Backoff resets once a frame arrives.
    private func runDnsSocketSupervisor() async {
        var backoffSeconds = 1.0
        while !Task.isCancelled {
            guard let url = client.websocketURL else { return }
            liveFeedStatus = .connecting
            let task = URLSession.shared.webSocketTask(with: url)
            dnsWebSocketTask = task
            task.resume()
            let receivedAnyMessage = await runDnsSocketReceiveLoop(task)
            task.cancel(with: .goingAway, reason: nil)
            dnsWebSocketTask = nil
            if Task.isCancelled { break }
            if receivedAnyMessage {
                backoffSeconds = 1.0
            }
            liveFeedStatus = .reconnecting
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            backoffSeconds = min(backoffSeconds * 2, 30)
        }
    }

    private func runDnsSocketReceiveLoop(_ task: URLSessionWebSocketTask) async -> Bool {
        var receivedAnyMessage = false
        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                if Task.isCancelled { break }
                if !receivedAnyMessage {
                    receivedAnyMessage = true
                    liveFeedStatus = .live
                }
                let text: String?
                switch msg {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: text = nil
                }
                guard let text, let data = text.data(using: .utf8),
                      let ev = try? JSONDecoder().decode(WsDnsEvent.self, from: data)
                else { continue }

                let dev = ev.deviceId ?? "ip:\(ev.payload.clientIp)"
                let row = DnsQueryItem(
                    liveTimestamp: ev.timestamp,
                    deviceId: dev,
                    domain: ev.payload.domain,
                    queryType: ev.payload.queryType ?? "—",
                    action: ev.payload.action
                )
                liveWsQueries.insert(row, at: 0)
                if liveWsQueries.count > 150 {
                    liveWsQueries.removeLast()
                }
                bumpQueriesDisplayRevision()
                recordSparklineEvent()
            } catch {
                break
            }
        }
        return receivedAnyMessage
    }

    /// Keeps the sparkline draining to zero during idle periods; without it the
    /// buckets only recompute when an event arrives.
    private func startSparklineTimer() {
        guard sparklineTimerTask == nil else { return }
        sparklineTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.recomputeSparklineBuckets()
            }
        }
    }

    private func stopSparklineTimer() {
        sparklineTimerTask?.cancel()
        sparklineTimerTask = nil
    }

    private func recordSparklineEvent() {
        sparklineEventTimes.append(Date())
        recomputeSparklineBuckets()
    }

    private func recomputeSparklineBuckets() {
        let now = Date()
        sparklineEventTimes.removeAll { now.timeIntervalSince($0) > 60 }
        let buckets: [Int] = (0 ..< 12).map { i in
            let older = Double(11 - i) * 5.0
            let newer = Double(12 - i) * 5.0
            return sparklineEventTimes.filter { t in
                let a = now.timeIntervalSince(t)
                return a >= older && a < newer
            }.count
        }
        trafficSparklineBuckets = buckets
    }

    func refreshDevices() async {
        lastOperationError = nil
        defer { hasCompletedInitialDevicesFetch = true }
        do {
            devices = try await client.devices()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    /// Latest device row + query stats (`GET /devices/:id`). Returns nil on failure (`lastOperationError` set).
    func fetchDevice(id: String) async -> DeviceDTO? {
        lastOperationError = nil
        do {
            return try await client.device(id: id)
        } catch {
            lastOperationError = error.localizedDescription
            return nil
        }
    }

    func refreshAlerts() async {
        defer { hasCompletedInitialAlertsFetch = true }
        do {
            alerts = try await client.alerts()
            alertsFetchError = nil
            AlertNotifier.shared.processRefreshedAlerts(alerts)
        } catch {
            alertsFetchError = error.localizedDescription
        }
    }

    func refreshTimeOverrides() async {
        do {
            timeOverrides = try await client.timeOverrides()
            timeOverridesFetchError = nil
        } catch {
            timeOverridesFetchError = error.localizedDescription
        }
    }

    /// Adds a scheduled DNS-policy window and refreshes the list.
    func addTimeOverride(scopeDeviceId: String?, startMin: Int, endMin: Int, dnsPolicy: String) async {
        lastOperationError = nil
        do {
            try await client.postTimeOverride(
                scopeDeviceId: scopeDeviceId,
                startMin: startMin,
                endMin: endMin,
                dnsPolicy: dnsPolicy
            )
            await refreshTimeOverrides()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func deleteTimeOverride(id: Int64) async {
        lastOperationError = nil
        do {
            try await client.deleteTimeOverride(id: id)
            await refreshTimeOverrides()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func refreshSettings() async {
        lastOperationError = nil
        do {
            settings = try await client.settings()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    /// Health + stats + a small query sample for dashboard “last query” row.
    func refreshAllDashboardData() async {
        isRefreshingDashboard = true
        defer { isRefreshingDashboard = false }
        await refreshHealth()
        await refreshStats()
        await refreshQueries(limit: 5)
        await refreshInsights()
    }

    func refreshInsights() async {
        isRefreshingInsights = true
        defer { isRefreshingInsights = false }
        do {
            lastInsights = try await client.insightsDaily(hours: 24)
            insightsFetchError = nil
        } catch {
            lastInsights = nil
            insightsFetchError = error.localizedDescription
        }
    }

    /// Saves `queries/export.csv` via a save panel (G14).
    func exportQueriesCSVUsingSavePanel() {
        lastOperationError = nil
        Task {
            do {
                let data = try await client.exportQueriesCSV(hours: 24, limit: 10_000)
                await MainActor.run {
                    let p = NSSavePanel()
                    p.allowedContentTypes = [.commaSeparatedText]
                    p.nameFieldStringValue = "netsentrix_queries_export.csv"
                    guard p.runModal() == .OK, let url = p.url else { return }
                    do {
                        try data.write(to: url, options: .atomic)
                        self.lastDomainRuleSuccess = "Exported queries to \(url.lastPathComponent)"
                    } catch {
                        self.lastOperationError = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run { self.lastOperationError = error.localizedDescription }
            }
        }
    }

    func saveUpstream(_ upstream: String) async {
        await saveSettingsPatch(
            SettingsDnsPatch(
                upstream: upstream,
                blockPolicy: nil,
                protectionActivityWindowSecs: nil,
                blocklistPaths: nil,
                allowlistPaths: nil
            )
        )
    }

    func saveBlockPolicy(_ apiValue: String) async {
        await saveSettingsPatch(
            SettingsDnsPatch(
                upstream: nil,
                blockPolicy: apiValue,
                protectionActivityWindowSecs: nil,
                blocklistPaths: nil,
                allowlistPaths: nil
            )
        )
    }

    func saveProtectionActivityWindow(seconds: UInt64) async {
        await saveSettingsPatch(
            SettingsDnsPatch(
                upstream: nil,
                blockPolicy: nil,
                protectionActivityWindowSecs: seconds,
                blocklistPaths: nil,
                allowlistPaths: nil
            )
        )
    }

    /// Saves static block/allow list file paths (engine merges into the live filter).
    func saveBlocklistAllowlistPaths(blocklist: [String], allowlist: [String]) async {
        await saveSettingsPatch(
            SettingsDnsPatch(
                upstream: nil,
                blockPolicy: nil,
                protectionActivityWindowSecs: nil,
                blocklistPaths: blocklist,
                allowlistPaths: allowlist
            )
        )
    }

    /// Reload `config.toml` from disk (e.g. manual edits); refreshes in-memory settings + health.
    func reloadConfigFromDisk() async {
        lastOperationError = nil
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            try await client.postReload()
            settings = try await client.settings()
            await refreshHealth()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    /// While paused, engine answers **SERVFAIL** on UDP/TCP and does **not** forward to upstream.
    func pauseDnsAnswering() async {
        lastOperationError = nil
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            try await client.postDnsPause()
            await refreshHealth()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func resumeDnsAnswering() async {
        lastOperationError = nil
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            try await client.postDnsResume()
            await refreshHealth()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    private func saveSettingsPatch(_ patch: SettingsDnsPatch) async {
        lastOperationError = nil
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            settings = try await client.postSettings(dns: patch)
            await refreshHealth()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func renameDevice(id: String, name: String) async {
        lastOperationError = nil
        lastDeviceControlSuccess = nil
        isApplyingDeviceChange = true
        defer { isApplyingDeviceChange = false }
        do {
            try await client.patchDevice(id: id, name: name, dnsPolicy: nil, tags: nil)
            lastDeviceControlSuccess = "Device renamed."
            await refreshDevices()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    /// `dnsPolicy`: `normal`, `restricted`, `paused`, or `blocked` (engine canonical values).
    func setDeviceDnsPolicy(id: String, dnsPolicy: String) async {
        lastOperationError = nil
        lastDeviceControlSuccess = nil
        isApplyingDeviceChange = true
        defer { isApplyingDeviceChange = false }
        do {
            try await client.patchDevice(id: id, name: nil, dnsPolicy: dnsPolicy, tags: nil)
            lastDeviceControlSuccess = "Device DNS mode updated."
            await refreshDevices()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func setDeviceTags(id: String, tags: String) async {
        lastOperationError = nil
        lastDeviceControlSuccess = nil
        isApplyingDeviceChange = true
        defer { isApplyingDeviceChange = false }
        do {
            try await client.patchDevice(id: id, name: nil, dnsPolicy: nil, tags: tags)
            lastDeviceControlSuccess = "Tags saved."
            await refreshDevices()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func markDomainFeedback(pattern: String, verdict: String) async {
        lastOperationError = nil
        do {
            try await client.postDomainFeedback(pattern: pattern, verdict: verdict)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func clearDeviceControlSuccess() {
        lastDeviceControlSuccess = nil
    }

    func clearDomainRuleSuccess() {
        lastDomainRuleSuccess = nil
    }

    /// POST `/block` with normalized domain; engine reloads filter immediately.
    func blockDomain(_ raw: String) async {
        await applyDomainRule(raw: raw, allow: false)
    }

    /// POST `/allow` with normalized domain; allowlist wins over blocks for new lookups.
    func allowDomain(_ raw: String) async {
        await applyDomainRule(raw: raw, allow: true)
    }

    private func applyDomainRule(raw: String, allow: Bool) async {
        lastOperationError = nil
        lastDomainRuleSuccess = nil
        let p = DomainPattern.normalize(raw)
        guard !p.isEmpty else {
            lastOperationError = "Enter a domain name."
            return
        }
        isApplyingDomainRule = true
        defer { isApplyingDomainRule = false }
        do {
            if allow {
                try await client.postAllowDomain(pattern: p)
                lastDomainRuleSuccess = "Allowed «\(p)» — this name bypasses block rules for new lookups."
            } else {
                try await client.postBlockDomain(pattern: p)
                lastDomainRuleSuccess = "Blocked «\(p)» — new lookups will be filtered using this rule."
            }
            lastOperationError = nil
            await refreshQueries(limit: 100, deviceId: lastQueriesDeviceId)
        } catch {
            lastDomainRuleSuccess = nil
            lastOperationError = error.localizedDescription
        }
    }
}
