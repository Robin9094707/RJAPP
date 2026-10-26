import AVKit
import Observation
import SwiftUI
import UIKit

enum TVMode: String, Codable, CaseIterable, Identifiable {
    case ambient = "Unser Wir", dashboard = "Dashboard", moments = "Momente", wall = "Momentwand", cinema = "Kino", drawing = "Zusammen malen", game = "Tic-Tac-Toe", night = "Nacht"
    var id: String { rawValue }
    var networkID: String {
        switch self { case .ambient: return "ambient"; case .dashboard: return "dashboard"; case .moments: return "moments"; case .wall: return "wall"; case .cinema: return "cinema"; case .drawing: return "drawing"; case .game: return "game"; case .night: return "night" }
    }
}
@MainActor @Observable final class TVPresentation {
    static let shared = TVPresentation()
    var connected = false
    var mode: TVMode = .ambient {
        didSet {
            saveLayout()
            if mode == .wall || mode == .dashboard { loadWall() }
            if ![.wall,.dashboard,.moments].contains(mode) { slideshow = false; slideTask?.cancel() }
            if sharedEnabled,!applyingSharedMode,!layoutKey.isEmpty,mode != oldValue {
                let value = mode.networkID
                Task { await TVTogetherService.shared.action("mode",values: ["mode":value]) }
            }
        }
    }
    private var applyingSharedMode = false
    private var applyingLayout = false
    var columns=2 {didSet {saveLayout()}}
    var slideSeconds=15 {didSet {saveLayout()}}
    var cameraAutoLive=true {didSet {saveLayout()}}
    func acceptRemote(_ mode: TVMode) {
        guard self.mode != mode else { return }
        applyingSharedMode = true; self.mode = mode; applyingSharedMode = false
        if [.moments,.wall,.dashboard].contains(mode) { Task { await self.loadMoments() } }
    }
    var showInfo = false { didSet { saveLayout() } }
    var theme: TVTheme = .light { didSet { saveLayout() } }
    var widgets: [TVWidgetKind] = [.clock,.mine,.partner,.location,.moments,.signals] { didSet { saveLayout() } }
    var includeOwnLocation = false { didSet { saveLayout() } }
    var showPartnerLocation = true { didSet { saveLayout() } }
    var wallCount = 6 { didSet { saveLayout(); loadWall() } }
    var fillPhotos = false { didSet { saveLayout() } }
    var sharedEnabled = true { didSet { saveLayout() } }
    var wallImages: [String:UIImage] = [:]
    private var wallTask: Task<Void,Never>?
    private var layoutKey = ""
    var app: AppState?
    var moments: [SharedRecord] = []
    var index = 0
    var slideshow = false
    var image: UIImage?
    var error: String?
    private var loadTask: Task<Void, Never>?
    private var slideTask: Task<Void, Never>?
    private var generation = UUID()
    func attach(app: AppState) {
        self.app = app
        applyingSharedMode = true; applyingLayout=true;defer { applyingSharedMode = false;applyingLayout=false }
        layoutKey = "rjlove.tv.layout." + CinemaCoordinator.shared.namespace
        if let data=UserDefaults.standard.data(forKey:layoutKey) {restoreLayout(data)}
    }
    func restoreLayout(_ data:Data) {
        guard let saved=try? JSONDecoder().decode(TVSavedLayout.self,from:data) else {return}
        let previous=applyingLayout;applyingLayout=true
        let remote=applyingSharedMode;applyingSharedMode=true
        defer {applyingLayout=previous;applyingSharedMode=remote;saveLayout()}
        mode=saved.mode;theme=saved.theme;widgets=saved.widgets.isEmpty ? [.clock] : saved.widgets.reduce(into:[TVWidgetKind]()) {if !$0.contains($1) {$0.append($1)}}
        includeOwnLocation=saved.includeOwnLocation;showPartnerLocation=saved.showPartnerLocation
        wallCount=[4,6,9,12].contains(saved.wallCount) ? saved.wallCount : 6
        fillPhotos=saved.fillPhotos;showInfo=saved.showInfo;sharedEnabled=saved.sharedEnabled
        columns=[2,3].contains(saved.columns ?? 2) ? saved.columns ?? 2 : 2
        slideSeconds=[5,10,15,30,60].contains(saved.slideSeconds ?? 15) ? saved.slideSeconds ?? 15 : 15
        cameraAutoLive=saved.cameraAutoLive ?? true
    }
    func encodedLayout()->Data? {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(TVSavedLayout(mode:mode,theme:theme,widgets:widgets,includeOwnLocation:includeOwnLocation,showPartnerLocation:showPartnerLocation,wallCount:wallCount,fillPhotos:fillPhotos,showInfo:showInfo,sharedEnabled:sharedEnabled,columns:columns,slideSeconds:slideSeconds,cameraAutoLive:cameraAutoLive))
    }
    private func saveLayout() {
        guard !layoutKey.isEmpty,!applyingLayout else {return}
        if let data=encodedLayout() {UserDefaults.standard.set(data,forKey:layoutKey)}
    }

