import AVFoundation
import HomeKit
import Observation
import SwiftUI

@MainActor @Observable final class HomeKitDashboard: NSObject, HMHomeManagerDelegate {
    static let shared = HomeKitDashboard()
    var homes: [HMHome] = []
    var enabled = UserDefaults.standard.bool(forKey:"rjlove.homekit.enabled")
    var selectedID = UserDefaults.standard.string(forKey:"rjlove.homekit.home") ?? "" {
        didSet { UserDefaults.standard.set(selectedID,forKey:"rjlove.homekit.home"); if oldValue != selectedID { HomeCameraSessions.shared.stopAll() } }
    }
    var cameraID = UserDefaults.standard.string(forKey:"rjlove.homekit.camera") ?? "" {
        didSet { UserDefaults.standard.set(cameraID,forKey:"rjlove.homekit.camera") }
    }
    var message: String?
    private var manager: HMHomeManager?
    var selected: HMHome? { homes.first { $0.uniqueIdentifier.uuidString == selectedID } }
    var cameras: [HMAccessory] { selected?.accessories.filter { !($0.cameraProfiles ?? []).isEmpty } ?? [] }
    var selectedCamera: HMAccessory? { cameras.first { $0.uniqueIdentifier.uuidString == cameraID } ?? cameras.first }
    func activate() {
        guard SigningProfile.current.homeKit else { message="Die installierte Signatur gibt HomeKit nicht frei. Beim Signieren die HomeKit-Berechtigung erhalten.";return }
        enabled=true;UserDefaults.standard.set(true,forKey:"rjlove.homekit.enabled")
        if manager == nil { let value=HMHomeManager();value.delegate=self;manager=value }
        reload()
    }
    func restorePreferences() {
        let defaults=UserDefaults.standard
        selectedID=defaults.string(forKey:"rjlove.homekit.home") ?? ""
        cameraID=defaults.string(forKey:"rjlove.homekit.camera") ?? ""
        if defaults.bool(forKey:"rjlove.homekit.enabled") { activate() } else { disable() }
    }
    func disable() {
        HomeCameraSessions.shared.stopAll()
        enabled=false;UserDefaults.standard.set(false,forKey:"rjlove.homekit.enabled")
        manager?.delegate=nil;manager=nil;homes=[];message=nil
    }
    func homeManagerDidUpdateHomes(_ manager:HMHomeManager) { reload() }
    func homeManagerDidUpdateAuthorization(_ manager:HMHomeManager) { reload() }
    func homeManager(_ manager:HMHomeManager,didAdd home:HMHome) { reload() }
    func homeManager(_ manager:HMHomeManager,didRemove home:HMHome) { reload() }
    private func reload() {
        guard let manager else { return }
        guard manager.authorizationStatus.contains(.authorized) else {
            HomeCameraSessions.shared.stopAll();homes=[]
            message="Erlaube Home-Zugriff in iOS. Für die Kamera deines Gegenübers muss das Zuhause mit deinem Apple-Account in Apple Home geteilt sein.";return
        }
        homes=manager.homes;message=nil
        if selected == nil,let first=homes.first { selectedID=first.uniqueIdentifier.uuidString }
        if selectedCamera == nil { cameraID="" }
    }
}

