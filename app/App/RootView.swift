import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @EnvironmentObject private var engine: EngineService

    var body: some View {
        NavigationSplitView {
            List(selection: $appModel.selectedDestination) {
                ForEach(AppDestination.allCases) { dest in
                    Label(dest.title, systemImage: dest.systemImage)
                        .tag(dest)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detailView(for: appModel.selectedDestination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(appModel.selectedDestination.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await refreshCurrentScreen() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh this screen (⌘R)")
                    }
                }
        }
    }

    @ViewBuilder
    private func detailView(for dest: AppDestination) -> some View {
        switch dest {
        case .dashboard: DashboardView()
        case .devices: DevicesView()
        case .queries: QueriesView()
        case .alerts: AlertsView()
        case .setup: SetupView()
        case .settings: SettingsView()
        }
    }

    private func refreshCurrentScreen() async {
        switch appModel.selectedDestination {
        case .dashboard, .setup:
            await engine.refreshAllDashboardData()
        case .devices:
            await engine.refreshDevices()
        case .queries:
            await engine.refreshQueries(limit: 100, deviceId: appModel.queriesDeviceFilterId)
        case .alerts:
            await engine.refreshAlerts()
        case .settings:
            await engine.refreshSettings()
            await engine.refreshHealth()
        }
    }
}
