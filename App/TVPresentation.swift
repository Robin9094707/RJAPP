import AVKit
import Observation
import SwiftUI
import UIKit

enum TVMode: String, CaseIterable, Identifiable {
    case ambient = "Unser Wir", moments = "Momente", cinema = "Kino", night = "Nacht"
    var id: String { rawValue }
}
@MainActor @Observable final class TVPresentation {
    static let shared = TVPresentation()
    var connected = false
    var mode: TVMode = .ambient
    var showInfo = false
    var app: AppState?
    var moments: [SharedRecord] = []
    var index = 0
    var slideshow = false
    var image: UIImage?
    var error: String?
    private var loadTask: Task<Void, Never>?
    private var slideTask: Task<Void, Never>?
    private var generation = UUID()
    func attach(app: AppState) { self.app = app }
    func clear() { generation = UUID(); app = nil; moments = []; image = nil; index = 0; slideshow = false; loadTask?.cancel(); slideTask?.cancel(); mode = .ambient }
    func loadMoments() async {
        guard let app else { return }
        do {
            let values = try await app.api.recordArchive(kind: .moment)
            guard self.app === app else { return }
            // Video moments remain available in the existing native evening playlist.
            moments = values.filter { $0.payload.mediaKind != "video" }
            index = min(index, max(0,moments.count-1)); showMoment(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func advance(_ delta: Int) {
        guard !moments.isEmpty else { return }
        index = (index + delta + moments.count) % moments.count; showMoment()
    }
    func showMoment() {
        loadTask?.cancel(); image = nil
        guard moments.indices.contains(index), let app else { return }
        let record = moments[index], operation = UUID(); generation = operation
        loadTask = Task { [weak self] in
            do {
                let file = try await app.api.momentImageFile(record)
                defer { try? FileManager.default.removeItem(at: file) }
                let decoded = await Task.detached(priority: .userInitiated) { MediaPicker.Coordinator.displayImage(file: file) }.value
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
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
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
                if tv.mode == .cinema, cinema.active {
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
        }.ignoresSafeArea().preferredColorScheme(.dark)
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
struct CinemaMiniPlayer: View {
    @State private var cinema = CinemaCoordinator.shared
    @State private var tv = TVPresentation.shared
    var body: some View {
        if cinema.active && !cinema.screenVisible && cinema.foreground {
            VStack(spacing: 5) {
                if cinema.provider == "youtube", !(tv.connected && tv.mode == .cinema) {
                    CinemaPlaybackSurface().frame(height: 200)
                }
                HStack {
                    Image(systemName: "play.tv.fill")
                    Text(cinema.title).font(.caption).lineLimit(1)
                    Spacer()
                    Button { Task { await cinema.control(cinema.playing ? "pause" : "play") } } label: { Image(systemName: cinema.playing ? "pause.fill" : "play.fill") }
                    Button { Task { await cinema.leave() } } label: { Image(systemName: "xmark") }
                }.padding(10)
            }.background(.ultraThinMaterial)
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
                    Text(tv.app?.partner?.displayName ?? "Schatzi").font(.system(size: geometry.size.width * 0.1,weight: .medium,design: .serif))
                    Text(tv.app?.partner?.presence?.statusMessage ?? "Ein Abend. Nur für uns.").foregroundStyle(.secondary).lineLimit(4)
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
