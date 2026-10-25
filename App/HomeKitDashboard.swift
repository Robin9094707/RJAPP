import HomeKit
import Observation
import SwiftUI

@MainActor @Observable final class HomeKitDashboard: NSObject, HMHomeManagerDelegate {
    static let shared = HomeKitDashboard()
    var homes: [HMHome] = []
    var enabled = UserDefaults.standard.bool(forKey: "rjlove.homekit.enabled")
    var selectedID = UserDefaults.standard.string(forKey: "rjlove.homekit.home") ?? "" {
        didSet { UserDefaults.standard.set(selectedID, forKey: "rjlove.homekit.home") }
    }
    var message: String?
    private var manager: HMHomeManager?
    var selected: HMHome? { homes.first { $0.uniqueIdentifier.uuidString == selectedID } }
    var cameras: [HMAccessory] { selected?.accessories.filter { !($0.cameraProfiles ?? []).isEmpty } ?? [] }
    func activate() {
        guard SigningProfile.current.homeKit else { message = "Die installierte Signatur gibt HomeKit nicht frei. Beim Signieren die HomeKit-Berechtigung erhalten."; return }
        enabled = true; UserDefaults.standard.set(true, forKey: "rjlove.homekit.enabled")
        if manager == nil { let value = HMHomeManager(); value.delegate = self; manager = value }
        reload()
    }
    func disable() {
        enabled = false; UserDefaults.standard.set(false, forKey: "rjlove.homekit.enabled")
        manager?.delegate = nil; manager = nil; homes = []; message = nil
    }
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { reload() }
    func homeManagerDidUpdateAuthorization(_ manager: HMHomeManager) { reload() }
    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { reload() }
    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { reload() }
    private func reload() {
        guard let manager else { return }
        guard manager.authorizationStatus.contains(.authorized) else {
            homes = []; message = "Home-Zugriff in den iOS-Einstellungen erlauben. Geteilte Häuser müssen bereits in Apple Home sichtbar sein."; return
        }
        homes = manager.homes; message = nil
        if selected == nil, let first = homes.first { selectedID = first.uniqueIdentifier.uuidString }
    }
}

struct HomeKitDashboardCard: View {
    @State private var home = HomeKitDashboard.shared
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { LoveSectionTitle("Unser Zuhause", subtitle: home.selected?.name ?? "Optional mit Apple Home verbinden"); Spacer(); Image(systemName: "house.fill").foregroundStyle(LovePalette.cyan) }
            if !home.enabled {
                Text("Wähle auch ein mit dir geteiltes Zuhause. Kameras bleiben bei Apple Home und werden nicht an euren RJ-Server übertragen.").font(.caption).foregroundStyle(.secondary)
                Button("HomeKit aktivieren", systemImage: "house.badge.checkmark") { home.activate() }.buttonStyle(.bordered)
            } else {
                if let message = home.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if !home.homes.isEmpty {
                    Picker("Zuhause", selection: $home.selectedID) { ForEach(home.homes, id: \.uniqueIdentifier) { Text($0.name).tag($0.uniqueIdentifier.uuidString) } }
                    if home.cameras.isEmpty { Text("In diesem Zuhause sind keine freigegebenen Kameras verfügbar.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array((expanded ? home.cameras : Array(home.cameras.prefix(2)))), id: \.uniqueIdentifier) { camera in HomeCameraTile(accessory: camera).id(camera.uniqueIdentifier) }
                    if home.cameras.count > 2 { Button(expanded ? "Weniger Kameras" : "Alle Kameras") { expanded.toggle() } }
                }
                Button("HomeKit deaktivieren", role: .destructive) { home.disable() }.font(.caption)
            }
        }.loveCard().task { if home.enabled { home.activate() } }
    }
}
@MainActor @Observable private final class HomeCameraFeed: NSObject, HMCameraStreamControlDelegate, HMCameraSnapshotControlDelegate {
    var source: HMCameraSource?
    var error: String?
    var live = false
    private var profile: HMCameraProfile?
    func attach(_ profile: HMCameraProfile?) {
        self.profile = profile
        profile?.snapshotControl?.delegate = self
        source = profile?.snapshotControl?.mostRecentSnapshot
        profile?.snapshotControl?.takeSnapshot()
    }
    func start() {
        guard let control = profile?.streamControl else { error = "Diese Kamera bietet keinen Live-Stream an."; return }
        error = nil; control.delegate = self; control.startStream()
    }
    func stop() {
        profile?.streamControl?.stopStream(); profile?.streamControl?.delegate = nil
        live = false; source = profile?.snapshotControl?.mostRecentSnapshot
    }
    func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) { source = cameraStreamControl.cameraStream; live = true; error = nil }
    func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl, didStopStreamWithError error: Error?) { live = false; source = profile?.snapshotControl?.mostRecentSnapshot; self.error = error?.localizedDescription }
    func cameraSnapshotControl(_ cameraSnapshotControl: HMCameraSnapshotControl, didTake snapshot: HMCameraSnapshot?, error: Error?) { if !live { source = snapshot }; self.error = error?.localizedDescription }
    func cameraSnapshotControlDidUpdateMostRecentSnapshot(_ cameraSnapshotControl: HMCameraSnapshotControl) { if !live { source = cameraSnapshotControl.mostRecentSnapshot } }
}
private struct HomeCameraTile: View {
    let accessory: HMAccessory
    @Environment(\.scenePhase) private var phase
    @State private var feed = HomeCameraFeed()
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label(accessory.name,systemImage: "web.camera.fill").font(.subheadline.bold()); Spacer(); Text(feed.live ? "LIVE" : "Vorschau").font(.caption2).foregroundStyle(.secondary) }
            ZStack {
                Color.black
                if let source = feed.source { HomeCameraSurface(source: source) }
                else { Image(systemName: "video.slash").foregroundStyle(.white.opacity(0.7)) }
            }.frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 18))
            Button(feed.live ? "Live-Ansicht beenden" : "Live ansehen",systemImage: feed.live ? "stop.circle" : "play.circle") { if feed.live { feed.stop() } else { feed.start() } }.font(.caption)
            if let error = feed.error { Text(error).font(.caption2).foregroundStyle(.secondary) }
        }.task { feed.attach(accessory.cameraProfiles?.first) }.onDisappear { feed.stop() }
            .onChange(of: phase) { _, value in if value != .active { feed.stop() } }
    }
}
private struct HomeCameraSurface: UIViewRepresentable {
    let source: HMCameraSource
    func makeUIView(context: Context) -> HMCameraView { let view = HMCameraView(); view.cameraSource = source; return view }
    func updateUIView(_ view: HMCameraView, context: Context) { view.cameraSource = source }
}
