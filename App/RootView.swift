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
                if ProcessInfo.processInfo.arguments.contains("--preview-instant-gallery") {NavigationStack{InstantGalleryView()}.fullScreenCover(item:Binding(get:{appState.pendingPhotoRequest},set:{appState.pendingPhotoRequest=$0})){InstantCameraView(request:$0)}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-profile") {NavigationStack{SettingsView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-status") {NavigationStack{StatusEditorView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-recorder") {FartRecorderView(autoStart:false)}
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
            NavigationStack{ExperienceView()}.tabItem{Label("Erleben",systemImage:"sparkles")}.tag(AppTab.moments)

        }

        .tint(LovePalette.pink)
        .sheet(isPresented:$state.showingEvening,onDismiss:{appState.didCloseEvening()}){NavigationStack{SharedJournalView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingEvening=false}}}}}
        .sheet(isPresented:$state.showingPartnerProfile){NavigationStack{PartnerProfileView()}.presentationDragIndicator(.visible)}
        .sheet(isPresented:$state.showingCountdowns){NavigationStack{CountdownHubView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingCountdowns=false}}}}}
        .sheet(isPresented:$state.showingHealthUpgrade,onDismiss:{appState.health.deferExpandedAccess();appState.offerForegroundMoments()}){HealthPermissionsUpgradeView()}
        .sheet(isPresented:$state.showingStatus){StatusEditorSheet()}
        .onChange(of:state.selectedTab){_,tab in if tab == .settings{state.selectedTab = .home;state.showingProfile=true}}
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
                LoveIcon(symbol:"heart.fill",tint:LovePalette.pink,size:70)
                Text("Mehr Ruhe.\nMehr wir.").font(.system(size:38,weight:.medium,design:.serif))
                Text("Willkommen in RJ Love 3.6").font(.title3.bold())
                Label("Ein offener Fotowunsch pro Person",systemImage:"camera.badge.ellipsis")
                Label("Wartende Wünsche sehen und bewusst zurückrufen",systemImage:"arrow.uturn.backward")
                Label("Ein neues Profil mit klaren Einstellungen",systemImage:"person.crop.circle.fill")
                Label("Ruhigere Farben, Karten und einheitliche Symbole",systemImage:"square.stack.3d.up.fill")
                Text("Dein Status öffnet sich jetzt innerhalb des Profils mit einem normalen iOS-Übergang. Die Karten in der App sind ruhiger, während Bedienelemente ihren nativen Glasstil behalten.").font(.subheadline).foregroundStyle(.secondary)
                Text("Alte unbeantwortete Fotowunsch-Stapel werden beim Serverupdate auf den neuesten Wunsch pro Absender begrenzt. Fertige Fotos und eure Erinnerungen bleiben erhalten. Bitte App und Server gemeinsam aktualisieren.").font(.footnote).foregroundStyle(.secondary)
                Button("Schön, los geht’s") {app.didReadChangelog()}.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(26)}.background(LoveBackground()).navigationTitle("Neu für euch")
        }.interactiveDismissDisabled()
    }
}
