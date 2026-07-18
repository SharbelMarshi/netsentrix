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
}
