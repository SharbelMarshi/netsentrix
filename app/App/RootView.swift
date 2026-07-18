import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $appModel.selectedDestination) {
                ForEach(AppDestination.allCases) { dest in
                    Label(dest.title, systemImage: dest.systemImage)
                        .tag(dest)
                        .listRowBackground(sidebarRowBackground(selected: appModel.selectedDestination == dest))
                }
            }
            .navigationTitle("NetSentrix")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minWidth: 200)
            .background(Theme.deepNavy)
        } detail: {
            detailView(for: appModel.selectedDestination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Theme.accent)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func sidebarRowBackground(selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.accent.opacity(0.95))
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 4)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func detailView(for dest: AppDestination) -> some View {
        switch dest {
        case .dashboard: DashboardView()
        case .devices: DevicesView()
        case .queries: QueriesView()
        case .alerts: AlertsView()
        case .setup: SetupView()
        case .settings: SettingsView()
        }
    }
}
