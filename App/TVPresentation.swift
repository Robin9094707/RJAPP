import AVKit
import CoreImage
import ImageIO
import Observation
import SwiftUI
import UIKit

enum TVMode: String, Codable, CaseIterable, Identifiable {
    case ambient = "Unser Wir", dashboard = "Dashboard", moments = "Momente", wall = "Momentwand", cinema = "Kino", drawing = "Zusammen malen", game = "Tic-Tac-Toe", night = "Nacht"
    var id: String { rawValue }
    var networkID: String {
        switch self { case .ambient: return "ambient"; case .dashboard: return "dashboard"; case .moments: return "moments"; case .wall: return "wall"; case .cinema: return "cinema"; case .drawing: return "drawing"; case .game: return "game"; case .night: return "night" }
    }
    var symbol: String {
        switch self { case .ambient: return "heart.fill"; case .dashboard: return "rectangle.grid.2x2.fill"; case .moments: return "photo.fill"; case .wall: return "square.grid.3x3.fill"; case .cinema: return "play.tv.fill"; case .drawing: return "pencil.tip"; case .game: return "number"; case .night: return "moon.stars.fill" }
    }
}

/// True while TV views render as a scaled preview inside the phone UI. Live video and
/// camera surfaces are replaced by placeholders there, so they never run twice.
private struct LoveTVPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var loveTVPreview: Bool {
        get { self[LoveTVPreviewKey.self] }
        set { self[LoveTVPreviewKey.self] = newValue }
    }
}

/// A decoded slide and its tiny blurred backdrop, prepared off the main thread.
struct TVFrame: @unchecked Sendable {
    let image: UIImage
    let backdrop: UIImage?
}