struct HomeKitDashboardCard:View {
    @State private var home=HomeKitDashboard.shared
    @State private var confirmingDisable=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                LoveSectionTitle("Unser Zuhause",subtitle:home.selected?.name ?? "Dein Apple Home in RJ Love")
                Menu {
                    NavigationLink("Zuhause, Geräte & Szenen",destination:HomeKitView())
                    if home.enabled { Button("HomeKit deaktivieren",systemImage:"power",role:.destructive) { confirmingDisable=true } }
                } label:{Image(systemName:"ellipsis.circle").frame(width:44,height:44)}.accessibilityLabel("HomeKit-Optionen")
            }
            if !home.enabled {
                Text(home.message ?? "Kameras aus deinem eigenen oder geteilten Apple Home. Live-Bilder bleiben bei HomeKit.").font(.subheadline).foregroundStyle(.secondary)
                Button("Mit Apple Home verbinden",systemImage:"house.fill") { home.activate() }.buttonStyle(.bordered)
            } else {
                if let message=home.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if !home.homes.isEmpty {
                    Picker("Zuhause",selection:$home.selectedID) { ForEach(home.homes,id:\.uniqueIdentifier) { Text($0.name).tag($0.uniqueIdentifier.uuidString) } }
                    if let camera=home.selectedCamera {
                        HomeCameraTile(accessory:camera).id(camera.uniqueIdentifier)
                    } else { Label("Keine freigegebene Kamera in diesem Zuhause",systemImage:"video.slash").font(.caption).foregroundStyle(.secondary) }
                    NavigationLink("Alle Kameras, Geräte & Szenen",destination:HomeKitView()).font(.subheadline.weight(.semibold))
                }
            }
        }.loveCard().task { if home.enabled { home.activate() } }
        .confirmationDialog("HomeKit in RJ Love deaktivieren?",isPresented:$confirmingDisable,titleVisibility:.visible) {
            Button("HomeKit deaktivieren",role:.destructive) { home.disable() }
            Button("Abbrechen",role:.cancel) {}
        } message:{Text("Live-Bild und Sprechen werden beendet. Dein Apple-Zuhause und seine Freigaben bleiben erhalten.")}
    }
}

@MainActor final class HomeCameraSessions {
    static let shared=HomeCameraSessions()
    private var feeds:[UUID:HomeCameraFeed]=[:]
    func feed(for accessory:HMAccessory)->HomeCameraFeed {
        if let feed=feeds[accessory.uniqueIdentifier] { return feed }
        let feed=HomeCameraFeed(profile:accessory.cameraProfiles?.first);feeds[accessory.uniqueIdentifier]=feed;return feed
    }
    func stopAll() { for feed in feeds.values { feed.stop() } }
}

