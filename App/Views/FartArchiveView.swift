import MapKit
import SwiftUI

private enum DuftRoom: String, CaseIterable { case sammlung = "Sammlung", kalender = "Kalender", karte = "Karte", bilanz = "Bilanz" }
private enum DuftOrder: String, CaseIterable { case newest = "Neueste zuerst", oldest = "Älteste zuerst", stars = "Bestbewertet", longest = "Längste zuerst" }

struct FartStudioView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filtersExpanded=false
    @State private var room: DuftRoom = .sammlung
    @State private var query = ""
    @State private var owner = "all"
    @State private var category = "all"
    @State private var favorites = false
    @State private var order: DuftOrder = .newest
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
    @State private var until = Date.now
    @State private var showingDates = false
    @State private var dates: [String: Date] = [:]
    /// Precomputed lowercase-insensitive search text per clip; formatting dates on every keystroke was the main cost.
    @State private var searchIndex: [String: String] = [:]
    @State private var calendarDate = Date.now
    @State private var selectedDay: Date?
    @State private var yearMode = false
    @State private var revealed = false
    @State private var mascotAwake = false
    private var cal: Calendar { Calendar.autoupdatingCurrent }
    private func date(_ clip: FartClip) -> Date { dates[clip.id] ?? clip.date ?? .distantPast }
    private var clips: [FartClip] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let me = app.me?.id
        let start = cal.startOfDay(for: from), end = cal.startOfDay(for: until)
        let selected = app.farts.filter { clip in
            if owner == "mine" && clip.ownerID != me { return false }
            if owner == "partner" && clip.ownerID == me { return false }
            if category != "all" && clip.category != category { return false }
            if favorites && !clip.reactions.contains(where: { $0.userID == me && $0.emoji == "❤️" }) { return false }
            if useDates {
                let day = cal.startOfDay(for: date(clip))
                if day < start || day > end { return false }
            }
            if !needle.isEmpty {
                let haystack = searchIndex[clip.id] ?? Self.searchText(clip, date: date(clip), author: clip.ownerID == me ? app.me?.displayName : app.partner?.displayName)
                if !haystack.localizedStandardContains(needle) { return false }
            }
            return true
        }
        return selected.sorted { a,b in
            switch order {
            case .newest: return date(a) == date(b) ? a.id > b.id : date(a) > date(b)
            case .oldest: return date(a) == date(b) ? a.id < b.id : date(a) < date(b)
            case .stars: return a.stars == b.stars ? date(a) > date(b) : (a.stars ?? 0) > (b.stars ?? 0)
            case .longest: return a.duration == b.duration ? date(a) > date(b) : a.duration > b.duration
            }
        }
    }
    private static func searchText(_ clip: FartClip, date: Date, author: String?) -> String {
        [clip.title,clip.caption,clip.category,author ?? "",FartSituation(rawValue: clip.situation ?? "alltag")?.title ?? "",date.formatted(date: .long, time: .shortened),date.formatted(date: .numeric, time: .omitted),clip.recordedAt ?? clip.createdAt,clip.ratings.first?.comment ?? ""].joined(separator: " ")
    }
    private func calendarClips(_ clips: [FartClip]) -> [FartClip] {
        clips.filter { clip in
            if let selectedDay { return cal.isDate(date(clip), inSameDayAs: selectedDay) }
            return cal.isDate(date(clip), equalTo: calendarDate, toGranularity: yearMode ? .year : .month)
        }
    }
    var body: some View {
        let visible = clips
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
                if room == .sammlung && query.isEmpty { hero.loveReveal(revealed, index: 0) }
                if room == .sammlung {
                    HStack(spacing:12) {
                        NavigationLink {FartLibraryView()} label:{Label("Schatzkiste & Import",systemImage:"square.and.arrow.down").frame(maxWidth:.infinity,minHeight:40)}
                        NavigationLink {EveningPlaylistView()} label:{Label("Abendplayer",systemImage:"play.square.stack.fill").frame(maxWidth:.infinity,minHeight:40)}.accessibilityIdentifier("evening-playlist-link")
                    }.font(.caption.bold()).buttonStyle(.bordered).loveReveal(revealed, index: 1)
                    HStack {
                        Button {Haptics.selection();favorites.toggle()} label:{Label("Lieblinge",systemImage:favorites ? "heart.fill":"heart").contentTransition(.symbolEffect(.replace))}.tint(favorites ? LovePalette.pink:LovePalette.violet)
                        Spacer()
                        Menu {Picker("Sortieren",selection:$order) {ForEach(DuftOrder.allCases,id:\.self) {Text($0.rawValue).tag($0)}}} label:{Label("Sortieren",systemImage:"arrow.up.arrow.down")}
                        Button {filtersExpanded=true;showingDates=true} label:{Image(systemName:"calendar")}.accessibilityLabel("Zeitraum filtern")
                    }.font(.subheadline).buttonStyle(.bordered).loveReveal(revealed, index: 2)
                }
                if app.studio.queueCount>0{HStack{Image(systemName:"music.note.list").foregroundStyle(LovePalette.violet);Text("Konzert · \(app.studio.queueIndex+1) / \(app.studio.queueCount)").contentTransition(.numericText());Spacer();Button("Weiter"){app.studio.nextInPlaylist()};Button("Stoppen"){app.studio.stopPlayback()}}.font(.caption).buttonStyle(.bordered).padding(12).loveGlass(in:RoundedRectangle(cornerRadius:18,style:.continuous)).transition(.move(edge:.top).combined(with:.opacity))}
                DisclosureGroup("Verfeinern · \(visible.count) Werke",isExpanded:$filtersExpanded){filters(count: visible.count).padding(.top,12)}.font(.subheadline.bold()).tint(LovePalette.violet).loveCard().loveReveal(revealed, index: 3)
                if app.loadingFartArchive { HStack(spacing: 10) { ProgressView(); Text("Euer vollständiges Archiv wird geladen …") }.font(.footnote).foregroundStyle(.secondary).transition(.opacity) }
                switch room {
                case .sammlung:
                    if visible.isEmpty { empty }
                    else { ForEach(visible) { clip in FartClipCard(clip: clip).loveScrollEffect() } }
                case .kalender:
                    let dayClips = calendarClips(visible)
                    FartCalendarPanel(clips: visible, date: $calendarDate, selectedDay: $selectedDay, yearMode: $yearMode)
                    HStack {
                        Text((selectedDay ?? calendarDate).formatted(selectedDay != nil ? .dateTime.day().month(.wide).year() : yearMode ? .dateTime.year() : .dateTime.month(.wide).year())).font(.headline)
                        Spacer()
                        Text("\(dayClips.count)").font(.subheadline.bold()).foregroundStyle(LovePalette.violet).contentTransition(.numericText())
                    }
                    if selectedDay != nil { Button("Alle Tage dieses Monats zeigen") { selectedDay = nil }.font(.caption) }
                    if dayClips.isEmpty { empty }
                    else { ForEach(dayClips) { clip in FartClipCard(clip: clip).loveScrollEffect() } }
                case .karte: FartAtlasView(clips: visible)
                case .bilanz: FartInsightsView(clips: visible)
                }
                Text("Euer privates Baucharchiv. Nur ihr zwei hört mit.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.padding(.horizontal, LoveMetrics.screenPadding).padding(.vertical, 14)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .id(room).scrollIndicators(.hidden).accessibilityIdentifier("duft-archive-scroll").refreshable { _ = await app.syncNow(showErrors: true) }
        .safeAreaInset(edge: .top, spacing: 0) { controlBar(results: visible.count) }
        .safeAreaInset(edge: .bottom, spacing: 0) { recordBar }
        .background(LoveBackground()).navigationTitle("Duftstudio").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Titel, Datum, Person, Jury-Kommentar …")
            .sheet(isPresented: $showingDates) { dateFilter }
            .task {
                app.fartArchiveVisible = true
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--preview-fart-calendar") { room = .kalender }
                if arguments.contains("--preview-fart-map") { room = .karte }
                if arguments.contains("--preview-fart-year") { room = .kalender }
                #endif
                await app.loadFartArchive()
            }
            .onAppear { revealed = true }
            .onChange(of: app.farts, initial: true) { _, value in rebuildIndex(value) }
            .onDisappear { app.fartArchiveVisible = false; if !EveningPlaylistService.shared.active {app.studio.stopPlayback()} }
            .onChange(of: yearMode) { _, _ in selectedDay = nil }
            .onChange(of: room) { _, _ in Haptics.selection() }
            .animation(reduceMotion ? nil : LoveMotion.gentle, value: room)
            .animation(reduceMotion ? nil : LoveMotion.fade, value: app.studio.queueCount)
            .animation(reduceMotion ? nil : LoveMotion.gentle, value: app.loadingFartArchive)
    }
    private func rebuildIndex(_ value: [FartClip]) {
        var nextDates: [String: Date] = [:]
        var nextIndex: [String: String] = [:]
        let me = app.me?.id
        for clip in value {
            let when = clip.date ?? .distantPast
            if let date = clip.date { nextDates[clip.id] = date }
            nextIndex[clip.id] = Self.searchText(clip, date: when, author: clip.ownerID == me ? app.me?.displayName : app.partner?.displayName)
        }
        dates = nextDates
        searchIndex = nextIndex
    }
    private func controlBar(results: Int) -> some View {
        VStack(spacing: 10) {
            Picker("Duftstudio-Bereich", selection: $room) {
                ForEach(DuftRoom.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("duft-room")
            if room == .kalender {
                HStack {
                    Picker("Kalenderansicht", selection: $yearMode) { Text("Monat").tag(false); Text("Jahr").tag(true) }
                        .pickerStyle(.segmented).accessibilityIdentifier("duft-calendar-scale")
                    Button("Heute") {
                        calendarDate = .now
                        selectedDay = nil
                        yearMode = false
                    }.font(.caption.bold()).buttonStyle(.bordered).accessibilityIdentifier("duft-calendar-today").accessibilityLabel("Heute anzeigen")
                }.transition(.opacity)
            }
            if !query.isEmpty {
                HStack {Text("\(results) Treffer").font(.caption.bold()).contentTransition(.numericText()).accessibilityIdentifier("duft-results");Spacer();Button("Suche leeren"){query=""}.font(.caption)}
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 4)
        .animation(reduceMotion ? nil : LoveMotion.spring, value: room == .kalender)
    }
    private var recordBar: some View {
        Button { Haptics.impact(.soft); app.openFartRecorder() } label: {
            Label(app.studio.draft == nil ? "Neues Meisterwerk aufnehmen" : "Deinen Entwurf fortsetzen", systemImage: app.studio.draft == nil ? "mic.fill" : "waveform")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
        }.buttonStyle(.borderedProminent).controlSize(.large).tint(LovePalette.violet)
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8).accessibilityIdentifier("duft-record")
    }
    private var hero: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.center,spacing:10) {
                VStack(alignment:.leading,spacing:10) {
                    LoveEyebrow(text:"Kleine Kunst. Große Liebe.", tint: LovePalette.violet)
                    Text("Dein Duftstudio.").font(.loveDisplay(30)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("duft-archive-title")
                    Text("Ein privates Tonstudio für euren ganz eigenen Humor.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                PuffMascot(active:mascotAwake).frame(width:84,height:92).clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.impact(.light)
                        mascotAwake = true
                        Task { try? await Task.sleep(for: .seconds(2.4)); mascotAwake = false }
                    }
                    .accessibilityHidden(true)
            }
            HStack(spacing:10) {
                studioStat(app.farts.count,"Meisterwerke","cloud.fill")
                studioStat(Set(app.farts.compactMap{$0.date.map{cal.startOfDay(for:$0)}}).count,"Dufttage","calendar")
                studioStat(app.farts.reduce(0){$0+($1.commentCount ?? 0)},"Kommentare","bubble.left.fill")
            }
        }.loveCard()
    }
    private func studioStat(_ value:Int,_ title:String,_ symbol:String)->some View {
        VStack(alignment:.leading,spacing:7){
            Image(systemName:symbol).symbolRenderingMode(.hierarchical).foregroundStyle(LovePalette.violet)
            Text(value.formatted()).font(.system(.title2,design:.rounded).bold()).contentTransition(.numericText(value: Double(value))).animation(LoveMotion.snappy, value: value)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
            .background(LinearGradient(colors:[LovePalette.violet.opacity(0.12),LovePalette.violet.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .accessibilityElement(children:.combine)
    }
    private func filters(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Von wem?", selection: $owner) { Text("Von euch beiden").tag("all"); Text("Von mir").tag("mine"); Text("Von meinem Lieblingsmenschen").tag("partner") }
                    } label: { Label(owner == "all" ? "Wir beide" : owner == "mine" ? "Meine" : "Deine", systemImage: "person.2.fill") }
                    Menu {
                        Picker("Kategorie", selection: $category) { Text("Alle Kategorien").tag("all"); ForEach(FartCategory.allCases) { Text($0.emoji + " " + $0.rawValue).tag($0.rawValue) } }
                    } label: { Label(category == "all" ? "Alle Duftnoten" : category, systemImage: "wind") }
                    Button { Haptics.selection(); favorites.toggle() } label: { Label("Lieblinge", systemImage: favorites ? "heart.fill" : "heart") }.tint(favorites ? LovePalette.pink : LovePalette.violet)
                    Button { showingDates = true } label: { Label(useDates ? "Zeitraum aktiv" : "Zeitraum", systemImage: "calendar") }
                }.font(.caption.bold()).buttonStyle(.bordered).padding(.vertical, 2)
            }
            HStack {
                Text("\(count) Treffer").font(.caption).foregroundStyle(.secondary).contentTransition(.numericText()).accessibilityIdentifier(query.isEmpty ? "duft-results":"duft-filter-results")
                Spacer()
                Menu { Picker("Sortieren", selection: $order) { ForEach(DuftOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { Label(order.rawValue, systemImage: "arrow.up.arrow.down").font(.caption) }
            }
            if useDates { Text(from.formatted(date: .abbreviated, time: .omitted) + " bis " + until.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(LovePalette.violet) }
        }
    }
    private var empty: some View {
        ContentUnavailableView("Hier ist noch frische Luft.", systemImage: "wind", description: Text("Passe deine Suche an oder nehmt euer nächstes Meisterwerk auf."))
    }
    private var dateFilter: some View {
        NavigationStack {
            Form {
                Toggle("Aufnahmezeitraum filtern", isOn: $useDates)
                DatePicker("Von", selection: $from, in: ...until, displayedComponents: .date).disabled(!useDates)
                DatePicker("Bis", selection: $until, in: from...Date.now, displayedComponents: .date).disabled(!useDates)
                Button("Filter zurücksetzen") { useDates = false; query = ""; owner = "all"; category = "all"; favorites = false }
            }.navigationTitle("Euer Zeitraum").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showingDates = false } } }
        }.presentationDetents([.medium,.large])
    }
}

struct FartCalendarPanel: View {
    let clips: [FartClip]
    @Binding var date: Date
    @Binding var selectedDay: Date?
    @Binding var yearMode: Bool
    private var cal: Calendar { Calendar.autoupdatingCurrent }
    private var first: Date { cal.date(from: cal.dateComponents([.year,.month], from: date))! }
    private var counts: [Date: Int] { Dictionary(grouping: clips.compactMap(\.date), by: { cal.startOfDay(for: $0) }).mapValues(\.count) }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }.accessibilityLabel(yearMode ? "Vorheriges Jahr" : "Vorheriger Monat")
                Spacer(minLength: 0)
                Text(date.formatted(yearMode ? .dateTime.year() : .dateTime.month(.wide).year())).font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("duft-calendar-heading")
                Spacer(minLength: 0)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }.accessibilityLabel(yearMode ? "Nächstes Jahr" : "Nächster Monat")
            }.buttonStyle(.bordered)
            if yearMode { yearGrid } else { monthGrid }
        }.padding(12).frame(maxWidth: .infinity).loveGlass(in: RoundedRectangle(cornerRadius: 26))
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-fart-year") { yearMode = true }
                #endif
            }
    }
    private func move(_ direction: Int) {
        date = cal.date(byAdding: yearMode ? .year : .month, value: direction, to: first) ?? date
        selectedDay = nil
    }
    private var monthGrid: some View {
        let byDay = counts
        let leading = (cal.component(.weekday, from: first)-cal.firstWeekday+7)%7
        let length = cal.range(of: .day, in: .month, for: first)!.count
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<7) { index in Text(symbols[(index+cal.firstWeekday-1)%7]).font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<((leading+length+6)/7)*7, id: \.self) { index in
                    if index >= leading && index < leading+length {
                        let day = cal.date(byAdding: .day, value: index-leading, to: first)!
                        let amount = byDay[cal.startOfDay(for: day)] ?? 0
                        let chosen = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                        Button { selectedDay = chosen ? nil : day } label: {
                            VStack(spacing: 3) {
                                Text(String(index-leading+1)).font(.system(.subheadline, design: .rounded, weight: chosen || amount>0 ? .bold : .regular))
                                Text(amount>0 ? String(amount) : " ").font(.system(size: 9, weight: .bold)).opacity(amount>0 ? 1 : 0)
                            }.frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(chosen ? Color.white : amount>0 ? LovePalette.violet : Color.primary)
                                .background(chosen ? LovePalette.violet : amount>0 ? LovePalette.violet.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                                .overlay { if cal.isDateInToday(day) { RoundedRectangle(cornerRadius: 12).stroke(LovePalette.pink, lineWidth: 1) } }
                        }.buttonStyle(.lovePress).accessibilityLabel(day.formatted(date: .long, time: .omitted) + ", \(amount) Aufnahmen")
                    } else { Color.clear.frame(height: 46).accessibilityHidden(true) }
                }
            }
        }
    }
    private var yearGrid: some View {
        let year = cal.component(.year, from: date)
        let values = Dictionary(grouping: clips.compactMap(\.date).filter { cal.component(.year, from: $0)==year }, by: { cal.component(.month, from: $0) }).mapValues(\.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 8),count: 3),spacing: 8) {
            ForEach(1...12,id: \.self) { month in
                let value = cal.date(from: DateComponents(year: year,month: month,day: 1))!
                Button { date = value; selectedDay = nil; yearMode = false } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(value.formatted(.dateTime.month(.abbreviated))).font(.caption.bold())
                        Text(String(values[month] ?? 0)).font(.system(.title3,design: .rounded,weight: .bold))
                        Text("Aufnahmen").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity,alignment: .leading).padding(10)
                        .background(LovePalette.violet.opacity(values[month] == nil ? 0.04 : 0.15),in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.lovePress).accessibilityLabel(value.formatted(.dateTime.month(.wide).year()) + ", \(values[month] ?? 0) Aufnahmen")
            }
        }
    }
}

