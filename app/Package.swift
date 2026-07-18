// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetSentrix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NetSentrix", targets: ["NetSentrix"]),
    ],
    targets: [
        .executableTarget(
            name: "NetSentrix",
            dependencies: [],
            path: ".",
            sources: [
                "App/NetSentrixApp.swift",
                "App/RootView.swift",
                "App/Theme.swift",
                "App/MenuBarView.swift",
                "Screens/Dashboard/DashboardView.swift",
                "Screens/Devices/DevicesView.swift",
                "Screens/Queries/QueriesView.swift",
                "Screens/Alerts/AlertsView.swift",
                "Screens/Setup/SetupView.swift",
                "Screens/Settings/SettingsView.swift",
                "Screens/Settings/SettingsSections.swift",
                "ViewModels/AppViewModel.swift",
                "ViewModels/ProductStatusAdapter.swift",
                "Models/HealthModels.swift",
                "Models/APIModels.swift",
                "Models/DomainPattern.swift",
                "Networking/EngineAPIClient.swift",
                "Services/EngineService.swift",
                "Services/APITokenLoader.swift",
                "Services/EngineEndpoint.swift",
                "Services/EngineDaemonManager.swift",
                "Services/AlertNotifier.swift",
            ]
        ),
        .testTarget(
            name: "NetSentrixTests",
            dependencies: ["NetSentrix"],
            path: "Tests/NetSentrixTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