@MainActor @Observable final class HomeCameraFeed:NSObject,HMCameraStreamControlDelegate,HMCameraSnapshotControlDelegate {
    var source:HMCameraSource?
    var error:String?
    var live=false
    var connecting=false
    var listening=false
    var speaking=false
    var changingAudio=false
    var canSpeak:Bool { profile?.speakerControl != nil }
    private let profile:HMCameraProfile?
    private var viewers:Set<UUID>=[]
    private var timeout:Task<Void,Never>?
    init(profile:HMCameraProfile?) { self.profile=profile;super.init() }
    func retain(_ id:UUID,autoplay:Bool) {
        viewers.insert(id)
        profile?.snapshotControl?.delegate=self
        if !live { source=profile?.snapshotControl?.mostRecentSnapshot;profile?.snapshotControl?.takeSnapshot() }
        if autoplay { start() }
    }
    func release(_ id:UUID) {
        viewers.remove(id)
        if viewers.isEmpty { stop();profile?.snapshotControl?.delegate=nil }
    }
    func start() {
        guard !live,!connecting else { return }
        guard let control=profile?.streamControl else { error="Diese Kamera bietet keinen Live-Stream an.";return }
        guard HomeKitDashboard.shared.enabled else { return }
        connecting=true;error=nil;control.delegate=self;control.startStream()
        timeout?.cancel();timeout=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(20)) } catch { return }
            guard let self,self.connecting else { return }
            self.stop();self.error="Die Kamera antwortet nicht. Prüfe Home-Freigabe, Netzwerk und die Zahl gleichzeitiger Streams."
        }
    }
    func stop() {
        timeout?.cancel();timeout=nil
        profile?.streamControl?.cameraStream?.updateAudioStreamSetting(.muted) { _ in }
        profile?.streamControl?.delegate=nil;profile?.streamControl?.stopStream()
        live=false;connecting=false;listening=false;speaking=false;changingAudio=false
        source=profile?.snapshotControl?.mostRecentSnapshot
    }
    func audio(listen:Bool,talk:Bool) async {
        guard !changingAudio,live,let stream=profile?.streamControl?.cameraStream else { return }
        changingAudio=true;defer { changingAudio=false }
        if talk {
            guard canSpeak else {error="Diese Kamera unterstützt kein Sprechen.";return}
            guard await AVAudioApplication.requestRecordPermission() else {error="Erlaube den Mikrofonzugriff in den iOS-Einstellungen, um zu sprechen.";return}
        }
        guard live,profile?.streamControl?.cameraStream === stream,UIApplication.shared.applicationState == .active else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                stream.updateAudioStreamSetting(talk ? .bidirectionalAudioAllowed : listen ? .incomingAudioAllowed : .muted) { issue in
                    if let issue { continuation.resume(throwing:issue) } else { continuation.resume() }
                }
            }
            guard live,profile?.streamControl?.cameraStream === stream else { return }
            listening=listen || talk;speaking=talk;error=nil
        } catch { self.error=error.localizedDescription }
    }
    func cameraStreamControlDidStartStream(_ cameraStreamControl:HMCameraStreamControl) {
        guard !viewers.isEmpty,HomeKitDashboard.shared.enabled else { stop();return }
        timeout?.cancel();source=cameraStreamControl.cameraStream;live=true;connecting=false;error=nil
        cameraStreamControl.cameraStream?.updateAudioStreamSetting(.muted) { _ in }
    }
    func cameraStreamControl(_ control:HMCameraStreamControl,didStopStreamWithError issue:Error?) {
        timeout?.cancel();live=false;connecting=false;speaking=false;listening=false;source=profile?.snapshotControl?.mostRecentSnapshot;error=issue?.localizedDescription
    }
    func cameraSnapshotControl(_ control:HMCameraSnapshotControl,didTake snapshot:HMCameraSnapshot?,error:Error?) { if !live {source=snapshot;self.error=error?.localizedDescription} }
    func cameraSnapshotControlDidUpdateMostRecentSnapshot(_ control:HMCameraSnapshotControl) { if !live {source=control.mostRecentSnapshot} }
}

