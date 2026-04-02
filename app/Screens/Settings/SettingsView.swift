import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var upstreamEdit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            GroupBox("Upstream DNS") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Resolver NetSentrix uses after applying your block and allow rules. Must be reachable from this Mac (e.g. 8.8.8.8:53).")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("e.g. 8.8.8.8:53", text: $upstreamEdit)
                        .textFieldStyle(.roundedBorder)
                    Button("Save upstream") {
                        Task {
                            await engine.saveUpstream(upstreamEdit.trimmingCharacters(in: .whitespaces))
                            await engine.refreshSettings()
                        }
                    }
                    .disabled(upstreamEdit.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let s = engine.settings {
                GroupBox("Current configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Upstream") {
                            Text(s.dns.upstream).font(.body.monospaced())
                        }
                        LabeledContent("Block policy") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.dns.blockPolicy).font(.caption.monospaced())
                                Text(ProductStatusAdapter.blockPolicyDescription(s.dns.blockPolicy))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        LabeledContent("API bind (technical)") {
                            Text(s.apiListen).font(.caption.monospaced())
                        }
                    }
                }
            }

            GroupBox("Engine control") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restart and stop are not available from this app yet — manage the engine with your usual launch method (e.g. launchd or Terminal).")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Button("Reload from engine") {
                Task { await engine.refreshSettings() }
            }

            if let e = engine.lastOperationError {
                Text(e).foregroundStyle(Theme.blocked)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task {
            await engine.refreshSettings()
            if let u = engine.settings?.dns.upstream {
                upstreamEdit = u
            }
        }
        .onChange(of: engine.settings?.dns.upstream) { new in
            guard let new else { return }
            if upstreamEdit.isEmpty {
                upstreamEdit = new
            }
        }
    }
}
