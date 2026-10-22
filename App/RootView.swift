import SwiftUI

enum AppTab:Hashable {case home,map,together,moments,settings}
struct RootView:View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var update=UpdateCoordinator.shared
    var body:some View {
        ZStack {
            LoveBackground()
            switch appState.phase {
            case .setup:ServerSetupView()
            case .restoring:ProgressView(appState.connectionMessage).padding(30)
            case .authenticated:
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-recorder") {FartRecorderView(autoStart:false)}
                else if ProcessInfo.processInfo.arguments.contains("--preview-delivery") {NavigationStack{DeliveryCenterView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-planner") {NavigationStack{PlannerView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-media-composer") {MediaComposer(media:PreviewFixtures.media(),kind:.moment)}
                else if ProcessInfo.processInfo.arguments.contains("--preview-messenger") {NavigationStack{MessengerView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-setup") {SetupJourneyView()}
                else if ProcessInfo.processInfo.arguments.contains("--preview-health") {NavigationStack{HealthDashboardView()}}
                else {MainTabView()}
                #else
                MainTabView()
                #endif
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityIdentifier("rj-root").previewAccessibilityEnvironment()
            .overlay{if update.requirement != nil {UpdateRequiredView()}}
            .task{await appState.activate()}
            .alert(item:Binding(get:{appState.alert},set:{appState.alert=$0})){Alert(title:Text($0.title),message:Text($0.message),dismissButton:.default(Text("OK")))}
    }
}
struct MainTabView:View {
    @Environment(AppState.self) private var appState
    var body:some View {
        @Bindable var state=appState
        @Bindable var journey=appState.setupJourney
        TabView(selection:$state.selectedTab) {
            NavigationStack{HomeView()}.tabItem{Label("Wir",systemImage:"heart.fill")}.tag(AppTab.home)
            NavigationStack{PartnerMapView()}.tabItem{Label("Karte",systemImage:"location.fill")}.tag(AppTab.map)
            NavigationStack{LoveHubView()}.tabItem{Label("Für uns",systemImage:"person.2.fill")}.tag(AppTab.together)
            NavigationStack{ExperienceView()}.tabItem{Label("Spielplatz",systemImage:"sparkles")}.tag(AppTab.moments)
            NavigationStack{SettingsView()}.tabItem{Label("Mehr",systemImage:"slider.horizontal.3")}.tag(AppTab.settings)
        }
        .sheet(isPresented:$state.showingFartRecorder,onDismiss:{appState.offerForegroundMoments()}){FartRecorderView(autoStart:appState.quickFartRecording)}
        .sheet(isPresented:$state.showingChangelog,onDismiss:{appState.offerForegroundMoments()}){ChangelogView()}
        .sheet(item:$state.pendingSweet,onDismiss:{appState.offerForegroundMoments()}){SweetPlaybackView(record:$0)}
        .fullScreenCover(item:$state.pendingPhotoRequest,onDismiss:{appState.offerForegroundMoments()}){InstantCameraView(request:$0)}
        .fullScreenCover(isPresented:$journey.presented,onDismiss:{Task{_ = await appState.syncNow(showErrors:false)}}){SetupJourneyView()}
    }
}
struct ChangelogView:View {
    @Environment(AppState.self) private var app
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:22){
                Image(systemName:"heart.text.clipboard.fill").font(.system(size:50)).foregroundStyle(LovePalette.pink)
                Text("Noch mehr wir.").font(.system(size:36,weight:.medium,design:.serif))
                Text("Willkommen in RJ Love 3.0").font(.title3.bold())
                Label("Messenger mit Fotos, Videos und Sprachnachrichten",systemImage:"bubble.left.and.bubble.right.fill")
                Label("Momente, Alben und echte Live Photos",systemImage:"photo.stack.fill")
                Label("Duftpost importieren, lokal sichern und als Playlist hören",systemImage:"wind")
                Label("Gemeinsame Termine, Jahrestage und optionale Wecker",systemImage:"calendar.badge.clock")
                Label("Jeder Herzgedanke mit Datum und Sekunden",systemImage:"heart.fill")
                Text("Neu zunächst eingeschaltet: Aufnahmeorte bei neuer Duftpost, Fotowünsche mit sichtbarem 3-Sekunden-Countdown und abbrechbarer Kamera sowie süße Nachrichten beim Öffnen. iOS-Zugriffsrechte gelten weiterhin. Unter Mehr kannst du diese Optionen jederzeit ändern.").font(.subheadline).foregroundStyle(.secondary)
                Text("Walkie-Talkie und die eigene Face-ID-Sperre sind entfernt. Eure Konten, Aufnahmen und bisherigen Momente bleiben erhalten.").font(.footnote)
                Button("Schön, los geht’s") {app.didReadChangelog()}.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(26)}.background(LoveBackground()).navigationTitle("Neu für euch")
        }.interactiveDismissDisabled()
    }
}