struct FartAtlasView: View {
    let clips: [FartClip]
    @State private var selection: String?
    private var located: [FartClip] { clips.filter { $0.location != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Eure Furzkarte", systemImage: "map.fill").font(.title3.bold()).accessibilityIdentifier("duft-map-title")
            Text("Kleine Geschichten, echte Orte. Tippe auf eine Markierung, um das Meisterwerk zu öffnen.").font(.subheadline).foregroundStyle(.secondary)
            if located.isEmpty {
                ContentUnavailableView("Noch kein Lüftchen verortet.", systemImage: "mappin.slash", description: Text("Du kannst beim Senden einer neuen Aufnahme ihren zuvor erfassten Ort ausdrücklich mitgeben. Alte Aufnahmen erhalten keinen erfundenen Standort."))
            } else {
                Map(initialPosition: .automatic, selection: $selection) {
                    ForEach(located) { clip in
                        if let point = clip.location {
                            Marker(clip.title, systemImage: "wind", coordinate: CLLocationCoordinate2D(latitude: point.latitude,longitude: point.longitude)).tint(LovePalette.violet).tag(clip.id)
                        }
                    }
                }.mapControls { MapCompass(); MapScaleView() }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 26))
                Text("\(located.count) mit Ort · \(clips.count-located.count) ohne Ort").font(.caption).foregroundStyle(.secondary)
                ForEach(located) { clip in Button { selection = clip.id } label: { Label(clip.title, systemImage: "mappin.circle.fill").frame(maxWidth: .infinity,alignment: .leading) }.buttonStyle(.bordered) }
            }
        }.sheet(item: Binding(get: { located.first { $0.id == selection } }, set: { selection = $0?.id })) { clip in
            NavigationStack {
                ScrollView { FartClipCard(clip: clip).padding(20) }.background(LoveBackground()).navigationTitle("Duftpost am Ort").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { selection = nil } } }
            }
        }
    }
}

