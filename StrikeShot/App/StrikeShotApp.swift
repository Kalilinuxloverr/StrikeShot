import SwiftUI

@main
struct StrikeShotApp: App {
    @State private var services = AppServices()
    @State private var showingBoot = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(services)
                    .opacity(showingBoot ? 0 : 1)

                if showingBoot {
                    BootAnimationView {
                        withAnimation(.easeOut(duration: 0.35)) { showingBoot = false }
                    }
                    .transition(.opacity)
                }
            }
            .stormThemed(services.theme)
            .preferredColorScheme(.dark)
            .task { await services.start() }
        }
    }
}
