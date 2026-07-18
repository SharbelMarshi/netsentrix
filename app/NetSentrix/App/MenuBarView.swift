import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var engine: EngineService
    @EnvironmentObject private var engineProcess: EngineProcessManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(protectionSummary)
            if engine.isEngineUnreachable {
                Button("Start engine") {
                    Task { await engineProcess.start(engineService: engine) }
                }
            }
            if let paused = engine.lastHealth?.dnsPaused {
                if paused {
                    Button("Resume DNS answering") {
                        Task { await engine.resumeDnsAnswering() }
                    }
                } else {
                    Button("Pause DNS answering") {
                        Task { await engine.pauseDnsAnswering() }
                    }
                }
            }
            Divider()
            Button("Open NetSentrix") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Refresh status") {
                Task { await engine.refreshHealth() }
            }
            Divider()
            Button("Quit NetSentrix") {
                NSApp.terminate(nil)
            }
        }
        .task {
            await engineProcess.autostartIfNeeded(engineService: engine)
            await engine.refreshHealth()
        }
    }

    private var protectionSummary: String {
        guard let h = engine.lastHealth else {
            return engine.isEngineUnreachable ? "Engine unreachable" : "Checking engine…"
        }
        if h.dnsPaused == true {
            return "DNS paused (SERVFAIL)"
        }
        if let p = h.protection {
            switch p.state.lowercased() {
            case "protecting": return "Protecting your network"
            case "idle": return "Idle — no recent LAN clients"
            default: return "Protection: \(p.state)"
            }
        }
        return "Engine \(h.engineStatus)"
    }
}
