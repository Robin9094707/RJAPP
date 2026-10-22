import MapKit
import SwiftUI

private enum DuftRoom: String, CaseIterable { case sammlung = "Sammlung", kalender = "Kalender", karte = "Karte", bilanz = "Bilanz" }
private enum DuftOrder: String, CaseIterable { case newest = "Neueste zuerst", oldest = "Älteste zuerst", stars = "Bestbewertet", longest = "Längste zuerst" }

struct FartStudioView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var calendarDate = Date.now
    @State private var selectedDay: Date?
    @State private var yearMode = false
    private var cal: Calendar { Calendar.autoupdatingCurrent }
    private func date(_ clip: FartClip) -> Date { dates[clip.id] ?? clip.date ?? .distantPast }
    private var clips: [FartClip] {
        let selected = app.farts.filter { clip in
            if owner == "mine" && clip.ownerID != app.me?.id { return false }
            if owner == "partner" && clip.ownerID == app.me?.id { return false }
            if category != "all" && clip.category != category { return false }
            if favorites && !clip.reactions.contains(where: { $0.userID == app.me?.id && $0.emoji == "❤️" }) { return false }
            let day = cal.startOfDay(for: date(clip))
            if useDates && (day < cal.startOfDay(for: from) || day > cal.startOfDay(for: until)) { return false }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let author = clip.ownerID == app.me?.id ? app.me?.displayName : app.partner?.displayName
                let haystack = [clip.title,clip.caption,clip.category,author ?? "",FartSituation(rawValue: clip.situation ?? "alltag")?.title ?? "",date(clip).formatted(date: .long, time: .shortened),date(clip).formatted(date: .numeric, time: .omitted),clip.recordedAt ?? clip.createdAt,clip.ratings.first?.comment ?? ""].joined(separator: " ")
                if !haystack.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines)) { return false }
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
    private var calendarClips: [FartClip] {
        clips.filter { clip in
            if let selectedDay { return cal.isDate(date(clip), inSameDayAs: selectedDay) }
            return cal.isDate(date(clip), equalTo: calendarDate, toGranularity: yearMode ? .year : .month)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("Duftstudio-Bereich", selection: $room) {
                    ForEach(DuftRoom.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("duft-room")
                if room == .kalender {
                    Picker("Kalenderansicht", selection: $yearMode) { Text("Monat").tag(false); Text("Jahr").tag(true) }
                        .pickerStyle(.segmented).accessibilityIdentifier("duft-calendar-scale")
                }
            }.padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if room == .sammlung { hero }
                    HStack {
                        NavigationLink {FartLibraryView()} label:{Label("Duftschatzkiste & Import",systemImage:"square.and.arrow.down")}
                        Spacer()
                        Menu {Button("Alle abspielen"){app.studio.startPlaylist(clips,api:app.api)};Button("Alle durcheinander"){app.studio.startPlaylist(clips,api:app.api,shuffle:true)};Button("Nur meine"){app.studio.startPlaylist(clips.filter{$0.ownerID==app.me?.id},api:app.api)};Button("Nur von meinem Lieblingsmenschen"){app.studio.startPlaylist(clips.filter{$0.ownerID != app.me?.id},api:app.api)}}label:{Image(systemName:"play.square.stack.fill")}.accessibilityLabel("Furz-Playlist")
                    }.font(.caption.bold())
                    if app.studio.queueCount>0{HStack{Text("Konzert · \(app.studio.queueIndex+1) / \(app.studio.queueCount)");Spacer();Button("Weiter"){app.studio.nextInPlaylist()};Button("Stoppen"){app.studio.stopPlayback()}}.font(.caption).padding(12).loveGlass(in:RoundedRectangle(cornerRadius:18))}
                    filters
                    if app.loadingFartArchive { ProgressView("Euer vollständiges Archiv wird geladen …").font(.footnote) }
                    switch room {
                    case .sammlung:
                        if clips.isEmpty { empty }
                        else { ForEach(clips) { clip in FartClipCard(clip: clip) } }
                    case .kalender:
                        FartCalendarPanel(clips: clips, date: $calendarDate, selectedDay: $selectedDay, yearMode: $yearMode)
                        HStack {
                            Text((selectedDay ?? calendarDate).formatted(selectedDay != nil ? .dateTime.day().month(.wide).year() : yearMode ? .dateTime.year() : .dateTime.month(.wide).year())).font(.headline)
                            Spacer()
                            Text("\(calendarClips.count)").font(.subheadline.bold()).foregroundStyle(LovePalette.violet)
                        }
                        if selectedDay != nil { Button("Alle Tage dieses Monats zeigen") { selectedDay = nil }.font(.caption) }
                        if calendarClips.isEmpty { empty }
                        else { ForEach(calendarClips) { clip in FartClipCard(clip: clip) } }
                    case .karte: FartAtlasView(clips: clips)
                    case .bilanz: FartInsightsView(clips: clips)
                    }
                    Text("Euer privates Baucharchiv. Nur ihr zwei hört mit.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.padding(20)
            }.accessibilityIdentifier("duft-archive-scroll").refreshable { _ = await app.syncNow(showErrors: true) }
            Button { app.openFartRecorder() } label: {
                Label(app.studio.draft == nil ? "Neues Meisterwerk aufnehmen" : "Deinen Entwurf fortsetzen", systemImage: app.studio.draft == nil ? "mic.fill" : "waveform").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).tint(LovePalette.violet)
                .padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial).accessibilityIdentifier("duft-record")
        }.background(LoveBackground()).navigationTitle("Duftstudio").navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: app.farts, initial: true) { _, value in dates = Dictionary(uniqueKeysWithValues: value.compactMap { clip in clip.date.map { (clip.id,$0) } }) }
            .onDisappear { app.fartArchiveVisible = false; app.studio.stopPlayback() }
            .onChange(of: yearMode) { _, _ in selectedDay = nil }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: room)
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LoveEyebrow(text: "Das kleine Naturkundemuseum eurer Liebe")
                Spacer(minLength: 0)
                Image(systemName: "heart.fill").foregroundStyle(LovePalette.pink).symbolEffect(.bounce, value: reduceMotion ? "" : room.rawValue)
            }
            Text("Für immer. Fürzeinander.").font(.system(size: 30, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("duft-archive-title")
            Text("Sammelt die kleinen Momente, findet alte Klassiker und entdeckt eure ganz eigene Wetterkarte.").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(app.farts.count) Werke", systemImage: "waveform")
                Label("\(Set(app.farts.compactMap { $0.date.map { cal.startOfDay(for: $0) } }).count) Tage", systemImage: "calendar")
            }.font(.caption.bold()).foregroundStyle(LovePalette.violet).fixedSize(horizontal: false, vertical: true)
        }.loveCard()
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Von wem?", selection: $owner) { Text("Von euch beiden").tag("all"); Text("Von mir").tag("mine"); Text("Von meinem Lieblingsmenschen").tag("partner") }
                    } label: { Label(owner == "all" ? "Wir beide" : owner == "mine" ? "Meine" : "Deine", systemImage: "person.2.fill") }
                    Menu {
                        Picker("Kategorie", selection: $category) { Text("Alle Kategorien").tag("all"); ForEach(FartCategory.allCases) { Text($0.emoji + " " + $0.rawValue).tag($0.rawValue) } }
                    } label: { Label(category == "all" ? "Alle Duftnoten" : category, systemImage: "wind") }
                    Button { favorites.toggle() } label: { Label("Lieblinge", systemImage: favorites ? "heart.fill" : "heart") }.tint(favorites ? LovePalette.pink : LovePalette.violet)
                    Button { showingDates = true } label: { Label(useDates ? "Zeitraum aktiv" : "Zeitraum", systemImage: "calendar") }
                }.font(.caption.bold()).buttonStyle(.bordered)
            }
            HStack {
                Text("\(clips.count) Treffer").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("duft-results")
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
            Button("Heute anzeigen") { date = .now; selectedDay = nil; yearMode = false }.font(.caption.bold())
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
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .long, time: .omitted) + ", \(amount) Aufnahmen")
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
                }.buttonStyle(.plain).accessibilityLabel(value.formatted(.dateTime.month(.wide).year()) + ", \(values[month] ?? 0) Aufnahmen")
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
