import SwiftUI

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.stormTheme) private var theme
    @State private var selection: Tab = .capture

    enum Tab: Hashable {
        case capture, map, log, stats, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            CaptureScreen()
                .tabItem {
                    Label(String(localized: "tab.capture", defaultValue: "Kamera"),
                          systemImage: "bolt.fill")
                }
                .tag(Tab.capture)

            MapScreen()
                .tabItem {
                    Label(String(localized: "tab.map", defaultValue: "Karte"),
                          systemImage: "map.fill")
                }
                .tag(Tab.map)

            StormLogScreen()
                .tabItem {
                    Label(String(localized: "tab.log", defaultValue: "Tagebuch"),
                          systemImage: "book.closed.fill")
                }
                .tag(Tab.log)

            StatsScreen()
                .tabItem {
                    Label(String(localized: "tab.stats", defaultValue: "Statistik"),
                          systemImage: "chart.bar.fill")
                }
                .tag(Tab.stats)

            SettingsScreen()
                .tabItem {
                    Label(String(localized: "tab.settings", defaultValue: "Einstellungen"),
                          systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(theme.accent)
        .overlay(alignment: .top) { alertOverlay }
    }

    /// Safety warnings must reach the user wherever they are in the app, so the
    /// banner lives above the tabs rather than inside a single screen.
    @ViewBuilder
    private var alertOverlay: some View {
        if let alert = services.alerts.activeAlerts.last {
            AlertBanner(alert: alert) { services.alerts.dismiss(alert) }
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.4), value: alert.id)
        }
    }
}
