import SwiftUI

@main
struct NetSentrixApp: App {
    @StateObject private var appModel = AppViewModel()
    @StateObject private var engineService = EngineService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(engineService)
                // System controls default to light-mode (dark) text on dark custom backgrounds.
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1040, height: 700)
    }
}