struct HomeCameraTile:View {
    let accessory:HMAccessory
    var autoplay=false
    var external=false
    @Environment(\.scenePhase) private var phase
    @State private var viewer=UUID()
    @State private var fullscreen=false
    private var feed:HomeCameraFeed { HomeCameraSessions.shared.feed(for:accessory) }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label(accessory.name,systemImage:"web.camera.fill").font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text(feed.live ? "LIVE" : feed.connecting ? "Verbindet …" : "Vorschau").font(.caption2.bold()).foregroundStyle(feed.live ? .green : .secondary)
            }
            cameraSurface(feed:feed).frame(maxWidth:.infinity).frame(height:external ? nil : 190).frame(maxHeight:external ? .infinity : nil).clipShape(RoundedRectangle(cornerRadius:18))
            if !external {
                cameraControls(feed:feed)
                Button("Vollbild",systemImage:"arrow.up.left.and.arrow.down.right") { fullscreen=true }.font(.caption).buttonStyle(.bordered)
            }
            if let error=feed.error { Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
        }.task { feed.retain(viewer,autoplay:autoplay) }.onDisappear { feed.release(viewer) }
        .onChange(of:phase) { _,value in if value != .active { feed.stop() } else if autoplay { feed.start() } }
        .fullScreenCover(isPresented:$fullscreen) { HomeCameraFullscreen(accessory:accessory,feed:feed) }
    }
}
private struct HomeCameraFullscreen:View {
    let accessory:HMAccessory
    let feed:HomeCameraFeed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var viewer=UUID()
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraSurface(feed:feed).ignoresSafeArea(edges:.horizontal)
        }.safeAreaInset(edge:.top) {
            HStack {Text(accessory.name).font(.headline);Spacer();Button("Fertig",systemImage:"xmark") { dismiss() }}.padding().background(.ultraThinMaterial)
        }.safeAreaInset(edge:.bottom) {
            VStack(spacing:10) { cameraControls(feed:feed);if let error=feed.error {Text(error).font(.caption)} }.padding().frame(maxWidth:.infinity).background(.ultraThinMaterial)
        }.preferredColorScheme(.dark).task {feed.retain(viewer,autoplay:true)}.onDisappear {feed.release(viewer);Task { await feed.audio(listen:false,talk:false) }}
        .onChange(of:phase) { _,phase in if phase != .active {feed.stop()} }
    }
}
@MainActor @ViewBuilder private func cameraSurface(feed:HomeCameraFeed)->some View {
    ZStack {
        Color.black
        if let source=feed.source { HomeCameraSurface(source:source) }
        else { Image(systemName:"video.slash").font(.largeTitle).foregroundStyle(.white.opacity(0.6)) }
        if feed.connecting { ProgressView("Live-Bild verbinden …").padding(16).background(.ultraThinMaterial,in:Capsule()) }
    }
}
@MainActor @ViewBuilder private func cameraControls(feed:HomeCameraFeed)->some View {
    ViewThatFits {
        HStack { cameraButtons(feed:feed) }
        VStack { cameraButtons(feed:feed) }
    }.buttonStyle(.bordered).controlSize(.regular)
}
@MainActor @ViewBuilder private func cameraButtons(feed:HomeCameraFeed)->some View {
    Button(feed.live || feed.connecting ? "Stoppen" : "Live",systemImage:feed.live ? "stop.fill" : "play.fill") { if feed.live || feed.connecting {feed.stop()} else {feed.start()} }
    Button(feed.listening ? "Stumm" : "Zuhören",systemImage:feed.listening ? "speaker.wave.2.fill" : "speaker.slash") {Task {await feed.audio(listen:!feed.listening,talk:false)}}.disabled(!feed.live || feed.changingAudio)
    if feed.canSpeak {
        Button(feed.speaking ? "Sprechen beenden" : "Sprechen",systemImage:feed.speaking ? "mic.fill" : "mic.slash") {Task {await feed.audio(listen:true,talk:!feed.speaking)}}.tint(feed.speaking ? .red : LovePalette.cyan).disabled(!feed.live || feed.changingAudio)
    }
}
private struct HomeCameraSurface:UIViewRepresentable {
    let source:HMCameraSource
    func makeUIView(context:Context)->HMCameraView {let view=HMCameraView();view.cameraSource=source;view.contentMode = .scaleAspectFit;return view}
    func updateUIView(_ view:HMCameraView,context:Context) {view.cameraSource=source}
    static func dismantleUIView(_ view:HMCameraView,coordinator:()) {view.cameraSource=nil}
}