enum TVImageDecoding {
    private static let context = CIContext(options: nil)
    /// Fully decodes now (not lazily at first draw), so slide changes never stutter on the main thread.
    static func display(file: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2560, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    /// A 72-pixel blurred version; scaled up it becomes a soft, cheap full-screen backdrop.
    static func backdrop(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let scale = 72.0 / Double(cg.width)
        let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return UIImage(cgImage: output)
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
    var showCaptions=true {didSet {saveLayout()}}
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
    /// The slide on screen. It stays visible until the next one is fully decoded, so there is never a black gap.
    var image: UIImage?
    var backdrop: UIImage?
    var imageID: String?
    var error: String?
    @ObservationIgnored private var preloaded: [String: TVFrame] = [:]
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var slideTask: Task<Void, Never>?
    private var generation = UUID()
    var currentMoment: SharedRecord? { imageID.flatMap { id in moments.first { $0.id == id } } }
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
        showCaptions=saved.showCaptions ?? true
    }
    func encodedLayout()->Data? {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(TVSavedLayout(mode:mode,theme:theme,widgets:widgets,includeOwnLocation:includeOwnLocation,showPartnerLocation:showPartnerLocation,wallCount:wallCount,fillPhotos:fillPhotos,showInfo:showInfo,sharedEnabled:sharedEnabled,columns:columns,slideSeconds:slideSeconds,cameraAutoLive:cameraAutoLive,showCaptions:showCaptions))
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
        layoutKey = ""; wallTask?.cancel(); wallImages = [:]; generation = UUID(); app = nil; moments = []; image = nil; backdrop = nil; imageID = nil; index = 0
        preloadTask?.cancel(); preloadTask = nil; preloaded = [:]
        slideshow = false; loadTask?.cancel(); slideTask?.cancel(); mode = .ambient
        theme = .light; widgets = [.clock,.mine,.partner,.location,.moments,.signals]
        includeOwnLocation = false; showPartnerLocation = true; wallCount = 6; fillPhotos = false; showInfo = false; sharedEnabled = true;columns=2;slideSeconds=15;cameraAutoLive=true;showCaptions=true
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
        loadTask?.cancel()
        guard moments.indices.contains(index), let app else { image = nil; backdrop = nil; imageID = nil; return }
        let record = moments[index], operation = UUID(); generation = operation
        if let frame = preloaded[record.id] { present(frame, id: record.id); preloadNeighbors(); return }
        loadTask = Task { [weak self] in
            do {
                let frame = try await Self.loadFrame(record, api: app.api)
                guard let self, !Task.isCancelled, self.generation == operation else { return }
                self.preloaded[record.id] = frame
                self.present(frame, id: record.id)
                self.preloadNeighbors()
            } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
        }
    }
    private func present(_ frame: TVFrame, id: String) {
        image = frame.image; backdrop = frame.backdrop; imageID = id; error = nil
    }
    /// Keeps the current and the next slide decoded, so the slideshow advances instantly.
    private func preloadNeighbors() {
        guard moments.count > 1, let app, moments.indices.contains(index) else { return }
        let next = moments[(index + 1) % moments.count]
        let keep: Set<String> = [moments[index].id, next.id, moments[(index - 1 + moments.count) % moments.count].id]
        preloaded = preloaded.filter { keep.contains($0.key) }
        guard preloaded[next.id] == nil else { return }
        preloadTask?.cancel()
        preloadTask = Task { [weak self] in
            guard let frame = try? await Self.loadFrame(next, api: app.api), !Task.isCancelled, let self, self.app === app else { return }
            self.preloaded[next.id] = frame
        }
    }
    nonisolated private static func loadFrame(_ record: SharedRecord, api: APIClient) async throws -> TVFrame {
        let file = try await api.momentImageFile(record)
        defer { try? FileManager.default.removeItem(at: file) }
        return try await Task.detached(priority: .userInitiated) {
            guard let image = TVImageDecoding.display(file: file) else { throw MediaError.unreadable }
            return TVFrame(image: image, backdrop: TVImageDecoding.backdrop(image))
        }.value
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
        let host = UIHostingController(rootView: LoveTVScreen())
        host.view.backgroundColor = .black
        window.rootViewController = host
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

// MARK: - The TV stage

struct LoveTVScreen: View {
    @State private var tv = TVPresentation.shared
    @State private var cinema = CinemaCoordinator.shared
    @Environment(\.loveTVPreview) private var preview
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black
                stage(size: size)
                    .id(stageID)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                if showsSignals { TVSignalOverlay(size: size) }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .animation(.smooth(duration: 0.8), value: stageID)
        }
        .modifier(TVScreenEnvironment(scheme: tv.mode == .dashboard && tv.theme == .light ? .light : .dark, preview: preview))
    }
    private var stageID: String {
        switch tv.mode {
        case .cinema: return cinema.active ? "cinema" : "cinema-idle"
        case .moments: return tv.image == nil ? "moments-waiting" : "moments"
        default: return tv.mode.networkID
        }
    }
    private var showsSignals: Bool { ![.cinema, .night, .drawing, .game].contains(tv.mode) }
    @ViewBuilder private func stage(size: CGSize) -> some View {
        switch tv.mode {
        case .dashboard:
            TVDashboard()
        case .wall:
            ZStack {
                TVAuroraBackdrop(theme: .dusk)
                TVMomentWall().padding(size.width * 0.025)
            }
        case .drawing, .game:
            HStack(spacing: 24) {
                if tv.mode == .drawing { TVDrawingSurface().aspectRatio(16.0/9.0,contentMode: .fit).padding(28) }
                else { TVGameBoard().padding(28) }
                TVSignalsCard().padding(20).frame(width: size.width*0.2)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(24)
            }.frame(width: size.width, height: size.height).background(Color(red:0.08,green:0.06,blue:0.12))
        case .cinema:
            if cinema.active {
                HStack(spacing: 0) {
                    cinemaSurface.frame(width: tv.showInfo ? size.width * 0.75 : size.width, height: size.height)
                    if tv.showInfo { TVInfoPanel().frame(width: size.width * 0.25, height: size.height) }
                }
            } else { TVAmbientStage(size: size, night: false) }
        case .moments:
            if tv.image != nil { TVMomentStage(size: size) } else { TVAmbientStage(size: size, night: false) }
        case .ambient:
            TVAmbientStage(size: size, night: false)
        case .night:
            TVAmbientStage(size: size, night: true)
        }
    }
    @ViewBuilder private var cinemaSurface: some View {
        if preview {
            ZStack {
                Color.black
                VStack(spacing: 18) {
                    Image(systemName: cinema.playing ? "play.tv.fill" : "pause.circle.fill").font(.system(size: 90))
                    Text(cinema.title).font(.system(size: 38, weight: .semibold)).lineLimit(2)
                }.foregroundStyle(.white.opacity(0.85)).padding(60)
            }
        } else { CinemaPlaybackSurface(external: true) }
    }
}

/// The external display owns its color scheme; a preview only adjusts its own subtree.
private struct TVScreenEnvironment: ViewModifier {
    let scheme: ColorScheme
    let preview: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if preview { content.environment(\.colorScheme, scheme) }
        else { content.ignoresSafeArea().preferredColorScheme(scheme) }
    }
}

