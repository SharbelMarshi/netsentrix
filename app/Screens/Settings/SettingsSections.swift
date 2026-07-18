import SwiftUI

/// Settings → Engine connection: API address + token file override.
struct EngineConnectionSection: View {
    @EnvironmentObject private var engine: EngineService
    @State private var addressEdit = ""
    @State private var tokenPathEdit = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false

    var body: some View {
        GroupBox("Engine connection") {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Where this app reaches the engine API. Match `api.listen` in config.toml; leave empty for the default (127.0.0.1:8756)."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                TextField("127.0.0.1:8756", text: $addressEdit)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Token file override — useful when the engine runs as a LaunchDaemon with a shared token. Leave empty to use the standard locations."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                TextField(APITokenLoader.daemonDefaultTokenPath, text: $tokenPathEdit)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                HStack(spacing: 12) {
                    Button("Save connection") { save() }
                    if let f = feedback {
                        Text(f)
                            .font(.caption)
                            .foregroundStyle(feedbackIsError ? Theme.blocked : Theme.allowed)
                    }
                }
            }
        }
        .onAppear {
            if UserDefaults.standard.string(forKey: EngineEndpoint.defaultsKey) != nil {
                addressEdit = EngineEndpoint.current.absoluteString
            }
            tokenPathEdit = UserDefaults.standard.string(forKey: APITokenLoader.defaultsKey) ?? ""
        }
    }

    private func save() {
        let trimmedAddress = addressEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAddress.isEmpty, EngineEndpoint.normalize(trimmedAddress) == nil {
            feedback = "Enter a host:port such as 127.0.0.1:8756."
            feedbackIsError = true
            return
        }
        EngineEndpoint.save(trimmedAddress)
        let trimmedToken = tokenPathEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            UserDefaults.standard.removeObject(forKey: APITokenLoader.defaultsKey)
        } else {
            UserDefaults.standard.set(trimmedToken, forKey: APITokenLoader.defaultsKey)
        }
        feedback = "Saved — now using \(EngineEndpoint.current.absoluteString)."
        feedbackIsError = false
        Task { await engine.refreshHealth() }
    }
}

/// Settings → Notifications: opt-in macOS notifications for new alerts.
struct NotificationsSection: View {
    @AppStorage(AlertNotifier.enabledDefaultsKey) private var notificationsEnabled = false

    var body: some View {
        GroupBox("Notifications") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Notify when new alerts arrive", isOn: $notificationsEnabled)
                    .disabled(!AlertNotifier.isSupported)
                    .onChange(of: notificationsEnabled) { enabled in
                        if enabled { AlertNotifier.shared.requestAuthorization() }
                    }
                Text(
                    AlertNotifier.isSupported
                        ? "Checks for new alerts about once a minute, even when the Alerts screen is closed."
                        : "Notifications need the bundled app (make bundle) — not available under swift run."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Settings → Scheduled DNS policies (`/policy/time-overrides`).
struct TimeOverridesSection: View {
    @EnvironmentObject private var engine: EngineService
    @State private var scopeDeviceId = ""
    @State private var startTime = defaultTime(hour: 21)
    @State private var endTime = defaultTime(hour: 7)
    @State private var policy = "paused"
    @State private var isSaving = false

    private static let policies = ["normal", "restricted", "paused", "blocked"]

    var body: some View {
        GroupBox("Scheduled DNS policies") {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Time windows (local time) that override device DNS policy — e.g. pause a device's DNS overnight. Windows may cross midnight."
                )
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

                if let err = engine.timeOverridesFetchError {
                    Text(err).font(.caption).foregroundStyle(Theme.blocked)
                }

                if engine.timeOverrides.isEmpty {
                    Text("No schedules yet.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(engine.timeOverrides) { row in
                        HStack {
                            Text(Self.describe(row))
                                .font(.callout)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await engine.deleteTimeOverride(id: row.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this schedule")
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Picker("Policy", selection: $policy) {
                        ForEach(Self.policies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .frame(maxWidth: 150)
                    DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Picker("Applies to", selection: $scopeDeviceId) {
                    Text("All devices").tag("")
                    ForEach(engine.devices) { d in
                        Text(d.id).tag(d.id)
                    }
                }
                .frame(maxWidth: 320)
                HStack(spacing: 12) {
                    Button("Add schedule") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            await engine.addTimeOverride(
                                scopeDeviceId: scopeDeviceId.isEmpty ? nil : scopeDeviceId,
                                startMin: Self.minuteOfDay(startTime),
                                endMin: Self.minuteOfDay(endTime),
                                dnsPolicy: policy
                            )
                        }
                    }
                    .disabled(isSaving)
                    if isSaving { ProgressView().scaleEffect(0.85) }
                }
            }
        }
        .task {
            await engine.refreshTimeOverrides()
            if engine.devices.isEmpty {
                await engine.refreshDevices()
            }
        }
    }

    private static func defaultTime(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func formatMinute(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func describe(_ row: TimeOverrideDTO) -> String {
        let scope = row.scopeDeviceId.map { "Device \($0)" } ?? "All devices"
        let window = "\(formatMinute(row.startMin))–\(formatMinute(row.endMin))"
        let state = row.enabled ? "" : " (disabled)"
        return "\(scope): \(row.dnsPolicy) \(window)\(state)"
    }
}

/// Settings → Engine process: install the embedded engine as a LaunchDaemon.
struct EngineDaemonSection: View {
    @StateObject private var daemon = EngineDaemonManager()

    var body: some View {
        GroupBox("Engine process") {
            VStack(alignment: .leading, spacing: 10) {
                if daemon.isAvailable {
                    Text(
                        "This build embeds the NetSentrix engine. Installing registers it as a system LaunchDaemon (starts at boot, runs as root so DNS can bind port 53). macOS asks for approval in System Settings → Login Items."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    LabeledContent("Status") {
                        Text(daemon.statusDescription).font(.caption)
                    }
                    HStack(spacing: 12) {
                        Button("Install engine") { daemon.register() }
                            .disabled(daemon.status == .enabled)
                        Button("Uninstall") { daemon.unregister() }
                            .disabled(daemon.status == .notRegistered || daemon.status == .notFound)
                        Button("Open Login Items…") { daemon.openLoginItemsSettings() }
                    }
                    if let err = daemon.lastError {
                        Text(err).font(.caption).foregroundStyle(Theme.blocked)
                    }
                } else {
                    Text(
                        "No embedded engine in this build. Use an app built with `make bundle-full`, or manage the engine with launchctl (see packaging/macos/launchd/)."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onAppear { daemon.refreshStatus() }
    }
}
