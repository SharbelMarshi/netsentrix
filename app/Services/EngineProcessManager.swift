import AppKit
import Foundation

/// Runs the engine as a supervised child process so opening the app brings the
/// whole product up. The child runs unprivileged with default paths, which put
/// its token exactly where `APITokenLoader` already looks
/// (`~/Library/Application Support/NetSentrix/`). LAN service on :53 still goes
/// through the root LaunchDaemon (Settings → Engine process).
@MainActor
final class EngineProcessManager: ObservableObject {
    static let autoStartDefaultsKey = "engineAutoStartEnabled"

    enum State: Equatable {
        case idle
        case starting
        case running
        /// Engine reachable but not started by us (LaunchDaemon or manual run).
        case external
        case stopped
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?
    private var restartAttempts = 0
    private var stoppingIntentionally = false
    private var didRunAutostart = false
    private let client = EngineAPIClient()
    private let maxRestartAttempts = 3

    static var isAutoStartEnabled: Bool {
        UserDefaults.standard.object(forKey: autoStartDefaultsKey) as? Bool ?? true
    }

    init() {
        // launchd does not reap our children — kill the engine when the app quits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.stop()
            }
        }
    }

    /// Called once from the UI: if no engine answers, start the embedded one.
    func autostartIfNeeded(engineService: EngineService) async {
        guard !didRunAutostart else { return }
        didRunAutostart = true
        guard Self.isAutoStartEnabled else { return }
        if await engineIsReachable() {
            state = .external
            return
        }
        await start(engineService: engineService)
    }

    func start(engineService: EngineService? = nil) async {
        guard process == nil else { return }
        guard let binary = Self.locateEngineBinary() else {
            state = .failed(
                "No engine binary found. Use a bundled app (make bundle), or set NETSENTRIX_ENGINE_BIN for development."
            )
            return
        }
        let p = Process()
        p.executableURL = binary
        p.environment = ProcessInfo.processInfo.environment
        if let log = Self.openLogHandle() {
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in
                self?.handleTermination(status: status)
            }
        }
        do {
            try p.run()
        } catch {
            state = .failed("Could not launch engine: \(error.localizedDescription)")
            return
        }
        process = p
        state = .starting
        await waitUntilHealthy()
        if state == .running, let engineService {
            await engineService.refreshAllDashboardData()
        }
    }

    func stop() {
        guard let p = process else { return }
        stoppingIntentionally = true
        p.terminate()
    }

    /// Env override → app bundle → dev builds next to the repo's `app/` cwd.
    static func locateEngineBinary(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let override = env["NETSENTRIX_ENGINE_BIN"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/netsentrix-engine").path
        )
        let cwd = fileManager.currentDirectoryPath
        candidates.append(cwd + "/../engine/target/release/netsentrix-engine")
        candidates.append(cwd + "/../engine/target/debug/netsentrix-engine")
        for candidate in candidates {
            let path = ((candidate as NSString).expandingTildeInPath as NSString).standardizingPath
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static var logFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return dir
            .appendingPathComponent("NetSentrix", isDirectory: true)
            .appendingPathComponent("engine.log")
    }

    var statusDescription: String {
        switch state {
        case .idle: return "Not started."
        case .starting: return "Starting…"
        case .running: return "Running (started by this app)."
        case .external: return "Running (LaunchDaemon or started outside this app)."
        case .stopped: return "Stopped."
        case .failed(let message): return message
        }
    }

    private func engineIsReachable() async -> Bool {
        (try? await client.health()) != nil
    }

    private func waitUntilHealthy() async {
        for _ in 0 ..< 30 {
            if process == nil { return }
            if await engineIsReachable() {
                state = .running
                restartAttempts = 0
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        state = .failed("Engine process started but its API is not answering — see engine.log.")
    }

    private func handleTermination(status: Int32) {
        process = nil
        if stoppingIntentionally {
            stoppingIntentionally = false
            state = .stopped
            return
        }
        restartAttempts += 1
        if restartAttempts <= maxRestartAttempts {
            state = .starting
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await start()
            }
        } else {
            state = .failed("Engine exited repeatedly (last status \(status)) — see engine.log.")
        }
    }

    private static func openLogHandle() -> FileHandle? {
        guard let url = logFileURL else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        try? handle.seekToEnd()
        return handle
    }
}