/// Renders a TV view at 1280×720 and scales it into the available width.
struct TVScaledPreview<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            content()
                .environment(\.loveTVPreview, true)
                .frame(width: 1280, height: 720)
                .scaleEffect(geometry.size.width / 1280, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16, alignment: .topLeading)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        .allowsHitTesting(false)
    }
}

enum TVPalette {
    static let ambient: [Color] = [
        Color(red: 0.32, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.07, blue: 0.26), Color(red: 0.06, green: 0.05, blue: 0.16),
        Color(red: 0.42, green: 0.12, blue: 0.27), Color(red: 0.10, green: 0.05, blue: 0.14), Color(red: 0.17, green: 0.12, blue: 0.36),
        Color(red: 0.08, green: 0.04, blue: 0.10), Color(red: 0.30, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.14)
    ]
    static let light: [Color] = [
        Color(red: 0.99, green: 0.92, blue: 0.95), Color(red: 0.95, green: 0.93, blue: 0.99), Color(red: 0.89, green: 0.92, blue: 0.98),
        Color(red: 0.98, green: 0.94, blue: 0.97), Color(red: 0.97, green: 0.96, blue: 0.99), Color(red: 0.92, green: 0.91, blue: 0.99),
        Color(red: 0.93, green: 0.96, blue: 0.99), Color(red: 0.99, green: 0.93, blue: 0.95), Color(red: 0.99, green: 0.95, blue: 0.92)
    ]
    static let dark: [Color] = [
        Color(white: 0.02), Color(red: 0.06, green: 0.04, blue: 0.08), Color(white: 0.03),
        Color(red: 0.05, green: 0.03, blue: 0.06), Color(white: 0.01), Color(red: 0.04, green: 0.04, blue: 0.08),
        Color(white: 0.02), Color(red: 0.07, green: 0.03, blue: 0.05), Color(white: 0.02)
    ]
}

/// Slowly drifting backdrop for the TV. Frozen in previews and with Reduce Motion.
struct TVAuroraBackdrop: View {
    let theme: TVTheme
    @Environment(\.loveTVPreview) private var preview
    var body: some View {
        LoveAurora(colors: theme == .light ? TVPalette.light : theme == .dark ? TVPalette.dark : TVPalette.ambient, speed: 0.045, animated: !preview && theme != .dark)
    }
}