    func loadWall() {
        wallTask?.cancel()
        guard let app,!moments.isEmpty else { return }
        let wanted = (0..<min(wallCount,moments.count)).map { moments[(index+$0)%moments.count] }
        let ids = Set(wanted.map(\.id)); wallImages = wallImages.filter { ids.contains($0.key) }
        wallTask = Task { [weak self] in
            for record in wanted {
                guard let self,!Task.isCancelled,self.app === app else { return }
                if self.wallImages[record.id] != nil { continue }
                if let encoded = record.payload.posterBase64 ?? record.payload.imageBase64,
                   let image = await MomentPreviewCache.shared.decode(encoded,key: "tv-wall-"+record.id) {
                    self.wallImages[record.id] = image; continue
                }
                do {
                    let file = try await app.api.momentImageFile(record)
                    defer { try? FileManager.default.removeItem(at: file) }
                    let data = MediaPicker.Coordinator.poster(file: file)
                    if let data,let image = UIImage(data: data),!Task.isCancelled { self.wallImages[record.id] = image }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }
    }
    func clear() {
        layoutKey = ""; wallTask?.cancel(); wallImages = [:]; generation = UUID(); app = nil; moments = []; image = nil; index = 0
        slideshow = false; loadTask?.cancel(); slideTask?.cancel(); mode = .ambient
        theme = .light; widgets = [.clock,.mine,.partner,.location,.moments,.signals]
        includeOwnLocation = false; showPartnerLocation = true; wallCount = 6; fillPhotos = false; showInfo = false; sharedEnabled = true;columns=2;slideSeconds=15;cameraAutoLive=true
    }
    func loadMoments() async {
        guard let app else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            moments = app.records.filter { $0.kind == .moment && $0.payload.mediaKind != "video" }
            index = 0; showMoment(); loadWall(); return
        }
        #endif
        do {
            let values = try await app.api.recordArchive(kind: .moment)
            guard self.app === app else { return }
            // Video moments remain available in the existing native evening playlist.
            moments = values.filter { $0.payload.mediaKind != "video" }
            index = min(index, max(0,moments.count-1)); showMoment(); loadWall(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func advance(_ delta: Int) {
        guard !moments.isEmpty else { return }
        index = (index + delta + moments.count) % moments.count; showMoment(); loadWall()
    }
    func showMoment() {
        loadTask?.cancel(); image = nil
        guard moments.indices.contains(index), let app else { return }
        let record = moments[index], operation = UUID(); generation = operation
        loadTask = Task { [weak self] in
            do {
                let file = try await app.api.momentImageFile(record)
                defer { try? FileManager.default.removeItem(at: file) }
                let decoded = MediaPicker.Coordinator.displayImage(file: file)
                guard let self, !Task.isCancelled, self.generation == operation else { return }
                self.image = decoded
            } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
        }
    }
    func toggleSlideshow() {
        slideshow.toggle(); slideTask?.cancel()
        guard slideshow else { return }
        slideTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(self?.slideSeconds ?? 15)) } catch { return }
                guard let self, self.slideshow else { return }; self.advance(1)
            }
        }
    }
}

final class LoveExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: LoveTVScreen())
        window.backgroundColor = .black; window.isHidden = false
        self.window = window; TVPresentation.shared.connected = true; UIApplication.shared.isIdleTimerDisabled = true
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true; window = nil; TVPresentation.shared.connected = false; UIApplication.shared.isIdleTimerDisabled = false
    }
    func sceneDidBecomeActive(_ scene: UIScene) { TVPresentation.shared.connected = true }
}

