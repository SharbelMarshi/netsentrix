import SwiftUI

@main
struct NetSentrixApp: App {
    @StateObject private var appModel = AppViewModel()
    @StateObject private var engineService = EngineService()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appModel)
                .environmentObject(engineService)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {
                Button("Export Queries as CSV…") {
                    engineService.exportQueriesCSVUsingSavePanel()
                }
                .keyboardShortcut("e")
            }
            CommandMenu("Go") {
                ForEach(AppDestination.allCases) { dest in
                    Button(dest.title) {
                        appModel.selectedDestination = dest
                    }
                    .keyboardShortcut(dest.commandShortcut)
                }
                Divider()
                Button("Refresh") {
                    Task { await refreshCurrentScreen() }
                }
                .keyboardShortcut("r")
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(engineService)
        }

        MenuBarExtra("NetSentrix", systemImage: menuBarSymbol) {
            MenuBarView()
                .environmentObject(engineService)
        }
    }

    private var menuBarSymbol: String {
        guard let h = engineService.lastHealth else { return "shield.slash" }
        if h.dnsPaused == true { return "pause.circle" }
        if h.protection?.state.lowercased() == "protecting" { return "shield.fill" }
        return "shield"
    }

    private func refreshCurrentScreen() async {
        switch appModel.selectedDestination {
        case .dashboard, .setup:
            await engineService.refreshAllDashboardData()
        case .devices:
            await engineService.refreshDevices()
        case .queries:
            await engineService.refreshQueries(limit: 100, deviceId: appModel.queriesDeviceFilterId)
        case .alerts:
            await engineService.refreshAlerts()
        case .settings:
            await engineService.refreshSettings()
            await engineService.refreshHealth()
        }
    }
}