struct FartInsightsView: View {
    let clips: [FartClip]
    @Environment(AppState.self) private var app
    private var rated: [Int] { clips.compactMap(\.stars) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Eure kleine Duftbilanz").font(.title3.bold())
            Text("Alle Zahlen beziehen sich auf deine aktuelle Suche und Filter.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())],spacing: 12) {
                LoveMetric(title: "Meisterwerke", value: String(clips.count), symbol: "waveform", tint: LovePalette.violet)
                LoveMetric(title: "Sekunden Geschichte", value: String(format: "%.1f",clips.reduce(0) { $0+$1.duration }), symbol: "timer", tint: LovePalette.pink)
                LoveMetric(title: "Tage mit Duftpost", value: String(Set(clips.compactMap { $0.date.map { Calendar.current.startOfDay(for: $0) } }).count), symbol: "calendar", tint: LovePalette.cyan)
                LoveMetric(title: "Jury-Durchschnitt", value: rated.isEmpty ? "–" : String(format: "%.1f / 5",Double(rated.reduce(0,+))/Double(rated.count)), symbol: "star.fill", tint: LovePalette.coral)
            }
            ForEach([app.me?.id ?? "robin",app.partner?.id ?? "raphaela"],id: \.self) { id in
                let own = clips.filter { $0.ownerID == id }
                HStack {
                    PartnerAvatar(name: id == app.me?.id ? app.me?.displayName ?? "Du" : app.partner?.displayName ?? "Schatzi",size: 42)
                    VStack(alignment: .leading,spacing: 4) { Text(id == app.me?.id ? "Deine Naturtalente" : "Die deines Lieblingsmenschen").font(.subheadline.bold()); Text("\(own.count) Aufnahmen · \(own.filter { $0.stars != nil }.count) bewertet").font(.caption).foregroundStyle(.secondary) }
                }.loveCard()
            }
            if let best = clips.filter({ $0.stars != nil }).max(by: { ($0.stars ?? 0) < ($1.stars ?? 0) }) {
                Label("Von der Jury gefeiert", systemImage: "trophy.fill").font(.headline).foregroundStyle(LovePalette.coral)
                FartClipCard(clip: best)
            }
        }
    }
}
