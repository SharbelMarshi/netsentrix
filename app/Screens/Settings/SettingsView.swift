import SwiftUI

private enum BlockPolicyChoice: String, CaseIterable, Identifiable {
    case aZero = "a_zero"
    case nxDomain = "nx_domain"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aZero: return "A → 0.0.0.0 (silent block)"
        case .nxDomain: return "NXDOMAIN"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var engine: EngineService
    @State private var upstreamEdit = ""
    @State private var blockPolicySelection: BlockPolicyChoice = .aZero
    @State private var protectionWindowEdit = ""
    @State private var successBanner: String?
    @State private var protectionWindowHint: String?
    @State private var quickDomainRule = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Operator controls for the NetSentrix engine on this Mac. Changes need API access (Bearer token).")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)

                dnsAnsweringGroup

                GroupBox("Upstream resolver") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Address NetSentrix forwards to after your allow/block rules (e.g. 8.8.8.8:53). Must be reachable from this Mac."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        TextField("e.g. 8.8.8.8:53", text: $upstreamEdit)
                            .textFieldStyle(.roundedBorder)
                        Button("Save upstream") {
                            Task {
                                successBanner = nil
                                let u = upstreamEdit.trimmingCharacters(in: .whitespaces)
                                await engine.saveUpstream(u)
                                if engine.lastOperationError == nil { successBanner = "Upstream saved." }
                            }
                        }
                        .disabled(
                            upstreamEdit.trimmingCharacters(in: .whitespaces).isEmpty || engine.isSavingSettings
                        )
                    }
                }

                GroupBox("Block response policy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How blocked names are answered to clients (DNS responses).")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Picker("Policy", selection: $blockPolicySelection) {
                            ForEach(BlockPolicyChoice.allCases) { c in
                                Text(c.title).tag(c)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(ProductStatusAdapter.blockPolicyDescription(blockPolicySelection.rawValue))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Save block policy") {
                            Task {
                                successBanner = nil
                                await engine.saveBlockPolicy(blockPolicySelection.rawValue)
                                if engine.lastOperationError == nil { successBanner = "Block policy saved." }
                            }
                        }
                        .disabled(engine.isSavingSettings)
                    }
                }

                GroupBox("Protection activity window") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Seconds used for “recent client activity” and protection hints on the Dashboard and Setup (engine clamps 10–86,400)."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        TextField("Seconds (e.g. 300)", text: $protectionWindowEdit)
                            .textFieldStyle(.roundedBorder)
                        Button("Save window") {
                            Task {
                                successBanner = nil
                                protectionWindowHint = nil
                                guard let secs = UInt64(protectionWindowEdit.trimmingCharacters(in: .whitespaces)),
                                      (10 ... 86_400).contains(secs)
                                else {
                                    protectionWindowHint = "Enter a whole number of seconds between 10 and 86,400."
                                    return
                                }
                                await engine.saveProtectionActivityWindow(seconds: secs)
                                if engine.lastOperationError == nil { successBanner = "Activity window saved." }
                            }
                        }
                        .disabled(engine.isSavingSettings)
                        if let h = protectionWindowHint {
                            Text(h).font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }

                GroupBox("Block or allow a domain") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Adds a rule in the engine database and reloads the live DNS filter (same as Queries → Block / Allow). You can use a suffix pattern such as *.example.com when supported."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        TextField("Domain or pattern", text: $quickDomainRule)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 12) {
                            Button("Block") {
                                Task {
                                    successBanner = nil
                                    engine.clearDomainRuleSuccess()
                                    await engine.blockDomain(quickDomainRule)
                                    if engine.lastOperationError == nil {
                                        successBanner = engine.lastDomainRuleSuccess ?? "Block rule added."
                                    }
                                }
                            }
                            .disabled(
                                quickDomainRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || engine.isApplyingDomainRule
                            )
                            Button("Allow") {
                                Task {
                                    successBanner = nil
                                    engine.clearDomainRuleSuccess()
                                    await engine.allowDomain(quickDomainRule)
                                    if engine.lastOperationError == nil {
                                        successBanner = engine.lastDomainRuleSuccess ?? "Allow rule added."
                                    }
                                }
                            }
                            .disabled(
                                quickDomainRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || engine.isApplyingDomainRule
                            )
                            if engine.isApplyingDomainRule {
                                ProgressView().scaleEffect(0.85)
                            }
                        }
                    }
                }

                if let s = engine.settings {
                    GroupBox("Read-only — current engine config") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("DNS listen") {
                                Text(s.dns.listenAddr).font(.body.monospaced())
                            }
                            LabeledContent("Upstream") {
                                Text(s.dns.upstream).font(.caption.monospaced())
                            }
                            LabeledContent("Block policy") {
                                Text(s.dns.blockPolicy).font(.caption.monospaced())
                            }
                            LabeledContent("Protection window (s)") {
                                Text("\(s.dns.protectionActivityWindowSecs)").font(.caption.monospaced())
                            }
                            LabeledContent("API listen") {
                                Text(s.apiListen).font(.caption.monospaced())
                            }
                        }
                    }
                }

                GroupBox("Reload config from disk") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Rereads config.toml from disk and reloads list files into the running engine. Use after you edit the file manually outside this app."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        Button("Reload from disk") {
                            Task {
                                successBanner = nil
                                await engine.reloadConfigFromDisk()
                                if engine.lastOperationError == nil { successBanner = "Reloaded from disk." }
                                syncDraftsFromSettings()
                            }
                        }
                        .disabled(engine.isSavingSettings)
                    }
                }

                GroupBox("Engine process") {
                    Text("Start, stop, and upgrades are handled outside this app (e.g. launchctl for a LaunchDaemon).")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 12) {
                    Button("Refresh from engine") {
                        Task {
                            successBanner = nil
                            await engine.refreshSettings()
                            syncDraftsFromSettings()
                        }
                    }
                    .disabled(engine.isSavingSettings)
                    if engine.isSavingSettings {
                        ProgressView().scaleEffect(0.85)
                        Text("Saving…").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }

                if let ok = successBanner {
                    Text(ok)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.allowed)
                }

                if let e = engine.lastOperationError {
                    Text(e)
                        .font(.subheadline)
                        .foregroundStyle(Theme.blocked)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.deepNavy)
        .task {
            await engine.refreshSettings()
            await engine.refreshHealth()
            syncDraftsFromSettings()
        }
        .onChange(of: engine.settings?.dns.upstream) { new in
            guard let new else { return }
            if upstreamEdit.isEmpty || upstreamEdit == new {
                upstreamEdit = new
            }
        }
    }

    private var dnsAnsweringGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("DNS answering (pause / resume)", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                Text(
                    "When paused, NetSentrix replies to DNS queries with SERVFAIL and does not forward to your upstream resolver or apply normal filtering — clients see DNS failures. Use for maintenance or emergencies."
                )
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                Text("When resumed, normal allow/block rules and forwarding apply again.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 12) {
                    Button("Pause DNS answering") {
                        Task {
                            successBanner = nil
                            await engine.pauseDnsAnswering()
                            if engine.lastOperationError == nil { successBanner = "DNS answering paused." }
                        }
                    }
                    .disabled(engine.isSavingSettings || engine.lastHealth?.dnsPaused == true)
                    Button("Resume DNS answering") {
                        Task {
                            successBanner = nil
                            await engine.resumeDnsAnswering()
                            if engine.lastOperationError == nil { successBanner = "DNS answering resumed." }
                        }
                    }
                    .disabled(engine.isSavingSettings || engine.lastHealth?.dnsPaused == false)
                }

                if let paused = engine.lastHealth?.dnsPaused {
                    Text(paused ? "Status: paused (SERVFAIL, no forward)." : "Status: answering normally.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(paused ? Theme.warning : Theme.allowed)
                } else if engine.isEngineUnreachable {
                    Text("Engine unreachable — pause state unknown.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Refresh health to show pause state.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } label: {
            Text("DNS answering")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func syncDraftsFromSettings() {
        if let u = engine.settings?.dns.upstream {
            upstreamEdit = u
        }
        if let p = engine.settings?.dns.blockPolicy,
           let choice = BlockPolicyChoice(rawValue: p.lowercased()) {
            blockPolicySelection = choice
        }
        if let w = engine.settings?.dns.protectionActivityWindowSecs {
            protectionWindowEdit = String(w)
        }
    }
}
