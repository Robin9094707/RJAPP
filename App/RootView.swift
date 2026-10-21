import SwiftUI

enum AppTab: Hashable {
    case home
    case map
    case together
    case moments
    case settings
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            LoveBackground()
            switch appState.phase {
            case .setup:
                ServerSetupView()
            case .restoring:
                VStack(spacing: 18) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 68))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, LovePalette.pink)
                    ProgressView()
                        .controlSize(.large)
                    Text(appState.connectionMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(30)
                .loveGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            case .authenticated:
                if appState.privacyLock.isUnlocked {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--preview-recorder") {
                        FartRecorderView(autoStart: false)
                    } else if ProcessInfo.processInfo.arguments.contains("--preview-delivery") {
                        NavigationStack { DeliveryCenterView() }
                    } else if ProcessInfo.processInfo.arguments.contains("--preview-radio") {
                        NavigationStack { WalkieTalkieView() }
                    } else if ProcessInfo.processInfo.arguments.contains("--preview-setup") {
                        SetupJourneyView()
                    } else if ProcessInfo.processInfo.arguments.contains("--preview-health") {
                        NavigationStack { HealthDashboardView() }
                    } else { MainTabView() }
                    #else
                    MainTabView()
                    #endif
                } else {
                    PrivacyLockView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("rj-root")
        .previewAccessibilityEnvironment()
        .task {
            await appState.activate()
        }
        .alert(item: Binding(
            get: { appState.alert },
            set: { appState.alert = $0 }
        )) { value in
            Alert(title: Text(value.title), message: Text(value.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct PrivacyLockView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.heart.fill")
                .font(.system(size: 70))
                .foregroundStyle(LovePalette.pink)
            Text("RJ Love ist geschützt")
                .font(.title2.bold())
            Text("Entsperre eure privaten Inhalte mit Face ID, Touch ID oder deinem Gerätecode.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Entsperren") {
                Task { _ = await appState.privacyLock.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .loveCard()
        .padding(22)
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        @Bindable var journey = appState.setupJourney

        TabView(selection: $state.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Wir", systemImage: "heart.fill") }
                .tag(AppTab.home)
            NavigationStack { PartnerMapView() }
                .tabItem { Label("Karte", systemImage: "location.fill") }
                .tag(AppTab.map)
            NavigationStack { LoveHubView() }
                .tabItem { Label("Für uns", systemImage: "person.2.fill") }
                .tag(AppTab.together)
            NavigationStack { ExperienceView() }
                .tabItem { Label("Spielplatz", systemImage: "sparkles") }
                .tag(AppTab.moments)
            NavigationStack { SettingsView() }
                .tabItem { Label("Mehr", systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $state.showingFartRecorder, onDismiss: { Task { await appState.radio.restoreIfEnabled(api: appState.api) } }) {
            FartRecorderView(autoStart: appState.quickFartRecording)
        }
        .sheet(isPresented: $state.showingRadio) { NavigationStack { WalkieTalkieView() } }
        .fullScreenCover(isPresented: $journey.presented) { SetupJourneyView() }
    }
}
