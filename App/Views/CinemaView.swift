import SwiftUI

enum CinemaSection: String, CaseIterable, Identifiable {
    case youtube = "YouTube", plex = "Plex", television = "AirPlay"
    var id: String { rawValue }
}
struct CinemaView: View {
    @Environment(AppState.self) private var app
    @State private var cinema = CinemaCoordinator.shared
    @State private var tv = TVPresentation.shared
    @State private var section: CinemaSection = .youtube
    @State private var together = false
    @State private var sharePlex = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                Picker("Medien", selection: $section) {
                    ForEach(CinemaSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("cinema-section")
                if cinema.active { CinemaNowPlayingView() }
                if let error = cinema.error { Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
                if section != .television {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Zusammen schauen", isOn: $together).accessibilityIdentifier("cinema-together")
                        Text(together ? "Der andere tritt auf seinem iPhone ausdrücklich bei. Ihr könnt beide starten, pausieren und springen." : "Nur für dich. Es wird kein gemeinsamer Raum angelegt und keine gemeinsame Schauzeit gezählt.")
                            .font(.caption).foregroundStyle(.secondary)
                        if section == .plex && together {
                            Toggle("Diesen Film für maximal 4 Stunden freigeben", isOn: $sharePlex)
                            Text("Nur dieser Film, keine Bibliothek und kein Kontozugang. Der RJ-Server vermittelt die Datei. Du kannst die Freigabe jederzeit widerrufen.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.loveCard()
                }
                switch section {
                case .youtube: CinemaYouTubeBrowser(together: together)
                case .plex: CinemaPlexBrowser(together: together, share: sharePlex)
                case .television: CinemaTVRemote()
                }
                invitations
                statistics
            }.padding(20)
        }.background(LoveBackground()).navigationTitle("Unser Kino").navigationBarTitleDisplayMode(.inline)
            .onAppear { cinema.screenVisible = true; cinema.configure(app: app) }
            .onDisappear { cinema.screenVisible = false }
            .task { await cinema.refresh() }.refreshable { await cinema.refresh() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CinemaAirPlayPicker().frame(width: 40,height: 40).accessibilityLabel("AirPlay-Wiedergabegerät wählen") } }
            .accessibilityIdentifier("cinema-screen")
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            LoveEyebrow(text: "Dein Lieblingsmensch. Euer Lieblingsfilm.")
            HStack {
                Text("Noch eine Folge.\nMit dir.").font(.system(size: 34,weight: .medium,design: .serif))
                Spacer(); LoveIcon(symbol: "play.tv.fill",tint: LovePalette.violet,size: 62)
            }
            Text("YouTube, deine Plex-Mediathek und ein eigener Platz auf dem Fernseher.").font(.subheadline).foregroundStyle(.secondary)
        }.loveCard()
    }
    @ViewBuilder private var invitations: some View {
        let others = cinema.rooms.filter { $0.id != cinema.room?.id }
        if !others.isEmpty {
            VStack(alignment: .leading,spacing: 14) {
                LoveSectionTitle("Ein Platz neben mir",subtitle: "Gemeinsame Abende warten auf euch")
                ForEach(others) { room in
                    HStack {
                        VStack(alignment: .leading) { Text(room.title).font(.headline); Text(room.provider == "youtube" ? "YouTube" : "Plex · ausgewählter Film").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Beitreten") { tv.mode = .cinema; Task { await cinema.join(room) } }.buttonStyle(.bordered).disabled(cinema.busy || (room.provider == "plex" && !room.plexShared))
                    }
                }
            }.loveCard()
        }
    }
    private var statistics: some View {
        VStack(alignment: .leading,spacing: 12) {
            LoveSectionTitle("Unsere Kinozeit",subtitle: "Nur wenn beide Geräte Wiedergabe melden")
            if cinema.stats.isEmpty { Text("Euer erster gemeinsamer Abend wartet noch.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(cinema.stats) { item in
                HStack { Text(item.provider == "youtube" ? "YouTube" : "Plex"); Spacer(); Text("\(Int(item.seconds / 60)) Min · \(item.evenings) Abende").monospacedDigit() }.font(.subheadline)
            }
            Text("Näherungswerte: Puffern, Werbung, Verbindungsabbrüche und iOS-Hintergrundpausen können die Synchronität und Erfassung beeinflussen.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
    }
}
struct CinemaNowPlayingView: View {
    @State private var cinema = CinemaCoordinator.shared
    @State private var tv = TVPresentation.shared
    @State private var seek = 0.0
    @State private var seeking = false
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack {
                Label(cinema.room == nil ? "Nur für dich" : "Unser gemeinsamer Abend",systemImage: cinema.room == nil ? "person.fill" : "person.2.fill").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Beenden",role: .destructive) { Task { await cinema.leave() } }.font(.caption)
            }
            Text(cinema.title).font(.headline).lineLimit(3)
            if tv.connected && tv.mode == .cinema {
                Label("Das Video läuft auf eurem Fernseher",systemImage: "tv.fill").frame(maxWidth: .infinity).padding(24).background(.black.opacity(0.08),in: RoundedRectangle(cornerRadius: 18))
            } else {
                CinemaPlaybackSurface().frame(minHeight: 200,idealHeight: 230).clipShape(RoundedRectangle(cornerRadius: 18))
            }
            HStack(spacing: 28) {
                Button { Task { await cinema.control("seek",value: max(0,cinema.position-15)) } } label: { Image(systemName: "gobackward.15") }
                Button { Task { await cinema.control(cinema.playing ? "pause" : "play") } } label: { Image(systemName: cinema.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 48)) }.accessibilityLabel(cinema.playing ? "Gemeinsam pausieren" : "Wiedergabe starten")
                Button { Task { await cinema.control("seek",value: cinema.position+15) } } label: { Image(systemName: "goforward.15") }
                Spacer(); CinemaAirPlayPicker().frame(width: 36,height: 36)
            }.font(.title2).padding(10).loveGlass(in: RoundedRectangle(cornerRadius: 20))
            Text(Duration.seconds(cinema.position).formatted(.time(pattern: .hourMinuteSecond))).font(.caption.monospacedDigit())
            if cinema.duration > 0 {
                Slider(value: $seek,in: 0...max(1,cinema.duration),onEditingChanged: { editing in seeking = editing; if !editing { Task { await cinema.control("seek",value: seek) } } }).accessibilityLabel("Videoposition")
                    .onChange(of: cinema.position) { _, value in if !seeking { seek = min(cinema.duration,max(0,value)) } }
            }
            Menu {
                Button("Ohne Timer") { Task { await cinema.control("timer",value: 0) } }
                ForEach([15,30,60,120,180,240],id: \.self) { minutes in
                    Button("Nach \(minutes) Minuten") { Task { await cinema.control("timer",value: Double(minutes*60)) } }
                }
            } label: {
                Label(cinema.sleepUntil.map { "Endet um " + $0.formatted(date: .omitted,time: .shortened) } ?? "Schlaftimer einstellen",systemImage: "moon.zzz.fill")
            }.font(.subheadline).accessibilityIdentifier("cinema-sleep-timer")
            if let room = cinema.room, room.provider == "plex", room.ownerID == cinema.userID, room.plexShared {
                Button("Plex-Freigabe jetzt widerrufen",role: .destructive) { Task { await cinema.control("revoke") } }.font(.footnote)
            }
            if cinema.provider == "youtube" {
                Text("YouTube bleibt sichtbar. Beim Verlassen der Ansicht erscheint der Player unten; beim Sperren oder Verlassen der App pausiert er. Falls iOS den Start blockiert, direkt im YouTube-Player auf Play tippen.").font(.caption).foregroundStyle(.secondary)
            }
        }.loveCard()
    }
}
struct CinemaYouTubeBrowser: View {
    let together: Bool
    @State private var cinema = CinemaCoordinator.shared
    @State private var account = YouTubeAccount.shared
    @Environment(\.openURL) private var openURL
    @AppStorage("rjlove.youtube.consent.v1") private var consent = false
    @State private var query = ""
    @State private var items: [YouTubeResult] = []
    @State private var nextPage: String?
    @State private var searching = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            if !consent {
                Text("YouTube verwendet beim Laden des Players eigene Dienste und Cookies. Mit dem Aktivieren akzeptierst du die YouTube-Nutzungsbedingungen und die nachfolgend verlinkten Datenschutzhinweise. An Google gehen unter anderem Videoauswahl, IP-Adresse und Geräteinformationen. RJ Love teilt keine YouTube-Anmeldedaten mit deinem Partner.").font(.footnote)
                links
                Button("YouTube aktivieren") { consent = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("cinema-youtube-consent")
            } else {
                TextField("YouTube suchen oder Video-Link einfügen",text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never).onSubmit { Task { await search() } }.accessibilityIdentifier("cinema-youtube-query")
                Button(searching ? "Suche …" : "Suchen / Video öffnen",systemImage: "magnifyingglass") { Task { await search() } }.buttonStyle(.borderedProminent).disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                ForEach(items) { item in video(item) }
                if nextPage != nil { Button("Weitere Ergebnisse") { Task { await search(more: true) } }.disabled(searching) }
                Divider()
                Text(account.connected ? account.channel.isEmpty ? "Dein YouTube-Konto" : account.channel : "Dein eigenes YouTube-Konto").font(.headline)
                Text("Deine Playlists bleiben privat. Gemeinsam geteilt wird nur das ausgewählte Video; private oder gesperrte Videos benötigen auf jedem Gerät eine gültige Berechtigung. Die Anmeldung am Datenkonto meldet den eingebetteten Player nicht automatisch an.").font(.caption).foregroundStyle(.secondary)
                if account.connected {
                    Button("Meine Playlists laden") { Task { await account.loadLibrary() } }.disabled(account.busy)
                    ForEach(account.playlists) { list in Button(list.title,systemImage: "list.bullet") { Task { await account.loadPlaylist(list.id) } } }
                    ForEach(account.videos) { item in video(item) }
                    Button("YouTube-Konto trennen",role: .destructive) { Task { await account.disconnect() } }
                } else {
                    Button("Bei Google anmelden",systemImage: "person.crop.circle.badge.checkmark") { Task { await account.signIn() } }.disabled(account.busy)
                    Text("Optional: einmalig Google-OAuth am privaten Server einrichten. Die Einrichtung steht in RELEASE-4.0.0.md im Update-Paket.").font(.caption).foregroundStyle(.secondary)
                }
                if let url = account.authURL { Link("Google-Anmeldung im Browser fortsetzen",destination: url) }
                if let error = account.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                links
                Button("YouTube deaktivieren",role: .destructive) { consent = false; Task { if cinema.provider == "youtube" { await cinema.leave() }; await account.disconnect() } }.font(.caption)
            }
        }.loveCard().onChange(of: account.authURL) { _, url in if let url { openURL(url) } }
    }
    private var links: some View {
        VStack(alignment: .leading,spacing: 6) {
            Link("YouTube-Nutzungsbedingungen",destination: URL(string: "https://www.youtube.com/t/terms")!)
            Link("Google-Datenschutz",destination: URL(string: "https://policies.google.com/privacy")!)
            Link("RJ-Love-Datenschutz",destination: URL(string: "https://github.com/Robin9094707/RJAPP/blob/codex/cinema-4.0.0/PRIVACY.md")!)
        }.font(.caption)
    }
    private func video(_ item: YouTubeResult) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading,spacing: 4) { Text(item.title).font(.subheadline.bold()); Text(item.channel).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { TVPresentation.shared.mode = .cinema; Task { await cinema.startYouTube(id: item.id,title: item.title,together: together) } } label: { Image(systemName: "play.circle.fill").font(.title2) }.accessibilityLabel(item.title + " abspielen")
        }
    }
    private func search(more: Bool = false) async {
        guard !searching else { return }; searching = true; defer { searching = false }
        if let id = YouTubeLink.videoID(query) { TVPresentation.shared.mode = .cinema; await cinema.startYouTube(id: id,title: "YouTube · " + id,together: together); return }
        guard let api = cinema.api else { return }
        do {
            var body: [String: Any] = ["query": query]
            if more, let nextPage { body["page"] = nextPage }
            let page = try await api.cinema("youtube/search",body: body,as: YouTubeSearchPage.self)
            if more { var ids = Set(items.map(\.id)); items += page.items.filter { ids.insert($0.id).inserted } } else { items = page.items }
            nextPage = page.nextPage; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
struct CinemaPlexBrowser: View {
    let together: Bool
    let share: Bool
    @State private var cinema = CinemaCoordinator.shared
    @State private var plex = CinemaCoordinator.shared.plex
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text("Deine Plex-Mediathek").font(.headline)
            Text("Melde dich direkt bei Plex an. Dein Zugang liegt getrennt im Schlüsselbund dieses iPhones. Unterstützt werden eigene Plex-Server und auf iOS direkt abspielbare Dateien. Plex-Streamingangebote und Transcoding sind hier nicht enthalten.").font(.caption).foregroundStyle(.secondary)
            if !plex.authenticated {
                Button("Mit Plex verbinden",systemImage: "person.badge.key.fill") { Task { await plex.signIn() } }.buttonStyle(.borderedProminent).disabled(plex.busy)
            } else {
                HStack { Button("Server laden") { Task { await plex.loadServers() } }; Spacer(); Button("Trennen",role: .destructive) { Task { if cinema.provider == "plex" { await cinema.leave() }; plex.disconnect() } } }.font(.subheadline)
                ForEach(plex.servers) { server in
                    Button { Task { await plex.select(server) } } label: { Label(server.name,systemImage: plex.server?.id == server.id ? "checkmark.circle.fill" : "externaldrive.fill") }
                }
                if plex.server != nil {
                    HStack { Button("Bibliotheken",systemImage: "square.grid.2x2") { Task { await plex.browse("/library/sections") } }; Spacer(); Text(plex.server?.name ?? "").font(.caption).foregroundStyle(.secondary) }
                    TextField("Auf deinem Plex-Server suchen",text: $query).textFieldStyle(.roundedBorder).onSubmit { Task { await plex.browse("/hubs/search",query: query) } }
                    ForEach(plex.entries) { item in
                        Button {
                            if item.playable { TVPresentation.shared.mode = .cinema; Task { await cinema.startPlex(item,together: together,share: share) } }
                            else { Task { await plex.browse(item.key) } }
                        } label: {
                            HStack { Image(systemName: item.playable ? "play.circle.fill" : "folder.fill"); Text(item.title).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        }.padding(.vertical,4).disabled(cinema.busy)
                    }
                    if plex.hasMore { Button("Mehr laden") { Task { await plex.browse(plex.path,more: true) } }.disabled(plex.busy) }
                }
            }
            if plex.busy || cinema.busy { ProgressView() }
            if let url = plex.authURL { Link("Plex-Anmeldung im Browser fortsetzen",destination: url) }
            if let error = plex.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.loveCard().onChange(of: plex.authURL) { _, url in if let url { openURL(url) } }
    }
}
struct CinemaTVRemote: View {
    @State private var tv = TVPresentation.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Label(tv.connected ? "Fernseher verbunden" : "Fernseher verbinden",systemImage: "airplay.video").font(.headline)
            Text("Für den eigenen TV-Bildschirm: Im iOS-Kontrollzentrum Bildschirm­synchronisierung wählen und Apple TV oder AirPlay-TV verbinden. RJ Love liefert dann eine eigene Vollbildansicht. Für reine Videowiedergabe die AirPlay-Taste am Player verwenden.").font(.footnote).foregroundStyle(.secondary)
            Picker("TV-Ansicht",selection: $tv.mode) { ForEach(TVMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                .onChange(of: tv.mode) { _, mode in if mode == .moments { Task { await tv.loadMoments() } } }
            if tv.mode == .cinema {
                Toggle("Uhr & Schatzi-Infos neben dem Video",isOn: $tv.showInfo)
                Text("Die Infos stehen neben dem Player und verdecken das Video nicht. Ausgeschaltet nutzt der Film die gesamte TV-Fläche.").font(.caption).foregroundStyle(.secondary)
            }
            if tv.mode == .moments {
                if let image = tv.image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 15)) }
                HStack { Button("Zurück",systemImage: "backward.end.fill") { tv.advance(-1) }; Spacer(); Button(tv.slideshow ? "Diashow stoppen" : "Diashow starten") { tv.toggleSlideshow() }; Spacer(); Button("Weiter",systemImage: "forward.end.fill") { tv.advance(1) } }.font(.caption)
                Text("\(tv.moments.isEmpty ? 0 : tv.index+1) / \(tv.moments.count) Momente · Fotos und Live-Photo-Standbilder").font(.caption).foregroundStyle(.secondary)
                if let error = tv.error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
            Text("Der Nachtmodus zeigt eine sehr dunkle, leicht wandernde Uhr. Für die TV-Ansicht bleibt RJ Love geöffnet und das iPhone entsperrt. Reine Plex-Videowiedergabe kann im Hintergrund weiterlaufen. Der Timer pausiert die Wiedergabe; den Fernseher selbst schaltet er nicht aus.").font(.caption).foregroundStyle(.secondary)
            Text("Videos behalten ihr Seitenverhältnis. Abweichende Filmformate können schwarze Balken haben; das TV-Layout nutzt die gesamte Bildschirmfläche.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
    }
}
