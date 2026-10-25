import SwiftUI

enum AppTab:Hashable {case home,map,together,moments,cinema,settings}
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
                if ProcessInfo.processInfo.arguments.contains("--preview-tv-dashboard") {TVPreviewView()}
                else if ProcessInfo.processInfo.arguments.contains("--preview-tv-wall") {TVPreviewView(wall:true)}
                else if ProcessInfo.processInfo.arguments.contains("--preview-cinema") {NavigationStack{CinemaView()}}
                else if ProcessInfo.processInfo.arguments.contains("--verify-video-audio") {VideoAudioVerificationView()}
                else if ProcessInfo.processInfo.arguments.contains("--preview-instant-gallery") {NavigationStack{InstantGalleryView()}.fullScreenCover(item:Binding(get:{appState.pendingPhotoRequest},set:{appState.pendingPhotoRequest=$0})){InstantCameraView(request:$0)}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-gallery") {NavigationStack{MomentsView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-moment-map") {NavigationStack{MomentsView(mapOnOpen:true)}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-poop") {NavigationStack{DropPoopView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-relationship") {NavigationStack{ScrollView{RelationshipHomeCard().padding(20)}.background(LoveBackground())}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-playlist") {NavigationStack{EveningPlaylistView()}}
                else if ProcessInfo.processInfo.arguments.contains("--preview-ai-summary") {NavigationStack{AIDaySummaryView()}}
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
    @State private var cinema = CinemaCoordinator.shared
    var body:some View {
        @Bindable var state=appState
        @Bindable var journey=appState.setupJourney
        TabView(selection:$state.selectedTab) {
            Tab("Wir",systemImage:"heart.fill",value:AppTab.home) {
                NavigationStack { HomeView() }.modifier(CinemaVideoInset(tab:.home))
            }
            Tab("Für uns",systemImage:"person.2.fill",value:AppTab.together) {
                NavigationStack { LoveHubView() }.modifier(CinemaVideoInset(tab:.together))
            }
            Tab("Erleben",systemImage:"sparkles",value:AppTab.moments) {
                NavigationStack { ExperienceView() }.modifier(CinemaVideoInset(tab:.moments))
            }
            Tab("Karte",systemImage:"location.fill",value:AppTab.map) {
                NavigationStack { PartnerMapView() }.modifier(CinemaVideoInset(tab:.map))
            }
            Tab("Kino",systemImage:"play.tv.fill",value:AppTab.cinema) {
                NavigationStack { CinemaView() }.modifier(CinemaVideoInset(tab:.cinema))
            }
        }
        .tint(LovePalette.pink)
        .tabBarMinimizeBehavior(.never)
        .tabViewBottomAccessory(isEnabled: cinema.active && cinema.provider == "plex" && !cinema.screenVisible && cinema.foreground && !cinema.miniPlayerHidden) { CinemaMiniPlayer() }
        .onChange(of:cinema.mediaID) { _,_ in cinema.miniPlayerHidden = false }
        .task { CinemaCoordinator.shared.configure(app: appState) }
        .onChange(of: appState.me?.id) { _, _ in CinemaCoordinator.shared.configure(app: appState) }
        .sheet(item:$state.notificationDestination,onDismiss:{appState.offerForegroundMoments()}) { route in NotificationDestinationView(route:route).id(route.id) }
        .sheet(isPresented:$state.showingEvening,onDismiss:{appState.didCloseEvening()}){NavigationStack{SharedJournalView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingEvening=false}}}}}
        .sheet(isPresented:$state.showingPartnerProfile){NavigationStack{PartnerProfileView()}.presentationDragIndicator(.visible)}
        .sheet(isPresented:$state.showingCountdowns){NavigationStack{CountdownHubView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingCountdowns=false}}}}}
        .sheet(isPresented:$state.showingHealthUpgrade,onDismiss:{appState.health.deferExpandedAccess();appState.offerForegroundMoments()}){HealthPermissionsUpgradeView()}
        .sheet(isPresented:$state.showingPoop){NavigationStack{DropPoopView(openComposer:appState.composingPoop).toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingPoop=false}}}}}
        .sheet(isPresented:$state.showingStatus){StatusEditorSheet()}
        .onChange(of:state.selectedTab){_,tab in dismissKeyboard(); if tab == .settings{state.selectedTab = .home;state.showingProfile=true}}
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
                Text("Eure Momente.\nAlles im Blick.").font(.system(size:38,weight:.medium,design:.serif))
                Text("Willkommen in RJ Love 4.2.1").font(.title3.bold())
                Label("Momente direkt öffnen und mit Bestätigung für beide löschen",systemImage:"trash")
                Label("Kino als eigener Tab und eine ausblendbare Plex-Leiste",systemImage:"play.tv.fill")
                Label("Klare Navigation ohne überlagerte AirPlay-Steuerung",systemImage:"rectangle.bottomthird.inset.filled")
                Label("Gemeinsam steuern, Schlaftimer und getrennte Medienkonten",systemImage:"person.2.fill")
                Label("Bark bringt dich direkt zur Nachricht oder zum Kommentar",systemImage:"bell.badge.fill")
                Label("Kritische Bark-Weckrufe und Wiederholung bis zur Bestätigung",systemImage:"alarm.fill")
                Label("Eigene Ruhezeiten mit Wochentagen und Nachtstatus",systemImage:"moon.zzz.fill")
                Label("Drop-Poop: das private Thronarchiv für euch zwei",systemImage:"toilet.fill")
                Label("Beziehungsmonate, Monatstage und Jahrestag im Blick",systemImage:"heart.circle.fill")
                Text("Original oder optional platzsparend teilen: Ihr entscheidet. Eure bisherigen Erinnerungen bleiben erhalten. Ortsmarkierungen werden nur mit den entsprechenden Freigaben gespeichert.").font(.subheadline).foregroundStyle(.secondary)
                Text("Unsere Beziehungsmonate und Drop-Poop könnt ihr über Startseite anpassen als eigene Karten hinzufügen. Neue Schnellzugriffe, Widgets und ein Kontrollzentrum-Button bringen euch direkt hin.").font(.footnote).foregroundStyle(.secondary)
                Button("Schön, los geht’s") {app.didReadChangelog()}.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(26)}.background(LoveBackground()).navigationTitle("Neu für euch")
        }.interactiveDismissDisabled()
    }
}

