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
    @State private var together = true
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
                        Text(together ? "YouTube verbindet euch automatisch im selben Raum. Ihr könnt beide starten, pausieren, springen und das nächste Video auswählen." : "Nur für dich. Es wird kein gemeinsamer Raum angelegt und keine gemeinsame Schauzeit gezählt.")
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
    @AppStorage("rjlove.youtube.consent.v1") private var consent = false
    @State private var query = ""
    @State private var browser: YouTubeWebDestination?
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            if !consent {
                Text("YouTube wird von Google bereitgestellt. Beim Öffnen gehen unter anderem IP-Adresse, Geräteinformationen und die Videoauswahl an Google. Anmeldungen erfolgen ausschließlich auf der echten Google-/YouTube-Seite. Deine Abos und Anmeldedaten werden nicht mit Schatzi geteilt.").font(.footnote)
                links
                Button("YouTube aktivieren") { consent = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("cinema-youtube-consent")
            } else {
                TextField("YouTube suchen oder Video-Link einfügen",text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { openSearch() }.accessibilityIdentifier("cinema-youtube-query")
                Button("Suchen / Video öffnen",systemImage: "magnifyingglass") { openSearch() }.buttonStyle(.borderedProminent).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Suche ohne eigenen API-Schlüssel. Öffne ein Video und wähle im Teilen-Menü des eingebauten Browsers „Mit Schatzi schauen“, um es in euren gemeinsamen Player zu übernehmen.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    webButton("YouTube",symbol: "play.rectangle",path: "/")
                    webButton("Meine Abos",symbol: "person.2",path: "/feed/subscriptions")
                    webButton("Mein Bereich",symbol: "person.crop.circle",path: "/feed/you")
                }.font(.subheadline)
                Text("Anmeldung, Abos und YouTube Premium verwaltet die echte YouTube-Webseite. Jedes iPhone verwendet seine eigene Browser-Anmeldung. Der gemeinsame eingebettete Player übernimmt diese Anmeldung nicht automatisch.").font(.caption).foregroundStyle(.secondary)
                Toggle("Gemeinsamen Raum automatisch verbinden",isOn: $cinema.autoJoin)
                    .font(.subheadline).accessibilityIdentifier("cinema-auto-join")
                DisclosureGroup("Optionale API-Playlists") {
                    VStack(alignment: .leading,spacing: 12) {
                        Text("Die Websuche und der persönliche YouTube-Bereich oben benötigen keine API-Einrichtung. Nur diese zusätzliche native Playlist-Anzeige verwendet die bisherige optionale Google-OAuth-Konfiguration.").font(.caption).foregroundStyle(.secondary)
                        if account.connected {
                            Button("Meine Playlists laden") { Task { await account.loadLibrary() } }.disabled(account.busy)
                            ForEach(account.playlists) { list in Button(list.title,systemImage: "list.bullet") { Task { await account.loadPlaylist(list.id) } } }
                            ForEach(account.videos) { item in
                                Button(item.title,systemImage: "play.circle") { Task { await choose(item.id,item.title) } }
                            }
                            Button("API-Konto trennen",role: .destructive) { Task { await account.disconnect() } }
                        } else { Button("Optionales API-Konto verbinden") { Task { await account.signIn() } }.disabled(account.busy) }
                        if let url = account.authURL { Link("Google-Anmeldung fortsetzen",destination: url) }
                        if let error = account.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    }.padding(.top,12)
                }.font(.subheadline)
                links
                Button("YouTube deaktivieren",role: .destructive) { consent = false; Task { if cinema.provider == "youtube" { await cinema.leave() }; await account.disconnect() } }.font(.caption)
            }
        }.loveCard()
            .sheet(item: $browser) { destination in
                YouTubeWebBrowser(url: destination.url,together: together) { id,title,both in
                    browser = nil
                    TVPresentation.shared.mode = .cinema
                    Task { await cinema.startYouTube(id: id,title: title,together: both) }
                }.ignoresSafeArea()
                    .onAppear { cinema.youtubeBrowsing = true; cinema.youtube.pause() }
                    .onDisappear { cinema.youtubeBrowsing = false }
            }
    }
    private var links: some View {
        VStack(alignment: .leading,spacing: 6) {
            Link("YouTube-Nutzungsbedingungen",destination: URL(string: "https://www.youtube.com/t/terms")!)
            Link("Google-Datenschutz",destination: URL(string: "https://policies.google.com/privacy")!)
            Link("RJ-Love-Datenschutz",destination: URL(string: "https://github.com/Robin9094707/RJAPP/blob/codex/airplay-4.1.0/PRIVACY.md")!)
        }.font(.caption)
    }
    private func webButton(_ title: String,symbol: String,path: String) -> some View {
        Button(title,systemImage: symbol) { browser = YouTubeWebDestination(url: URL(string: "https://m.youtube.com"+path)!) }.buttonStyle(.bordered)
    }
    private func openSearch() {
        if let id = YouTubeLink.videoID(query) { Task { await choose(id,"YouTube · "+id) }; return }
        var url = URLComponents(string: "https://m.youtube.com/results")!
        url.queryItems = [.init(name: "search_query",value: query.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let value = url.url { browser = YouTubeWebDestination(url: value) }
    }
    private func choose(_ id: String,_ title: String) async {
        TVPresentation.shared.mode = .cinema
        await cinema.startYouTube(id: id,title: title,together: together)
    }
}
struct CinemaPlexBrowser: View {
    let together: Bool
    let share: Bool
    @State private var cinema = CinemaCoordinator.shared
    @State private var plex = CinemaCoordinator.shared.plex
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var selectedHome: PlexHomeProfile?
    @State private var profilePIN = ""
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text("Deine Plex-Mediathek").font(.headline)
            Text("Melde dich direkt bei Plex an. Dein Konto bleibt privat. Im Kompatibilitätsmodus wandelt dein Plex-Server Videos für iPhone und AirPlay in H.264/AAC um – auch aus anderen Containern und Codecs. Der Server muss Transcoding erlauben und die Quelle unterstützen. Geschützte Plex-Streamingangebote sind nicht enthalten.").font(.caption).foregroundStyle(.secondary)
            if !plex.authenticated {
                Button("Mit Plex verbinden",systemImage: "person.badge.key.fill") { Task { await plex.signIn() } }.buttonStyle(.borderedProminent).disabled(plex.busy)
            } else {
                HStack { Button("Server laden") { Task { await plex.loadServers() } }; Spacer(); Button("Trennen",role: .destructive) { Task { if cinema.provider == "plex" { await cinema.leave() }; plex.disconnect() } } }.font(.subheadline)
                if !plex.profileName.isEmpty { Text("Profil: " + plex.profileName).font(.subheadline.bold()) }
                if !plex.homeProfiles.isEmpty {
                    DisclosureGroup(plex.profileRequired ? "Plex-Profil wählen" : "Plex-Profil wechseln") {
                        ForEach(plex.homeProfiles) { profile in
                            Button(profile.title,systemImage: profile.protected ? "lock.fill" : "person.crop.circle") {
                                if profile.protected { selectedHome = profile; profilePIN = "" }
                                else { Task { if cinema.provider == "plex" { await cinema.leave() }; await plex.switchHomeProfile(profile) } }
                            }
                        }
                        if let profile = selectedHome {
                            SecureField("PIN für " + profile.title,text: $profilePIN).keyboardType(.numberPad)
                            Button("Profil entsperren") { Task { if cinema.provider == "plex" { await cinema.leave() }; await plex.switchHomeProfile(profile,pin: profilePIN); profilePIN = ""; selectedHome = nil } }.disabled(profilePIN.count != 4)
                        }
                    }
                }
                Picker("Wiedergabe",selection: $plex.playbackMode) { ForEach(PlexPlaybackMode.allCases) { Text($0.rawValue).tag($0) } }
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
    @State private var together = TVTogetherService.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Label(tv.connected ? "Fernseher verbunden" : "Fernseher verbinden",systemImage: "airplay.video").font(.headline)
            Text("Im iOS-Kontrollzentrum Bildschirm­synchronisierung wählen. RJ Love zeigt eine eigene TV-Oberfläche, dein iPhone bleibt die Fernbedienung. Die AirPlay-Taste am Player ist für direkte Videowiedergabe.").font(.footnote).foregroundStyle(.secondary)
            Picker("TV-Ansicht",selection: $tv.mode) { ForEach(TVMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("tv-mode-picker")
                .onChange(of: tv.mode) { _, mode in if [.moments,.wall,.dashboard].contains(mode) { Task { await tv.loadMoments() } } }
            NavigationLink { TVSettingsView() } label: { Label("AirPlay gestalten & Widgets sortieren",systemImage: "slider.horizontal.3") }.buttonStyle(.borderedProminent).accessibilityIdentifier("tv-customize")
            if tv.mode == .cinema { Toggle("Uhr & Schatzi-Infos neben dem Video",isOn: $tv.showInfo) }
            if tv.mode == .moments || tv.mode == .wall || tv.mode == .dashboard {
                if tv.mode == .wall || tv.mode == .dashboard { TVMomentWall(limit: 6).frame(height: 240) }
                else if let image = tv.image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 15)) }
                HStack {
                    Button("Zurück",systemImage: "backward.end.fill") { tv.advance(-1) }
                    Spacer()
                    Button(tv.slideshow ? "Diashow stoppen" : "Diashow starten") { tv.toggleSlideshow() }
                    Spacer()
                    Button("Weiter",systemImage: "forward.end.fill") { tv.advance(1) }
                }.font(.caption)
                Text("\(tv.moments.count) Fotos und Live-Photo-Standbilder").font(.caption).foregroundStyle(.secondary)
                if let error = tv.error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
            HStack {
                Button("Zusammen malen",systemImage: "pencil.tip") { tv.mode = .drawing }.accessibilityIdentifier("tv-open-drawing")
                Spacer()
                Button("Tic-Tac-Toe",systemImage: "square.grid.3x3") { tv.mode = .game }.accessibilityIdentifier("tv-open-game")
            }.buttonStyle(.bordered)
            Text("Live-Ansichten brauchen die geöffnete App. Akku und freigegebene Daten werden im Vordergrund aktualisiert. Plex kann im Hintergrund weiterspielen; eigene Dashboards und Spiele lassen sich bei gesperrter App nicht dauerhaft live halten.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
        if tv.mode == .drawing { TVDrawingRemote() }
        if tv.mode == .game { TVGameRemote() }
        TVSignalRemote()
    }
}
