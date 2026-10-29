import HomeKit
import MapKit
import SwiftUI

enum TVWidgetKind: String,Codable,CaseIterable,Identifiable {
    case clock,mine,partner,location,moments,countdown,nowPlaying,signals,camera,health,planner,studio,documents
    var id: String { rawValue }
    var title: String {
        switch self { case .camera:return "HomeKit-Kamera";case .health:return "Health & Schlaf";case .planner:return "Unsere Planung";case .studio:return "Duftstudio";case .documents:return "Dokumente";case .clock: return "Uhr & Datum"; case .mine: return "Mein iPhone"; case .partner: return "Schatzi"; case .location: return "Freigegebene Standorte"; case .moments: return "Unsere Momente"; case .countdown: return "Unsere Zeit"; case .nowPlaying: return "Unser Kino"; case .signals: return "Liebe Signale" }
    }
    var symbol: String {
        switch self { case .camera:return "web.camera.fill";case .health:return "heart.text.square.fill";case .planner:return "calendar";case .studio:return "waveform";case .documents:return "folder.fill";case .clock: return "clock"; case .mine: return "iphone"; case .partner: return "heart.fill"; case .location: return "map.fill"; case .moments: return "photo.stack"; case .countdown: return "calendar.badge.clock"; case .nowPlaying: return "play.tv.fill"; case .signals: return "hand.wave.fill" }
    }
}
enum TVTheme: String,Codable,CaseIterable,Identifiable {
    case light = "Hell", dusk = "Abend", dark = "Dunkel"
    var id: String { rawValue }
}
struct TVSavedLayout: Codable {
    var mode: TVMode
    var theme: TVTheme
    var widgets: [TVWidgetKind]
    var includeOwnLocation: Bool
    var showPartnerLocation: Bool
    var wallCount: Int
    var fillPhotos: Bool
    var showInfo: Bool
    var sharedEnabled: Bool
    var columns:Int? = nil
    var slideSeconds:Int? = nil
    var cameraAutoLive:Bool? = nil
    var showCaptions:Bool? = nil
}
struct TVDashboard: View {
    @State private var tv = TVPresentation.shared
    var body: some View {
        GeometryReader { geometry in
            let hasPhotos = tv.widgets.contains(.moments)
            let cards = tv.widgets.filter { $0 != .moments }
            let columns = cards.count == 1 ? 1 : tv.columns
            let rows = max(1,Int(ceil(Double(cards.count)/Double(columns))))
            HStack(spacing: 18) {
                if !cards.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 16),count: columns),spacing: 16) {
                        ForEach(cards) { kind in
                            TVDashboardCard(kind: kind)
                                .frame(height: max(80,(geometry.size.height-48-Double(rows-1)*16)/Double(rows)))
                        }
                    }.frame(maxWidth: .infinity)
                }
                if hasPhotos {
                    TVMomentWall(limit: min(6,tv.wallCount))
                        .frame(width: cards.isEmpty ? geometry.size.width-48 : geometry.size.width*0.31)
                }
            }.padding(24).frame(width: geometry.size.width,height: geometry.size.height)
                .background { TVAuroraBackdrop(theme: tv.theme) }
                .animation(.smooth(duration: 0.6), value: tv.widgets)
                .animation(.smooth(duration: 0.6), value: tv.columns)
        }
    }
}
struct TVDashboardCard: View {
    let kind: TVWidgetKind
    @State private var tv = TVPresentation.shared
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading,spacing: 10) {
                Label(kind.title,systemImage: kind.symbol).font(.system(size: max(13,min(24,geometry.size.height*0.12)),weight: .semibold)).foregroundStyle(LovePalette.pink)
                    .symbolRenderingMode(.hierarchical)
                content.font(.system(size: max(15,min(28,geometry.size.height*0.15))))
                    .frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .leading)
            }.padding(20).frame(width: geometry.size.width,height: geometry.size.height,alignment: .topLeading)
                .loveGlass(in: RoundedRectangle(cornerRadius:28,style:.continuous))
        }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .camera: TVHomeCameraWidget()
        case .health:
            VStack(alignment:.leading,spacing:8) {
                Label(tv.app?.partner?.presence?.steps?.formatted() ?? "–",systemImage:"figure.walk")
                Label(tv.app?.partner?.presence?.sleepMinutes.map { "\($0 / 60) h \($0 % 60) min" } ?? "Keine Schlafdaten",systemImage:"moon.zzz")
            }
        case .planner:
            let plans=(tv.app?.records ?? []).filter { [.calendar,.reminder,.milestone].contains($0.kind) && ($0.payload.startAt?.rjDate ?? .distantPast) >= .now }.sorted { ($0.payload.startAt ?? "") < ($1.payload.startAt ?? "") }
            VStack(alignment:.leading,spacing:8) {
                ForEach(Array(plans.prefix(3))) { record in Text(record.payload.title ?? "Unser Termin").font(.callout).lineLimit(1) }
                if plans.isEmpty { Text("Zeit für euch.").font(.callout) }
            }
        case .studio:
            VStack(alignment:.leading,spacing:8) {
                Text("\(tv.app?.farts.count ?? 0) Aufnahmen geladen").font(.callout)
                if let title=tv.app?.farts.first?.title { Text(title).font(.headline).lineLimit(2) }
            }
        case .documents: TVDocumentsWidget()
        case .clock: TVClockCard()
        case .mine: TVPhoneCard()
        case .partner:
            VStack(alignment: .leading,spacing: 8) {
                Text(tv.app?.partner?.displayName ?? "Schatzi").font(.title2.bold())
                Text(tv.app?.partner?.presence?.statusMessage ?? "Ein kleiner Platz für uns.").lineLimit(3)
                if let level = tv.app?.partner?.presence?.batteryLevel { Label("\(level) % · Schatzi",systemImage: "battery.100percent").font(.callout) }
                if let date = tv.app?.partner?.presence?.reportedAt?.rjDate { Text("Datenstand " + date.formatted(date: .omitted,time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            }
        case .location: TVLocationCard()
        case .countdown: TVCountdownCard()
        case .nowPlaying: TVNowPlayingCard()
        case .signals: TVSignalsCard()
        case .moments: TVMomentWall(limit: 4)
        }
    }
}
private struct TVClockCard: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading,spacing: 5) {
                Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))).font(.system(size: 64,weight: .light,design: .rounded)).monospacedDigit().minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text(context.date.formatted(date: .complete,time: .omitted)).font(.callout).foregroundStyle(.secondary)
            }.animation(.smooth, value: context.date)
        }
    }
}
private struct TVPhoneCard: View {
    @ObservedObject private var device = DeviceStatusService.shared
    @State private var tv = TVPresentation.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            Text(tv.app?.me?.displayName ?? "Mein iPhone").font(.title2.bold())
            Label(device.batteryLevel.map { "\($0) %" } ?? "Akku unbekannt",systemImage: device.batteryState == "charging" ? "battery.100percent.bolt" : "battery.100percent").font(.title2.monospacedDigit())
            Text(device.networkType == "wifi" ? "Im WLAN" : device.networkType == "cellular" ? "Mobil verbunden" : "Netz: " + device.networkType).font(.callout).foregroundStyle(.secondary)
            if device.lowPowerMode { Label("Stromsparmodus",systemImage: "leaf.fill").font(.caption) }
        }
    }
}
private struct TVLocationCard: View {
    @State private var tv = TVPresentation.shared
    @ObservedObject private var location = LocationService.shared
    private var coordinate: CLLocationCoordinate2D? {
        if tv.includeOwnLocation, location.sharingEnabled, let value = location.lastLocation { return value.coordinate }
        if tv.showPartnerLocation, let p = tv.app?.partner?.presence,p.locationSharing == true,let latitude = p.latitude,let longitude = p.longitude {
            return CLLocationCoordinate2D(latitude: latitude,longitude: longitude)
        }
        return nil
    }
    private var accuracy:Double? {
        if tv.includeOwnLocation,location.sharingEnabled {return location.lastLocation?.horizontalAccuracy}
        return tv.app?.partner?.presence?.horizontalAccuracy
    }
    private var timestamp: Date? {
        if tv.includeOwnLocation, location.sharingEnabled { return location.lastLocation?.timestamp }
        return tv.app?.partner?.presence?.locationTimestamp?.rjDate
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 7) {
            if let coordinate,CLLocationCoordinate2DIsValid(coordinate) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,span: MKCoordinateSpan(latitudeDelta: 0.018,longitudeDelta: 0.018)))) {
                    if let accuracy=accuracy,accuracy.isFinite,accuracy > 0 {MapCircle(center:coordinate,radius:accuracy).foregroundStyle(LovePalette.pink.opacity(0.12)).stroke(LovePalette.pink.opacity(0.5),lineWidth:1)}
                    Annotation(tv.includeOwnLocation && location.sharingEnabled ? tv.app?.me?.displayName ?? "Du" : tv.app?.partner?.displayName ?? "Schatzi",coordinate: coordinate) { Image(systemName: "heart.circle.fill").font(.title).foregroundStyle(.pink,.white) }
                }.id("\(coordinate.latitude),\(coordinate.longitude)").allowsHitTesting(false).clipShape(RoundedRectangle(cornerRadius: 12))
                if let timestamp { Text("Letzter Standort: " + timestamp.formatted(date: .abbreviated,time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            } else { Text("Kein freigegebener Standort. Wähle deine TV-Freigaben in den AirPlay-Einstellungen.").font(.callout).foregroundStyle(.secondary) }
        }
    }
}
private struct TVCountdownCard: View {
    @State private var tv = TVPresentation.shared
    private var next: SharedRecord? { tv.app?.records.filter { $0.kind == .milestone && ($0.payload.startAt?.rjDate ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }.sorted { ($0.payload.startAt ?? "") < ($1.payload.startAt ?? "") }.first }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            if let next,let date = next.payload.startAt?.rjDate {
                let days = Calendar.current.dateComponents([.day],from: Calendar.current.startOfDay(for: .now),to: date).day ?? 0
                Text("Noch \(days) Tage").font(.title.bold())
                Text(next.payload.title ?? "Unser besonderer Tag").lineLimit(2)
            } else { Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(LovePalette.pink); Text("So schön, dass es uns gibt.").font(.title3) }
        }
    }
}
private struct TVNowPlayingCard: View {
    @State private var cinema = CinemaCoordinator.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 9) {
            Text(cinema.active ? cinema.title : "Ein Abend mit dir.").font(.title3.bold()).lineLimit(3)
            if cinema.active { Label(cinema.playing ? "Läuft gerade" : "Pausiert",systemImage: cinema.playing ? "play.fill" : "pause.fill").font(.callout) }
            if let end = cinema.sleepUntil { Text("Schlaftimer: " + end.formatted(date: .omitted,time: .shortened)).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct TVSignalsCard: View {
    @State private var together = TVTogetherService.shared
    var body: some View {
        TimelineView(.periodic(from: .now,by: 1)) { _ in
            if let signal = together.recentSignals.last {
                VStack(alignment: .leading,spacing: 6) {
                    Text(signal.emoji).font(.system(size: 48))
                    Text(signal.owner == together.userID ? "Von dir" : "Von deinem Lieblingsmenschen").font(.callout)
                }
            } else { Text("Ein Herz ist nur einen Fingertipp entfernt.").font(.callout).foregroundStyle(.secondary) }
        }
    }
}
struct TVMomentWall: View {
    var limit: Int? = nil
    @State private var tv = TVPresentation.shared
    private var visible: [SharedRecord] {
        guard !tv.moments.isEmpty else { return [] }
        return (0..<min(limit ?? tv.wallCount,tv.moments.count)).map { tv.moments[(tv.index+$0)%tv.moments.count] }
    }
    var body: some View {
        GeometryReader { geometry in
            let count = max(1,visible.count)
            let columns = geometry.size.width > geometry.size.height ? (count > 6 ? 4 : 3) : 2
            let rows = max(1,Int(ceil(Double(count)/Double(columns))))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 12),count: columns),spacing: 12) {
                ForEach(visible) { record in
                    ZStack {
                        Color.secondary.opacity(0.08)
                        if let image = tv.wallImages[record.id] {
                            Image(uiImage: image).resizable().aspectRatio(contentMode: tv.fillPhotos ? .fill : .fit)
                                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        } else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary).transition(.opacity) }
                    }.frame(height: max(40,(geometry.size.height-Double(rows-1)*12)/Double(rows)))
                        .frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .animation(.easeInOut(duration: 0.7), value: tv.wallImages[record.id] != nil)
                        .transition(.opacity)
                }
            }.frame(maxWidth: .infinity,maxHeight: .infinity)
            .animation(.smooth(duration: 0.9), value: visible.map(\.id))
            if visible.isEmpty { ContentUnavailableView("Eure Momente",systemImage: "photo.stack",description: Text("Teilt Fotos in eurer Galerie.")) }
        }
    }
}
struct TVSettingsView: View {
    @State private var tv = TVPresentation.shared
    var body: some View {
        Form {
            Section {
                TVScaledPreview { TVDashboard() }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .accessibilityLabel("Vorschau deines TV-Dashboards")
                HStack(spacing: 8) {
                    LovePulseDot(color: tv.connected ? .green : .orange, active: tv.connected)
                    Text(tv.connected ? "Fernseher verbunden" : "Vorschau · noch kein Fernseher verbunden").font(.caption)
                }
            }
            Section("Euer Bildschirm") {
                Picker("Ansicht",selection: $tv.mode) { ForEach(TVMode.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Dashboard-Farben",selection: $tv.theme) { ForEach(TVTheme.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Gemeinsame Bühne aktualisieren",isOn: $tv.sharedEnabled)
                Picker("Dashboard-Spalten",selection:$tv.columns) {Text("Zwei").tag(2);Text("Drei").tag(3)}
                Button("Dashboard auf dem Fernseher zeigen",systemImage:"rectangle.grid.2x2") {tv.mode = .dashboard}
            }
            Section("Dashboard-Widgets · Reihenfolge bearbeiten") {
                ForEach(tv.widgets) { kind in Label(kind.title,systemImage: kind.symbol) }
                    .onMove { source,destination in tv.widgets.move(fromOffsets: source,toOffset: destination) }
                    .onDelete { offsets in tv.widgets.remove(atOffsets: offsets); if tv.widgets.isEmpty { tv.widgets = [.clock] } }
                Menu("Widget hinzufügen",systemImage: "plus") {
                    ForEach(TVWidgetKind.allCases.filter { !tv.widgets.contains($0) }) { kind in Button(kind.title,systemImage: kind.symbol) { tv.widgets.append(kind) } }
                }
            }
            Section("HomeKit-Kamera auf dem Fernseher") {
                TVCameraSettings()
                Toggle("Kamera im Dashboard live starten",isOn:$tv.cameraAutoLive)
                Text("Füge das Kamera-Widget oben hinzu. Nur auf einem verbundenen Bildschirm wird automatisch live gestartet, immer zunächst ohne Ton. Sprechen steuerst du auf dem iPhone. Die App muss aktiv bleiben.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Standorte auf dem Fernseher") {
                Toggle("Meinen freigegebenen Standort zeigen",isOn: $tv.includeOwnLocation)
                Toggle("Schatzis freigegebenen Standort zeigen",isOn: $tv.showPartnerLocation)
                Text("Es wird kein neuer Standortzugriff angefordert. Die bestehende Standortfreigabe muss aktiv sein. In der Karte wird dein Standort bevorzugt, wenn du beide auswählst.").font(.caption)
            }
            Section("Momente") {
                Picker("Fotos gleichzeitig",selection: $tv.wallCount) { ForEach([4,6,9,12],id: \.self) { Text("\($0)").tag($0) } }
                Picker("Diashow-Wechsel",selection:$tv.slideSeconds) {ForEach([5,10,15,30,60],id:\.self) {Text("\($0) Sekunden").tag($0)}}
                Toggle("Fotos bildfüllend zuschneiden",isOn: $tv.fillPhotos)
                Toggle("Titel und Datum zu Fotos zeigen",isOn: $tv.showCaptions)
                Toggle("Infos neben dem Kino-Player",isOn: $tv.showInfo)
            }
            Section { Text("Die Anordnung wird automatisch in deinem Konto auf eurem RJ-Server gesichert. Zeichnungen, Spielzüge und Signale teilen eure beiden angemeldeten Apps. iOS aktualisiert die eigene TV-Oberfläche zuverlässig im Vordergrund; eine gesperrte oder beendete App kann keinen dauerhaft live aktualisierten TV-Bildschirm garantieren.").font(.footnote) }
        }.scrollContentBackground(.hidden).background(LoveBackground()).navigationTitle("AirPlay gestalten").toolbar { EditButton() }.accessibilityIdentifier("tv-settings-screen")
    }
}

private struct TVCameraSettings:View {
    @State private var home=HomeKitDashboard.shared
    var body:some View {
        if home.enabled {
            Picker("Zuhause",selection:$home.selectedID) {ForEach(home.homes,id:\.uniqueIdentifier) {Text($0.name).tag($0.uniqueIdentifier.uuidString)}}
            Picker("Kamera",selection:$home.cameraID) {
                Text("Erste verfügbare Kamera").tag("")
                ForEach(home.cameras,id:\.uniqueIdentifier) {Text($0.name).tag($0.uniqueIdentifier.uuidString)}
            }
        } else {NavigationLink("Apple Home verbinden",destination:HomeKitView())}
    }
}
private struct TVHomeCameraWidget:View {
    @State private var home=HomeKitDashboard.shared
    @State private var tv=TVPresentation.shared
    @Environment(\.loveTVPreview) private var preview
    var body:some View {
        Group {
            if home.enabled,let camera=home.selectedCamera {
                if tv.connected && !preview {HomeCameraTile(accessory:camera,autoplay:tv.cameraAutoLive,external:true).id(camera.uniqueIdentifier)}
                else {Label(camera.name + " · live am Fernseher",systemImage:"video.fill").font(.callout)}
            } else {Text("Wähle eine HomeKit-Kamera auf deinem iPhone.").font(.callout).foregroundStyle(.secondary)}
        }.task {if home.enabled {home.activate()}}
    }
}
private struct TVDocumentsWidget:View {
    @State private var tv=TVPresentation.shared
    @State private var data=DocumentLibrary()
    @Environment(\.loveTVPreview) private var preview
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("\(data.folders.count) Ordner · \(data.files.count) Dateien").font(.callout).contentTransition(.numericText())
            if let file=data.files.first {Text(file.filename).font(.headline).lineLimit(2)}
        }.task {
            while !Task.isCancelled && !preview {
                if let api=tv.app?.api,let value=try? await api.documents() {data=value}
                do {try await Task.sleep(for:.seconds(30))} catch {return}
            }
        }
    }
}
