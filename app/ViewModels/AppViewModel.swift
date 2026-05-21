import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case dashboard, devices, queries, alerts, setup, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .devices: "Devices"
        case .queries: "Queries"
        case .alerts: "Alerts"
        case .setup: "Setup"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .devices: "laptopcomputer.and.iphone"
        case .queries: "list.bullet.rectangle"
        case .alerts: "exclamationmark.triangle"
        case .setup: "wand.and.stars"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedDestination: AppDestination = .dashboard

    /// When set, Queries uses `GET /queries?device_id=…` and filters the live stream to this client key.
    @Published var queriesDeviceFilterId: String?
    /// Optional domain string to sort/highlight on the Queries table (from alert context).
    @Published var queriesHighlightDomain: String?

    func openQueries(deviceFilter: String?, highlightDomain: String?) {
        queriesDeviceFilterId = deviceFilter
        queriesHighlightDomain = highlightDomain
        selectedDestination = .queries
    }

    func clearQueriesNavigationContext() {
        queriesDeviceFilterId = nil
        queriesHighlightDomain = nil
    }
}
