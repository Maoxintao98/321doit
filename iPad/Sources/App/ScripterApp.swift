import SwiftUI
import UIKit

@main
struct ScripterApp: App {
    @StateObject private var store = ScripterStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunch = true

    init() {
        // Make every navigation bar fully transparent with no shadow line, so
        // the content shows through and there is no color seam or white band
        // below the status bar.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.shadowColor = .clear
        navAppearance.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // The TabView's top bar (the "项目/场记" pill region on iPad) also paints
        // an opaque background — that is the white band under the status bar.
        // Make it transparent so the gray content background shows through.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = .clear
        tabAppearance.shadowColor = .clear
        tabAppearance.shadowImage = UIImage()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)
                    .environment(\.palette, Palette())
                    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())

                if showLaunch {
                    LaunchView {
                        withAnimation(.easeInOut(duration: 0.4)) { showLaunch = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            // Flush pending edits before iOS suspends us: the debounced async
            // save may not run once the app leaves the foreground.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.saveNow() }
            }
        }
    }
}