struct HomeKitView:View {
    @State private var home=HomeKitDashboard.shared
    @State private var executing=false
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:20) {
                HomeKitDashboardCard()
                if let selected=home.selected {
                    if home.cameras.count > 1 {
                        LoveSectionTitle("Deine Kameras")
                        Picker("Dashboard-Kamera",selection:$home.cameraID) { ForEach(home.cameras,id:\.uniqueIdentifier) {Text($0.name).tag($0.uniqueIdentifier.uuidString)} }
                        ForEach(home.cameras.filter {$0.uniqueIdentifier != home.selectedCamera?.uniqueIdentifier},id:\.uniqueIdentifier) {camera in HomeCameraTile(accessory:camera).loveCard()}
                    }
                    if !selected.actionSets.isEmpty {
                        VStack(alignment:.leading,spacing:14) {
                            LoveSectionTitle("Szenen",subtitle:"Aus deinem Apple Home")
                            ForEach(selected.actionSets,id:\.uniqueIdentifier) {scene in
                                Button(scene.name,systemImage:"sparkles") {
                                    executing=true
                                    selected.executeActionSet(scene) {issue in Task {@MainActor in executing=false;home.message=issue?.localizedDescription} }
                                }.buttonStyle(.bordered).disabled(executing)
                            }
                        }.loveCard()
                    }
                    ForEach(selected.rooms,id:\.uniqueIdentifier) {room in
                        if !room.accessories.isEmpty {
                            LoveSectionTitle(room.name)
                            ForEach(room.accessories,id:\.uniqueIdentifier) {accessory in HomeAccessoryCard(accessory:accessory)}
                        }
                    }
                    Text("Für den Zugriff auf das Zuhause des anderen braucht ihr die Einladung in Apple Home. RJ-Anmeldedaten erteilen keine Home-Rechte. Sprechen hängt von Kamera und Home-Freigabe ab. HomeKit Secure Video-Aufzeichnungen bleiben in Apple Home.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.background(LoveBackground()).navigationTitle("Unser Zuhause").navigationBarTitleDisplayMode(.inline)
    }
}
private struct HomeAccessoryCard:View {
    let accessory:HMAccessory
    @State private var values:[UUID:String]=[:]
    @State private var power:[UUID:Bool]=[:]
    @State private var busy=false
    @State private var error:String?
    private var characteristics:[HMCharacteristic] {
        accessory.services.flatMap(\.characteristics).filter { [HMCharacteristicTypePowerState,HMCharacteristicTypeCurrentTemperature,HMCharacteristicTypeCurrentRelativeHumidity,HMCharacteristicTypeMotionDetected,HMCharacteristicTypeContactState,HMCharacteristicTypeBrightness].contains($0.characteristicType) }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Label(accessory.name,systemImage:"house.fill").font(.headline);Spacer();if !accessory.isReachable {Text("Offline").font(.caption).foregroundStyle(.secondary)} }
            ForEach(characteristics,id:\.uniqueIdentifier) {c in
                if c.characteristicType == HMCharacteristicTypePowerState,c.properties.contains(HMCharacteristicPropertyWritable) {
                    Toggle("Eingeschaltet",isOn:Binding(get:{power[c.uniqueIdentifier] ?? false},set:{value in
                        busy=true;c.writeValue(value) {issue in Task {@MainActor in busy=false;error=issue?.localizedDescription;refresh()} }
                    })).disabled(busy || !accessory.isReachable)
                } else { LabeledContent(label(c),value:values[c.uniqueIdentifier] ?? "–").font(.subheadline) }
            }
            if let error {Text(error).font(.caption).foregroundStyle(.secondary)}
            Button("Aktualisieren",systemImage:"arrow.clockwise") {refresh()}.font(.caption).disabled(busy)
        }.loveCard().task {refresh()}
    }
    private func label(_ c:HMCharacteristic)->String {
        switch c.characteristicType {
        case HMCharacteristicTypeCurrentTemperature:return "Temperatur · °C"
        case HMCharacteristicTypeCurrentRelativeHumidity:return "Luftfeuchtigkeit · %"
        case HMCharacteristicTypeMotionDetected:return "Bewegung"
        case HMCharacteristicTypeContactState:return "Kontakt"
        case HMCharacteristicTypeBrightness:return "Helligkeit · %"
        default:return c.localizedDescription
        }
    }
    private func refresh() {
        for c in characteristics where c.properties.contains(HMCharacteristicPropertyReadable) {
            c.readValue {issue in Task {@MainActor in
                if let issue {error=issue.localizedDescription}
                if c.characteristicType == HMCharacteristicTypeMotionDetected {values[c.uniqueIdentifier]=(c.value as? NSNumber)?.boolValue == true ? "Erkannt" : "Keine"}
                else if c.characteristicType == HMCharacteristicTypeContactState {values[c.uniqueIdentifier]=(c.value as? NSNumber)?.intValue == 0 ? "Geschlossen" : "Offen"}
                else {values[c.uniqueIdentifier]=c.value.map {String(describing:$0)} ?? "–"}
                power[c.uniqueIdentifier]=(c.value as? NSNumber)?.boolValue ?? false
            } }
        }
    }
}
