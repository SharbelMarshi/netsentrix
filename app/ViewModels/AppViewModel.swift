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
}
