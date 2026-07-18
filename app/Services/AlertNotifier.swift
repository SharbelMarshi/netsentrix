import Foundation
import UserNotifications

/// Posts macOS notifications for newly arrived engine alerts.
///
/// No-ops when running unbundled (`swift run` / `swift test`):
/// UNUserNotificationCenter requires a real app bundle and crashes without one.
@MainActor
final class AlertNotifier {
    static let shared = AlertNotifier()
    static let enabledDefaultsKey = "alertNotificationsEnabled"

    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    /// Highest alert id already seen; nil until the first refresh, which only
    /// records the baseline so a backlog never fires a notification storm.
    private var lastSeenAlertId: Int64?

    func requestAuthorization() {
        guard Self.isSupported else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func processRefreshedAlerts(_ alerts: [AlertDTO]) {
        guard Self.isSupported, Self.isEnabled else { return }
        let maxId = alerts.map(\.id).max()
        guard let baseline = lastSeenAlertId else {
            lastSeenAlertId = maxId ?? 0
            return
        }
        let fresh = alerts.filter { $0.id > baseline }.sorted { $0.id < $1.id }
        guard !fresh.isEmpty else { return }
        lastSeenAlertId = maxId ?? baseline
        // Cap per refresh so a burst stays readable.
        for alert in fresh.suffix(5) {
            post(alert)
        }
    }

    private func post(_ alert: AlertDTO) {
        let content = UNMutableNotificationContent()
        content.title = "NetSentrix — \(alert.category)"
        content.body = alert.message
        if alert.severity.lowercased() == "high" {
            content.sound = .default
        }
        let request = UNNotificationRequest(
            identifier: "netsentrix-alert-\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
