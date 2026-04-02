import Foundation

@MainActor
final class EngineService: ObservableObject {
    private let client: EngineAPIClient

    @Published private(set) var lastHealth: HealthResponse?
    @Published private(set) var lastStats: StatsPayload?
    @Published private(set) var queries: [DnsQueryItem] = []
    @Published private(set) var devices: [DeviceDTO] = []
    @Published private(set) var alerts: [AlertDTO] = []
    @Published private(set) var settings: SettingsPayload?

    /// Set when `GET /health` fails after an attempt (engine unreachable).
    @Published private(set) var healthFetchError: String?
    /// Set when `GET /stats` fails.
    @Published private(set) var statsFetchError: String?
    /// Set when `GET /queries` fails.
    @Published private(set) var queriesFetchError: String?

    @Published private(set) var isRefreshingHealth = false
    @Published private(set) var isRefreshingStats = false
    @Published private(set) var isRefreshingQueries = false
    @Published private(set) var isRefreshingDashboard = false

    /// Live DNS rows from WebSocket (prepended to REST `queries` in the Queries screen).
    @Published private(set) var liveWsQueries: [DnsQueryItem] = []
    /// Twelve five-second buckets over the last minute (for Dashboard sparkline).
    @Published private(set) var trafficSparklineBuckets: [Int] = Array(repeating: 0, count: 12)

    private var dnsWebSocketTask: URLSessionWebSocketTask?
    private var dnsSocketReceiveTask: Task<Void, Never>?
    private var sparklineEventTimes: [Date] = []
    private var dnsWebSocketRetainCount = 0

    @Published private(set) var hasCompletedInitialHealthFetch = false
    @Published private(set) var hasCompletedInitialStatsFetch = false
    @Published private(set) var hasCompletedInitialQueriesFetch = false
    @Published private(set) var hasCompletedInitialDevicesFetch = false
    @Published private(set) var hasCompletedInitialAlertsFetch = false

    /// Last mutation / auxiliary endpoint error (settings, devices, alerts).
    @Published private(set) var lastOperationError: String?

    init(client: EngineAPIClient = EngineAPIClient()) {
        self.client = client
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
            lastStats = try await client.stats()
            statsFetchError = nil
        } catch {
            lastStats = nil
            statsFetchError = error.localizedDescription
        }
    }

    func refreshQueries(limit: Int = 100) async {
        isRefreshingQueries = true
        defer {
            isRefreshingQueries = false
            hasCompletedInitialQueriesFetch = true
        }
        do {
            queries = try await client.queries(limit: limit)
            queriesFetchError = nil
        } catch {
            queriesFetchError = error.localizedDescription
        }
    }

    /// Queries for UI: WebSocket-first (deduped by id), then REST sample.
    func mergedDisplayQueries() -> [DnsQueryItem] {
        var seen = Set<Int64>()
        var out: [DnsQueryItem] = []
        for q in liveWsQueries + queries {
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
        }
    }

    func releaseDnsEventsWebSocket() {
        dnsWebSocketRetainCount = max(0, dnsWebSocketRetainCount - 1)
        if dnsWebSocketRetainCount == 0 {
            stopQueriesWebSocket()
        }
    }

    private func startQueriesWebSocketIfNeeded() {
        guard dnsWebSocketTask == nil else { return }
        guard let url = client.websocketURL else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        dnsWebSocketTask = task
        task.resume()
        dnsSocketReceiveTask = Task { [weak self] in
            await self?.runDnsSocketReceiveLoop(task)
        }
    }

    private func stopQueriesWebSocket() {
        dnsSocketReceiveTask?.cancel()
        dnsSocketReceiveTask = nil
        dnsWebSocketTask?.cancel(with: .goingAway, reason: nil)
        dnsWebSocketTask = nil
    }

    private func runDnsSocketReceiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                if Task.isCancelled { break }
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
                    queryType: "A",
                    action: ev.payload.action
                )
                await MainActor.run {
                    self.liveWsQueries.insert(row, at: 0)
                    if self.liveWsQueries.count > 150 {
                        self.liveWsQueries.removeLast()
                    }
                    self.recordSparklineEvent()
                }
            } catch {
                break
            }
        }
    }

    private func recordSparklineEvent() {
        let now = Date()
        sparklineEventTimes.append(now)
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

    func refreshAlerts() async {
        lastOperationError = nil
        defer { hasCompletedInitialAlertsFetch = true }
        do {
            alerts = try await client.alerts()
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
    }

    func saveUpstream(_ upstream: String) async {
        lastOperationError = nil
        do {
            try await client.patchUpstream(upstream)
            await refreshSettings()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func renameDevice(id: String, name: String) async {
        lastOperationError = nil
        do {
            try await client.patchDeviceName(id: id, name: name)
            await refreshDevices()
        } catch {
            lastOperationError = error.localizedDescription
        }
    }
}
