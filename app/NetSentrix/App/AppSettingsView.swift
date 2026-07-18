import SwiftUI

/// Native Settings window (⌘,) — app-level preferences. Engine operator
/// controls stay in the sidebar's Settings screen.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            ScrollView {
                EmbeddedEngineSection()
                    .padding(16)
            }
            .tabItem {
                Label("Engine", systemImage: "bolt.horizontal.circle")
            }

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
        .frame(width: 540, height: 360)
    }
}

struct EmbeddedEngineSection: View {
    @EnvironmentObject private var engine: EngineService
    @EnvironmentObject private var engineProcess: EngineProcessManager
    @AppStorage(EngineProcessManager.autoStartDefaultsKey) private var autoStart = true

    var body: some View {
        GroupBox("Embedded engine") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Start engine automatically when the app opens", isOn: $autoStart)
                Text(
                    "The engine runs as an unprivileged helper of this app and stops when the app quits. It serves DNS on the port from config.toml; binding :53 for the whole LAN needs the LaunchDaemon install instead (sidebar Settings → Engine process)."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                LabeledContent("Status") {
                    Text(engineProcess.statusDescription).font(.caption)
                }
                HStack(spacing: 12) {
                    Button("Start now") {
                        Task { await engineProcess.start(engineService: engine) }
                    }
                    .disabled(engineProcess.state == .running || engineProcess.state == .starting)
                    Button("Stop") {
                        engineProcess.stop()
                    }
                    .disabled(engineProcess.state != .running && engineProcess.state != .starting)
                    Button("Open log") {
                        if let url = EngineProcessManager.logFileURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
}
