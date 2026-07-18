import SwiftUI

/// Native Settings window (⌘,) — app-level preferences. Engine operator
/// controls stay in the sidebar's Settings screen.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            ScrollView {
                EngineConnectionSection()
                    .padding(16)
            }
            .tabItem {
                Label("Connection", systemImage: "network")
            }

            ScrollView {
                NotificationsSection()
                    .padding(16)
            }
            .tabItem {
                Label("Notifications", systemImage: "bell.badge")
            }
        }
        .frame(width: 520, height: 320)
    }
}