private struct TVAmbientStage: View {
    let size: CGSize
    let night: Bool
    @State private var tv = TVPresentation.shared
    @Environment(\.loveTVPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    private var names: String { "\(tv.app?.me?.displayName ?? "Du") & \(tv.app?.partner?.displayName ?? "Schatzi")" }
    private var nextCountdown: String? {
        let start = Calendar.current.startOfDay(for: .now)
        guard let next = tv.app?.records.filter({ $0.kind == .milestone && ($0.payload.startAt?.rjDate ?? .distantPast) >= start }).sorted(by: { ($0.payload.startAt ?? "") < ($1.payload.startAt ?? "") }).first,
              let date = next.payload.startAt?.rjDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days == 0 ? "Heute · " + (next.payload.title ?? "Unser Tag") : "Noch \(days) Tage · " + (next.payload.title ?? "Unser Tag")
    }
    var body: some View {
        ZStack {
            if night { Color.black }
            else {
                TVAuroraBackdrop(theme: .dusk)
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: size.height * 0.2, endRadius: size.width * 0.75)
            }
            TimelineView(.everyMinute) { context in
                let shift = night ? CGFloat(Calendar.current.component(.minute, from: context.date) % 3 - 1) * 14 : 0
                VStack(spacing: size.height * 0.032) {
                    if !night {
                        Image(systemName: "heart.fill").font(.system(size: min(92, size.height * 0.1)))
                            .foregroundStyle(LovePalette.heart)
                            .shadow(color: LovePalette.pink.opacity(0.55), radius: 28)
                            .scaleEffect(breathe ? 1.06 : 0.95)
                    }
                    Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.system(size: min(210, size.height * 0.27), weight: .ultraLight, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(night ? "Schlaf schön, ihr zwei." : names)
                        .font(.system(size: min(62, size.width * 0.038), weight: .medium, design: .serif))
                    if !night {
                        Text(tv.app?.partner?.presence?.visibleStatus ?? "Ein kleiner Platz. Nur für uns.")
                            .font(.system(size: min(32, size.width * 0.023))).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                        HStack(spacing: size.width * 0.014) {
                            TVChip(symbol: "calendar", text: context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)), size: size)
                            if let level = tv.app?.partner?.presence?.batteryLevel {
                                TVChip(symbol: "battery.100percent", text: (tv.app?.partner?.displayName ?? "Schatzi") + " · \(level) %", size: size)
                            }
                            if let nextCountdown { TVChip(symbol: "calendar.badge.heart", text: nextCountdown, size: size) }
                        }.padding(.top, size.height * 0.01)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(night ? Color(white: 0.16) : .white)
                .padding(size.width * 0.07)
                .frame(width: size.width, height: size.height)
                .offset(x: shift)
                .animation(.smooth(duration: 0.8), value: context.date)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { if !night && !reduceMotion && !preview { withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { breathe = true } } }
    }
}

private struct TVChip: View {
    let symbol: String
    let text: String
    let size: CGSize
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: max(14, min(24, size.width * 0.016)), weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, size.width * 0.014).padding(.vertical, size.height * 0.014)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

private struct TVMomentStage: View {
    let size: CGSize
    @State private var tv = TVPresentation.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let anchors: [UnitPoint] = [.topLeading, .bottomTrailing, .topTrailing, .bottomLeading, .center]
    var body: some View {
        ZStack {
            Color.black
            if let image = tv.image {
                ZStack {
                    if tv.fillPhotos {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: size.width, height: size.height).clipped()
                            .modifier(TVKenBurns(anchor: Self.anchors[tv.index % Self.anchors.count], duration: Double(tv.slideSeconds), active: tv.slideshow && !reduceMotion))
                    } else {
                        if let backdrop = tv.backdrop {
                            Image(uiImage: backdrop).resizable().interpolation(.high).scaledToFill()
                                .frame(width: size.width, height: size.height).clipped()
                                .overlay { Color.black.opacity(0.32) }
                        }
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: size.height * 0.018, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 34, y: 14)
                            .frame(maxWidth: size.width * 0.94, maxHeight: size.height * 0.9)
                            .modifier(TVKenBurns(anchor: Self.anchors[tv.index % Self.anchors.count], duration: Double(tv.slideSeconds), active: tv.slideshow && !reduceMotion))
                    }
                }
                .frame(width: size.width, height: size.height)
                .id(tv.imageID ?? "")
                .transition(.opacity)
            }
            if tv.showCaptions, let record = tv.currentMoment {
                TVMomentCaption(record: record, size: size).id("caption-" + record.id).transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 1.1), value: tv.imageID)
    }
}

private struct TVKenBurns: ViewModifier {
    let anchor: UnitPoint
    let duration: Double
    let active: Bool
    @State private var moved = false
    func body(content: Content) -> some View {
        content.scaleEffect(moved ? 1.07 : 1.0, anchor: anchor)
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: max(4, duration + 1.2))) { moved = true }
            }
    }
}

private struct TVMomentCaption: View {
    let record: SharedRecord
    let size: CGSize
    var body: some View {
        let title = [record.payload.title, record.payload.caption, record.payload.text].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let date = (record.payload.capturedAt ?? record.createdAt).rjDate
        if title != nil || date != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let title { Text(title).font(.system(size: size.height * 0.032, weight: .semibold)).lineLimit(2) }
                if let date { Text(date.formatted(date: .long, time: .omitted)).font(.system(size: size.height * 0.022)).foregroundStyle(.white.opacity(0.7)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, size.height * 0.032).padding(.vertical, size.height * 0.022)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: size.height * 0.03, style: .continuous))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: size.width * 0.5, alignment: .leading)
            .padding(size.height * 0.055)
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        }
    }
}

