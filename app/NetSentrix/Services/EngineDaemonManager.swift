import Foundation
import ServiceManagement

/// Registers / unregisters the embedded engine LaunchDaemon via SMAppService
/// (macOS 13+). Only available in bundles built with `make bundle-full`, which
/// place the daemon plist at Contents/Library/LaunchDaemons/ and the engine
/// binary at Contents/Resources/bin/.
@MainActor
final class EngineDaemonManager: ObservableObject {
    static let plistName = "com.netsentrix.engine.plist"

    @Published private(set) var status: SMAppService.Status = .notFound
    @Published private(set) var lastError: String?

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    /// True when this build carries the embedded daemon plist. False under
    /// `swift run` or a `make bundle` (app-only) build.
    var isAvailable: Bool {
        let plist = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(Self.plistName)
        return FileManager.default.fileExists(atPath: plist.path)
    }

    func refreshStatus() {
        guard isAvailable else {
            status = .notFound
            return
        }
        status = service.status
    }

    /// Registration prompts for approval in System Settings → Login Items the
    /// first time; the daemon starts once approved.
    func register() {
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func unregister() {
        lastError = nil
        do {
            try service.unregister()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var statusDescription: String {
        switch status {
        case .enabled: return "Installed and enabled."
        case .requiresApproval: return "Waiting for approval in System Settings → Login Items."
        case .notRegistered: return "Not installed."
        case .notFound: return isAvailable ? "Not installed." : "This build has no embedded engine."
        @unknown default: return "Unknown status."
        }
    }
}