struct CinemaNativeSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    var controls = true
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController(); controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = controls; controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player; controller.showsPlaybackControls = controls }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
struct CinemaAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.prioritizesVideoDevices = true; view.tintColor = .systemPink; return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
struct CinemaPlaybackSurface: View {
    @State private var cinema = CinemaCoordinator.shared
    var external = false
    var body: some View {
        Group {
            if cinema.provider == "youtube" { CinemaYouTubeSurface(engine: cinema.youtube) }
            else if let player = cinema.player { CinemaNativeSurface(player: player, controls: !external) }
            else { ContentUnavailableView("Euer Kino wartet", systemImage: "play.tv", description: Text("Wähle auf deinem iPhone ein Video aus.")) }
        }.background(.black)
    }
}
struct LoveTVScreen: View {
    @State private var tv = TVPresentation.shared
    @State private var cinema = CinemaCoordinator.shared
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if tv.mode == .dashboard {
                    TVDashboard()
                } else if tv.mode == .wall {
                    TVMomentWall().padding(24)
                } else if tv.mode == .drawing || tv.mode == .game {
                    HStack(spacing: 24) {
                        if tv.mode == .drawing { TVDrawingSurface().aspectRatio(16.0/9.0,contentMode: .fit).padding(28) }
                        else { TVGameBoard().padding(28) }
                        TVSignalsCard().frame(width: geometry.size.width*0.18).padding(24)
                    }.background(Color(red:0.08,green:0.06,blue:0.12))
                } else if tv.mode == .cinema, cinema.active {
                    HStack(spacing: 0) {
                        CinemaPlaybackSurface(external: true)
                            .frame(width: tv.showInfo ? geometry.size.width * 0.75 : geometry.size.width, height: geometry.size.height)
                        if tv.showInfo {
                            TVInfoPanel().frame(width: geometry.size.width * 0.25, height: geometry.size.height)
                        }
                    }
                } else if tv.mode == .moments, let image = tv.image {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ambient(size: geometry.size)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.ignoresSafeArea().preferredColorScheme(tv.mode == .dashboard && tv.theme == .light ? .light : .dark)
    }
    private func ambient(size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: size.height * 0.045) {
                if tv.mode != .night { Image(systemName: "heart.fill").font(.system(size: min(100,size.height*0.12))).foregroundStyle(LovePalette.pink) }
                Text(context.date, style: .time).font(.system(size: min(180,size.height*0.24), weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text(tv.mode == .night ? "Schlaf schön, ihr zwei." : "\(tv.app?.me?.displayName ?? "Du") & \(tv.app?.partner?.displayName ?? "Schatzi")")
                    .font(.system(size: min(64,size.width*0.04),weight: .medium,design: .serif)).multilineTextAlignment(.center)
                if tv.mode != .night {
                    Text(tv.app?.partner?.presence?.statusMessage ?? "Ein kleiner Platz. Nur für uns.")
                        .font(.system(size: min(34,size.width*0.025))).foregroundStyle(.secondary).lineLimit(3)
                    HStack(spacing: 40) {
                        Label(context.date.formatted(date: .complete,time: .omitted),systemImage: "calendar")
                        if let level = tv.app?.partner?.presence?.batteryLevel { Label("\(level) %",systemImage: "battery.100percent") }
                    }.font(.system(size: min(26,size.width*0.018))).foregroundStyle(.secondary)
                }
            }.padding(size.width*0.08).frame(maxWidth: .infinity,maxHeight: .infinity)
                .foregroundStyle(tv.mode == .night ? Color(white: 0.16) : .white)
                .offset(x: tv.mode == .night ? CGFloat(Calendar.current.component(.minute,from:context.date)%3-1)*14 : 0)
        }
    }
}
/// Native tab accessory: it reserves space above the tab bar instead of covering it.
struct CinemaMiniPlayer: View {
    @Environment(AppState.self) private var app
    @State private var cinema = CinemaCoordinator.shared
    @State private var tv = TVPresentation.shared
    var body: some View {
        HStack(spacing: 10) {
            Button { app.selectedTab = .cinema } label: {
                HStack(spacing: 10) {
                    Image(systemName: cinema.externalPlaybackActive || tv.connected ? "airplay.video" : "film.fill").foregroundStyle(LovePalette.violet)
                    VStack(alignment:.leading,spacing:2) {
                        Text(cinema.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(cinema.externalPlaybackActive || tv.connected ? "Auf dem Fernseher · Kino öffnen" : "Gemeinsames Kino öffnen").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Kino öffnen: " + cinema.title)
            Button { Task { await cinema.control(cinema.playing ? "pause" : "play") } } label: { Image(systemName:cinema.playing ? "pause.fill":"play.fill").frame(width:44,height:44) }.accessibilityLabel(cinema.playing ? "Film pausieren":"Film fortsetzen")
            Button { cinema.miniPlayerHidden = true } label: { Image(systemName:"chevron.down").frame(width:44,height:44) }.accessibilityLabel("Plex-Leiste ausblenden, Wiedergabe fortsetzen")
        }.padding(.horizontal,12).accessibilityIdentifier("cinema-tab-accessory")
    }
}
/// The YouTube player stays visible, inside the selected tab's safe area.
struct CinemaVideoInset: ViewModifier {
    @Environment(AppState.self) private var app
    @State private var cinema = CinemaCoordinator.shared
    @State private var tv = TVPresentation.shared
    let tab: AppTab
    func body(content: Content) -> some View {
        content.safeAreaInset(edge:.bottom,spacing:0) {
            if app.selectedTab == tab && cinema.active && cinema.provider == "youtube" && !cinema.screenVisible && cinema.foreground {
                VStack(spacing:0) {
                    if !(tv.connected && tv.mode == .cinema) { CinemaPlaybackSurface().frame(height:180) }
                    HStack {
                        Button { app.selectedTab = .cinema } label: { Label(cinema.title,systemImage:"play.rectangle").lineLimit(1).frame(maxWidth:.infinity,alignment:.leading) }
                        Button { Task { await cinema.control(cinema.playing ? "pause":"play") } } label: { Image(systemName:cinema.playing ? "pause.fill":"play.fill").frame(width:44,height:44) }.accessibilityLabel("YouTube starten oder pausieren")
                        Button { Task { await cinema.leave() } } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("YouTube-Wiedergabe beenden")
                    }.font(.caption).padding(.horizontal,12)
                }.background(.regularMaterial)
            }
        }
    }
}

struct TVInfoPanel: View {
    @State private var tv = TVPresentation.shared
    @State private var cinema = CinemaCoordinator.shared
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: geometry.size.height * 0.04) {
                    Image(systemName: "heart.fill").foregroundStyle(LovePalette.pink)
                    Text(context.date, style: .time).font(.system(size: geometry.size.width * 0.17,weight: .ultraLight,design: .rounded)).monospacedDigit()
                    Text(cinema.active ? "Unser gemeinsamer Film" : (tv.app?.partner?.displayName ?? "Schatzi")).font(.system(size: geometry.size.width * 0.1,weight: .medium,design: .serif))
                    if cinema.active {
                        Text(cinema.title).font(.headline).lineLimit(3)
                        PlexCinemaInformation(details: cinema.room?.details)
                        Label(cinema.playing ? "Zusammen mittendrin" : "Zeit für eine kleine Pause",systemImage: cinema.playing ? "play.fill" : "pause.fill").foregroundStyle(.secondary)
                    } else { Text(tv.app?.partner?.presence?.statusMessage ?? "Ein Abend. Nur für uns.").foregroundStyle(.secondary).lineLimit(4) }
                    Spacer()
                    if let end = cinema.sleepUntil {
                        Label("Bis " + end.formatted(date: .omitted,time: .shortened),systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
                    }
                    Text(cinema.title).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }.font(.system(size: geometry.size.width * 0.06)).padding(geometry.size.width * 0.1)
                    .frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .leading)
            }
        }.background(Color(white: 0.025))
    }
}

#if DEBUG
struct TVPreviewView: View {
    @Environment(AppState.self) private var app
    var wall = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let width = min(geometry.size.width,geometry.size.height*16/9)
                LoveTVScreen().frame(width: 1280,height: 720)
                    .scaleEffect(width/1280)
                    .frame(width: width,height: width*9/16)
                    .position(x: geometry.size.width/2,y: geometry.size.height/2)
            }
        }.task {
            CinemaCoordinator.shared.configure(app: app)
            TVPresentation.shared.sharedEnabled = false
            TVPresentation.shared.mode = wall ? .wall : .dashboard
            await TVPresentation.shared.loadMoments()
        }
    }
}
#endif

