import SwiftUI

@main
struct RJLoveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(LovePalette.pink)
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "rjlove" {
                        appState.handleDeepLink(url)
                        Task { await appState.syncNow(showErrors: false) }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await appState.activate() }
            case .inactive:
                appState.prepareToLeaveForeground()
            case .background:
                appState.deactivateForeground()
            default:
                break
            }
        }
    }
}