/// Partner signals rise large over the TV stage for a few seconds (never over a running film).
private struct TVSignalOverlay: View {
    let size: CGSize
    @State private var together = TVTogetherService.shared
    @State private var shown: TVSignal?
    @State private var lifted = false
    @State private var hearts = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if let shown {
                VStack(spacing: size.height * 0.025) {
                    Text(shown.emoji).font(.system(size: size.height * 0.2))
                        .shadow(color: LovePalette.pink.opacity(0.5), radius: 40)
                    Text(shown.owner == together.userID ? "Von dir" : "Von deinem Lieblingsmenschen")
                        .font(.system(size: size.height * 0.035, weight: .medium, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, size.height * 0.035).padding(.vertical, size.height * 0.018)
                        .glassEffect(.regular, in: Capsule())
                        .environment(\.colorScheme, .dark)
                }
                .scaleEffect(lifted || reduceMotion ? 1 : 0.55)
                .offset(y: lifted || reduceMotion ? 0 : size.height * 0.12)
                .opacity(lifted ? 1 : 0)
                LoveHeartBurst(trigger: hearts).scaleEffect(size.height / 300)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onChange(of: together.recentSignals.last?.id) { _, id in
            guard let id, let signal = together.state.signals.first(where: { $0.id == id }) else { return }
            present(signal)
        }
    }
    private func present(_ signal: TVSignal) {
        shown = signal
        lifted = false
        withAnimation(.spring(response: 0.6, dampingFraction: 0.66)) { lifted = true }
        if signal.symbol == "heart" || signal.symbol == "kiss" { hearts += 1 }
        let id = signal.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.4))
            guard shown?.id == id else { return }
            withAnimation(.easeIn(duration: 0.6)) { lifted = false }
            try? await Task.sleep(for: .seconds(0.7))
            if shown?.id == id { shown = nil }
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
                        .symbolEffect(.pulse, options: .repeating, isActive: cinema.playing)
                    VStack(alignment:.leading,spacing:2) {
                        Text(cinema.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(cinema.externalPlaybackActive || tv.connected ? "Auf dem Fernseher · Kino öffnen" : "Gemeinsames Kino öffnen").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.lovePress).accessibilityLabel("Kino öffnen: " + cinema.title)
            Button { Haptics.impact(.light); Task { await cinema.control(cinema.playing ? "pause" : "play") } } label: { Image(systemName:cinema.playing ? "pause.fill":"play.fill").contentTransition(.symbolEffect(.replace)).frame(width:44,height:44) }.accessibilityLabel(cinema.playing ? "Film pausieren":"Film fortsetzen")
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
                    if !(tv.connected && tv.mode == .cinema) { CinemaPlaybackSurface().frame(height:180).clipShape(RoundedRectangle(cornerRadius:18,style:.continuous)).padding(.horizontal,10).padding(.top,10) }
                    HStack {
                        Button { app.selectedTab = .cinema } label: { Label(cinema.title,systemImage:"play.rectangle").lineLimit(1).frame(maxWidth:.infinity,alignment:.leading) }
                        Button { Task { await cinema.control(cinema.playing ? "pause":"play") } } label: { Image(systemName:cinema.playing ? "pause.fill":"play.fill").contentTransition(.symbolEffect(.replace)).frame(width:44,height:44) }.accessibilityLabel("YouTube starten oder pausieren")
                        Button { Task { await cinema.leave() } } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("YouTube-Wiedergabe beenden")
                    }.font(.caption).padding(.horizontal,12)
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 8).padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct TVInfoPanel: View {
    @State private var tv = TVPresentation.shared
    @State private var cinema = CinemaCoordinator.shared
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: geometry.size.height * 0.035) {
                    Image(systemName: "heart.fill").foregroundStyle(LovePalette.heart)
                    Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.system(size: geometry.size.width * 0.18,weight: .ultraLight,design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(cinema.active ? "Unser gemeinsamer Film" : (tv.app?.partner?.displayName ?? "Schatzi")).font(.system(size: geometry.size.width * 0.09,weight: .medium,design: .serif))
                    if cinema.active {
                        Text(cinema.title).font(.headline).lineLimit(3)
                        PlexCinemaInformation(details: cinema.room?.details)
                        Label(cinema.playing ? "Zusammen mittendrin" : "Zeit für eine kleine Pause",systemImage: cinema.playing ? "play.fill" : "pause.fill")
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .glassEffect(.regular, in: Capsule())
                    } else { Text(tv.app?.partner?.presence?.statusMessage ?? "Ein Abend. Nur für uns.").foregroundStyle(.secondary).lineLimit(4) }
                    Spacer()
                    if let end = cinema.sleepUntil {
                        Label("Bis " + end.formatted(date: .omitted,time: .shortened),systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
                    }
                }.font(.system(size: geometry.size.width * 0.06)).padding(geometry.size.width * 0.1)
                    .frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .leading)
                    .animation(.smooth, value: context.date)
            }
        }
        .background { ZStack { TVAuroraBackdrop(theme: .dark); LinearGradient(colors: [LovePalette.plum.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom) } }
        .environment(\.colorScheme, .dark)
    }
}

/// Shows a short glass banner on the phone whenever a TV or projector connects.
struct TVConnectionBanner: View {
    @State private var tv = TVPresentation.shared
    @State private var visible = false
    var body: some View {
        VStack {
            if visible {
                Label("Fernseher verbunden · eure Bühne ist live", systemImage: "airplay.video")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .glassEffect(.regular.tint(LovePalette.violet.opacity(0.12)), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .animation(LoveMotion.spring, value: visible)
        .onChange(of: tv.connected) { _, connected in
            guard connected else { visible = false; return }
            Haptics.success()
            visible = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(3.2)); visible = false }
        }
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
