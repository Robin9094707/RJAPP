import SwiftUI

struct HomeShortcutsView:View {
    var shortcuts:[HomeShortcut]?=nil
    var title="Ganz schnell bei uns"
    var compact=false
    @Environment(AppState.self) private var app
    private var items:[HomeShortcut] {shortcuts ?? app.homeLayout.shortcuts}
    var body:some View {
        if !items.isEmpty {
            VStack(alignment:.leading,spacing:12){
                HStack{Text(title).font(.headline);Spacer();Text("Deine Auswahl").font(.caption2.weight(.medium)).foregroundStyle(.secondary)}
                LazyVGrid(columns:[GridItem(.adaptive(minimum:94),spacing:10)],spacing:10){
                    ForEach(items){shortcut in
                        Group {
                            if shortcut.action.immediate {Button{perform(shortcut.action)}label:{tile(shortcut)}}
                            else {NavigationLink{QuickActionDestination(action:shortcut.action)}label:{tile(shortcut)}}
                        }.buttonStyle(.lovePress).accessibilityIdentifier("shortcut-"+shortcut.action.rawValue)
                    }
                }
            }.accessibilityIdentifier("home-shortcuts")
        }
    }
    private func tile(_ shortcut:HomeShortcut)->some View {
        VStack(spacing:8){
            LoveIcon(symbol:shortcut.action.symbol,tint:LovePalette.pink,size:compact ? 30:38)
            Text(shortcut.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2).frame(minHeight:30)
        }.frame(maxWidth:.infinity,minHeight:compact ? 44:82).padding(10)
            .loveGlass(in:RoundedRectangle(cornerRadius:LoveMetrics.tileRadius,style:.continuous))
    }
    private func perform(_ action:HomeQuickAction) {switch action {case .recordFart:app.openFartRecorder(quick:true);case .status:app.showingStatus=true;case .partner:app.showingPartnerProfile=true;case .profile:app.showingProfile=true;default:break}}
}
struct QuickActionDestination:View {
    let action:HomeQuickAction
    var body:some View {switch action {
    case .wake:WakeComposerView()
    case .home:HomeView()
    case .together:LoveHubView()
    case .experience:ExperienceView()
    case .cinema:CinemaView()
    case .homeKit:HomeKitView()
    case .airplay:TVSettingsView()
    case .documents:DocumentsView()
    case .poop:DropPoopView()
    case .logPoop:DropPoopView(openComposer:true)
    case .momentMap:MomentsView(mapOnOpen:true)
    case .moments:MomentsView()
    case .captureMoment:MomentsView(captureOnOpen:true)
    case .instant:InstantGalleryView()
    case .studio:FartStudioView()
    case .playlist:EveningPlaylistView()
    case .journal:SharedJournalView()
    case .feed:SharedJournalView(showFeed:true)
    case .messenger:MessengerView()
    case .nearby:NearbyView()
    case .map:PartnerMapView()
    case .health:HealthDashboardView()
    case .countdowns:CountdownHubView()
    case .planner:PlannerView()
    case .ritual:EveningRitualView()
    case .notes:TogetherView()
    case .live:LiveActivitySettingsView()
    case .updates:AppUpdateView()
    case .aiSummary:AIDaySummaryView()
    case .status:StatusEditorView()
    case .partner:PartnerProfileView()
    case .profile:SettingsView()
    case .recordFart:FartRecorderView(autoStart:true)
    }}
}
