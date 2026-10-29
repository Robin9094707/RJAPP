import SwiftUI

enum AppTab:Hashable {case home,map,together,moments,cinema,settings,shortcut(HomeQuickAction)}
struct RootView:View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var update=UpdateCoordinator.shared
    var body:some View {
        ZStack {
            LoveBackground()
            switch appState.phase {
            case .setup:ServerSetupView().transition(.opacity)
            case .restoring:LoveLaunchView(message:appState.connectionMessage).transition(.opacity)
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
            .animation(LoveMotion.gentle,value:appState.phase)
            .overlay{if update.requirement != nil && !appState.showingFartRecorder && appState.pendingQuickCapture == nil {UpdateRequiredView().transition(.opacity)}}
            .animation(LoveMotion.fade,value:update.requirement)
            .overlay{LoveSplashOverlay()}
            .task{await appState.activate()}
            .alert(item:Binding(get:{appState.alert},set:{appState.alert=$0})){Alert(title:Text($0.title),message:Text($0.message),dismissButton:.default(Text("OK")))}
    }
}
struct MainTabView:View {
    @Environment(AppState.self) private var appState
    @State private var cinema = CinemaCoordinator.shared
    @State private var extraDestination: HomeQuickAction?
    private func tabID(_ action:HomeQuickAction)->AppTab {
        switch action {case .home:return .home;case .map:return .map;case .together:return .together;case .experience:return .moments;case .cinema:return .cinema;default:return .shortcut(action)}
    }
    private var visibleTabs:[AppTab] { appState.homeLayout.tabs.map { tabID($0.action) } }
    var body:some View {
        @Bindable var state=appState
        @Bindable var journey=appState.setupJourney
        TabView(selection:$state.selectedTab) {
            ForEach(appState.homeLayout.tabs) { item in
                Tab(item.title,systemImage:item.action.symbol,value:tabID(item.action)) {
                    NavigationStack {
                        QuickActionDestination(action:item.action)
                            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button { appState.showingProfile=true } label:{Image(systemName:"person.crop.circle")} .accessibilityLabel("Profil und Einstellungen") } }
                    }.modifier(CinemaVideoInset(tab:tabID(item.action)))
                }
            }
        }
        .tint(LovePalette.pink)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: cinema.active && cinema.provider == "plex" && !cinema.screenVisible && cinema.foreground && !cinema.miniPlayerHidden) { CinemaMiniPlayer() }
        .onChange(of:cinema.mediaID) { _,_ in cinema.miniPlayerHidden = false }
        .overlay(alignment:.top) { TVConnectionBanner() }
        .task { CinemaCoordinator.shared.configure(app: appState); appState.acceptQuickCaptureRequest() }
        .task(id:appState.quickCaptureAttempt) {
            if appState.pendingQuickCapture != nil { extraDestination=nil; await appState.presentQuickCapture() }
        }
        .onChange(of:journey.presented) { _,shown in if !shown { appState.acceptQuickCaptureRequest() } }
        // An overlay, not a safe-area inset: the tab content never shifts while the recorder opens.
        .overlay(alignment:.top) {
            QuickCaptureFallbackButton(waiting:appState.pendingQuickCapture != nil && !appState.showingFartRecorder && !journey.presented) { appState.acceptQuickCaptureRequest() }
        }
        .onChange(of: appState.me?.id) { _, _ in CinemaCoordinator.shared.configure(app: appState) }
        .sheet(item:$state.notificationDestination,onDismiss:{appState.offerForegroundMoments()}) { route in NotificationDestinationView(route:route).id(route.id) }
        .sheet(isPresented:$state.showingEvening,onDismiss:{appState.didCloseEvening()}){NavigationStack{SharedJournalView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingEvening=false}}}}}
        .sheet(isPresented:$state.showingPartnerProfile){NavigationStack{PartnerProfileView()}.presentationDragIndicator(.visible)}
        .sheet(isPresented:$state.showingCountdowns){NavigationStack{CountdownHubView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingCountdowns=false}}}}}
        .sheet(isPresented:$state.showingHealthUpgrade,onDismiss:{appState.health.deferExpandedAccess();appState.offerForegroundMoments()}){HealthPermissionsUpgradeView()}
        .sheet(isPresented:$state.showingPoop){NavigationStack{DropPoopView(openComposer:appState.composingPoop).toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){state.showingPoop=false}}}}}
        .sheet(isPresented:$state.showingStatus){StatusEditorSheet()}
         .onChange(of:state.selectedTab) { _,tab in
            dismissKeyboard()
            if tab == .settings { state.showingProfile=true;state.selectedTab=visibleTabs.first ?? .home }
            else if !visibleTabs.contains(tab) {
                switch tab {case .cinema:extraDestination = .cinema;case .map:extraDestination = .map;case .together:extraDestination = .together;case .moments:extraDestination = .experience;case .home:break;case .shortcut(let action):extraDestination=action;case .settings:break}
                state.selectedTab=visibleTabs.first ?? .home
            }
        }
        .onChange(of:appState.homeLayout.tabs) { _,_ in if !visibleTabs.contains(state.selectedTab) { state.selectedTab=visibleTabs.first ?? .home } }
        .onAppear { if !visibleTabs.contains(state.selectedTab) { state.selectedTab=visibleTabs.first ?? .home } }
        .sheet(item:$extraDestination) { action in NavigationStack { QuickActionDestination(action:action).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fertig") { extraDestination=nil } } } } }
        .sheet(isPresented:$state.showingProfile) { NavigationStack { SettingsView().toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fertig") { state.showingProfile=false } } } }.presentationDragIndicator(.visible) }
        .sheet(isPresented:$state.showingFartRecorder,onDismiss:{appState.offerForegroundMoments()}){FartRecorderView(autoStart:appState.quickFartRecording)}
        .fullScreenCover(isPresented:$state.showingChangelog,onDismiss:{appState.offerForegroundMoments()}){WhatsNewView()}
        .sheet(item:$state.pendingSweet,onDismiss:{appState.offerForegroundMoments()}){SweetPlaybackView(record:$0)}
        .fullScreenCover(item:$state.pendingPhotoRequest,onDismiss:{appState.offerForegroundMoments()}){InstantCameraView(request:$0)}
        .fullScreenCover(isPresented:$journey.presented,onDismiss:{Task{_ = await appState.syncNow(showErrors:false)}}){SetupJourneyView()}
    }
}

/// Only appears when the emergency recorder could not open on its own within a moment
/// (for example while another sheet was still closing). A normal quick start never shows it.
private struct QuickCaptureFallbackButton:View {
    let waiting:Bool
    let open:()->Void
    @State private var visible=false
    var body:some View {
        ZStack {
            if visible {
                Button("Notfallaufnahme öffnen",systemImage:"cloud.fill",action:open)
                    .buttonStyle(.borderedProminent).tint(LovePalette.violet).padding(8).transition(.opacity)
            }
        }
        .animation(LoveMotion.fade,value:visible)
        .task(id:waiting) {
            guard waiting else { visible=false; return }
            try? await Task.sleep(for:.milliseconds(1600))
            if !Task.isCancelled { visible=true }
        }
    }
}
