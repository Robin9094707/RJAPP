import Charts
import SwiftUI

private enum DiaryMode: String, CaseIterable, Identifiable { case day = "Tag", pages = "Seiten", insights = "Einblicke", review = "Rückblick"; var id: String { rawValue } }

/// Unser Tagebuch: one shared page per day, a personal page each, private pages that stay on the iPhone,
/// and optional ChatGPT help for writing and looking back.
struct DiaryView: View {
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var mode: DiaryMode = .day
    @State private var day = Date.now
    @State private var query = ""
    @State private var editing: DiaryEditorRoute?
    @State private var reading: DiaryPage?
    @State private var loadedArchive = false
    @State private var privateUnlocked = false
    @State private var askDiary = false
    private var cal: Calendar { .current }
    private var privateHidden: Bool { DiaryLock.enabled && !privateUnlocked }
    private var dayKey: String { DiaryDay.key(day) }
    private var partnerName: String { app.partner?.displayName ?? "Dein Lieblingsmensch" }

    var body: some View {
        let pages = app.diaryPages().filter { !privateHidden || $0.visibility != .privateOnly }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
                hero(pages)
                Picker("Ansicht", selection: $mode) { ForEach(DiaryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                switch mode {
                case .day: dayView(pages.filter { $0.day == dayKey })
                case .pages: allPages(pages)
                case .insights: DiaryInsightsPanel(pages: pages) { askDiary = true }
                case .review: DiaryReviewPanel(pages: pages)
                }
                if privateHidden {
                    Button { Task { privateUnlocked = await DiaryLock.unlock() } } label: {
                        Label("Private Seiten mit Face ID zeigen", systemImage: "lock.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(LovePalette.violet)
                }
                Text("Gemeinsame Seiten und „Für uns“ liegen auf eurem eigenen Server. Private Seiten bleiben nur auf diesem iPhone.")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(.horizontal, LoveMetrics.screenPadding).padding(.vertical, 14)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LoveBackground()).navigationTitle("Unser Tagebuch").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(DiaryVisibility.allCases) { visibility in
                        Button(visibility.title, systemImage: visibility.symbol) { write(visibility) }
                    }
                    Button("Sprach-Tagebuch", systemImage: "mic.fill") { editing = DiaryEditorRoute(day: dayKey, visibility: .shared, startVoice: true) }
                    Divider()
                    Toggle("Private Seiten mit Face ID schützen", systemImage: "faceid", isOn: Binding(get: { DiaryLock.enabled }, set: { value in
                        Task { if await DiaryLock.unlock() { DiaryLock.enabled = value; privateUnlocked = !value } }
                    }))
                } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("Neue Tagebuchseite")
            }
        }
        .refreshable { _ = await app.syncNow(showErrors: false); await app.loadRecordArchive(kind: .diary) }
        .task {
            guard !loadedArchive else { return }
            loadedArchive = true
            await app.loadRecordArchive(kind: .diary)
            if ai.signedIn && ai.serverStatus == nil { await ai.loadStatus(api: app.api) }
        }
        .sheet(item: $editing) { route in DiaryEditorView(route: route) }
        .navigationDestination(isPresented: $askDiary) { AIChatEntryView(starter: "Lies mein Tagebuch der letzten Wochen: Welche Muster, Stimmungen und wiederkehrenden Themen fallen dir auf? Was hat mir gutgetan, was hat mich belastet? Antworte liebevoll und konkret mit Bezug auf einzelne Einträge.") }
        .sheet(item: $reading) { page in DiaryReaderView(page: page) { editing = DiaryEditorRoute(page: page) } }
    }

    // MARK: Hero

    private func hero(_ pages: [DiaryPage]) -> some View {
        let days = Set(pages.map(\.day))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    LoveEyebrow(text: "Unsere Geschichte, Seite für Seite", tint: LovePalette.violet)
                    Text("Unser Tagebuch.").font(.loveDisplay(32))
                    Text(streakText(days)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                LoveIcon(symbol: "book.pages.fill", tint: LovePalette.violet, size: 56)
            }
            weekStrip(pages)
            HStack(spacing: 10) {
                stat(pages.count, "Seiten", "doc.text.fill")
                stat(days.count, "Tage", "calendar")
                stat(pages.reduce(0) { $0 + $1.words }, "Wörter", "text.word.spacing")
            }
        }.loveCard()
    }

    private func streakText(_ days: Set<String>) -> String {
        var streak = 0
        var cursor = Date.now
        if !days.contains(DiaryDay.key(cursor)) { cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        while days.contains(DiaryDay.key(cursor)) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        if streak >= 2 { return "\(streak) Tage in Folge geschrieben. Wunderschön." }
        return days.contains(DiaryDay.key(.now)) ? "Heute habt ihr schon geschrieben." : "Ein paar Zeilen für heute?"
    }

    private func weekStrip(_ pages: [DiaryPage]) -> some View {
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        let moods = Dictionary(grouping: pages, by: \.day)
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: start) ?? start
                let key = DiaryDay.key(date)
                let selected = key == dayKey && mode == .day
                let entries = moods[key] ?? []
                Button { day = date; mode = .day; Haptics.selection() } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(selected ? .white : .secondary)
                        Text(entries.first(where: { !$0.mood.isEmpty })?.mood ?? (entries.isEmpty ? "·" : "✍️")).font(.system(size: 17))
                        Text(date.formatted(.dateTime.day())).font(.caption2.monospacedDigit()).foregroundStyle(selected ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(selected ? AnyShapeStyle(LovePalette.violet) : AnyShapeStyle(LovePalette.violet.opacity(entries.isEmpty ? 0.04 : 0.12)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.lovePress).accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (entries.isEmpty ? ", keine Seite" : ", \(entries.count) Seiten"))
            }
        }
    }

    private func stat(_ value: Int, _ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(LovePalette.violet)
            Text(value.formatted()).font(.system(.title3, design: .rounded).bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(LovePalette.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    // MARK: Day

    @ViewBuilder private func dayView(_ pages: [DiaryPage]) -> some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }.accessibilityLabel("Vorheriger Tag")
            Spacer(minLength: 0)
            DatePicker("Tag", selection: $day, in: ...Date.now, displayedComponents: .date).labelsHidden()
            Spacer(minLength: 0)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }.disabled(cal.isDateInToday(day)).accessibilityLabel("Nächster Tag")
        }.buttonStyle(.bordered)

        let together = pages.filter { $0.visibility == .together }
        let mine = pages.filter { $0.visibility == .privateOnly || ($0.visibility == .shared && $0.ownerID == app.me?.id) }
        let partner = pages.filter { $0.visibility == .shared && $0.ownerID != app.me?.id }

        section("Unsere gemeinsame Seite", symbol: "person.2.fill", tint: LovePalette.pink) {
            if together.isEmpty {
                Text("Eine Seite, die ihr beide weiterschreiben könnt.").font(.subheadline).foregroundStyle(.secondary)
                AdaptiveLoveRow {
                    Button("Gemeinsam beginnen", systemImage: "pencil") { write(.together) }.buttonStyle(.borderedProminent).tint(LovePalette.pink)
                    if ai.signedIn { Button("Mit KI aus eurem Tag", systemImage: "wand.and.sparkles") { editing = DiaryEditorRoute(day: dayKey, visibility: .together, autoCompose: true) }.buttonStyle(.bordered) }
                }
            }
            ForEach(together) { page in pageCard(page) }
        }
        section("Deine Seite", symbol: "heart.text.square.fill", tint: LovePalette.violet) {
            if mine.isEmpty {
                Text(cal.isDateInToday(day) ? "Wie war dein Tag? Ein Satz genügt." : "Für diesen Tag hast du nichts geschrieben.").font(.subheadline).foregroundStyle(.secondary)
                AdaptiveLoveRow {
                    Button("Schreiben", systemImage: "pencil") { write(.shared) }.buttonStyle(.borderedProminent).tint(LovePalette.violet)
                    Button("Privat schreiben", systemImage: "lock.fill") { write(.privateOnly) }.buttonStyle(.bordered)
                }
            }
            ForEach(mine) { page in pageCard(page) }
        }
        section(partnerName + " schreibt", symbol: "heart.fill", tint: LovePalette.coral) {
            if partner.isEmpty { Text("Noch keine Seite von \(partnerName) an diesem Tag.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(partner) { page in pageCard(page) }
        }
        DiaryPromptCard(day: dayKey) { prompt in editing = DiaryEditorRoute(day: dayKey, visibility: .shared, prompt: prompt) }
        VStack(alignment: .leading, spacing: 10) {
            Label("Geführt schreiben", systemImage: "list.bullet.rectangle.portrait.fill").font(.caption.bold()).foregroundStyle(LovePalette.violet)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { editing = DiaryEditorRoute(day: dayKey, visibility: .shared, startVoice: true) } label: { templateChip("Sprechen", "mic.fill", LovePalette.pink) }.buttonStyle(.lovePress)
                    ForEach(DiaryTemplate.allCases.filter { $0 != .free }) { template in
                        Button { editing = DiaryEditorRoute(day: dayKey, visibility: template == .worries || template == .dreams ? .privateOnly : .shared, template: template) } label: { templateChip(template.title, template.symbol, LovePalette.violet) }.buttonStyle(.lovePress)
                    }
                }
            }
        }.loveCard()
        NavigationLink { SharedJournalView(initialDay: day) } label: {
            Label("Momente & Aktivität dieses Tages", systemImage: "sparkles.rectangle.stack").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered)
    }

    private func templateChip(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
        }.frame(width: 92, height: 72).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func section<Content: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
            content()
        }.loveCard()
    }

    private func pageCard(_ page: DiaryPage) -> some View {
        Button { reading = page } label: { DiaryPageRow(page: page, author: author(page), compact: false) }.buttonStyle(.lovePress)
    }

    private func author(_ page: DiaryPage) -> String {
        switch page.visibility {
        case .privateOnly: return "Privat · nur du"
        case .together: return "Gemeinsam" + (page.ownerID == app.me?.id ? " · begonnen von dir" : " · begonnen von \(partnerName)")
        case .shared: return page.ownerID == app.me?.id ? "Du" : partnerName
        }
    }

    private func move(_ delta: Int) { if let date = cal.date(byAdding: .day, value: delta, to: day), date <= .now { day = date } }

    private func write(_ visibility: DiaryVisibility) {
        if visibility == .together, let existing = app.togetherPage(on: dayKey) { editing = DiaryEditorRoute(page: DiaryPage(record: existing)); return }
        editing = DiaryEditorRoute(day: dayKey, visibility: visibility)
    }

    // MARK: All pages

    @ViewBuilder private func allPages(_ pages: [DiaryPage]) -> some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Im Tagebuch suchen", text: $query).textInputAutocapitalization(.never)
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Suche leeren") }
        }.padding(12).loveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty ? pages : pages.filter { ($0.title + " " + $0.text + " " + $0.notes + " " + $0.mood).localizedStandardContains(needle) }
        if filtered.isEmpty {
            ContentUnavailableView(needle.isEmpty ? "Noch leer" : "Nichts gefunden", systemImage: "book.closed", description: Text(needle.isEmpty ? "Eure erste Seite wartet." : "Probiere ein anderes Wort."))
        }
        let months = Dictionary(grouping: filtered) { String($0.day.prefix(7)) }
        ForEach(months.keys.sorted(by: >), id: \.self) { month in
            Text(DiaryDay.date(month + "-01")?.formatted(.dateTime.month(.wide).year()) ?? month).font(.title3.bold()).padding(.top, 6)
            ForEach(months[month] ?? []) { page in
                Button { reading = page } label: { DiaryPageRow(page: page, author: author(page), compact: true).loveCard() }.buttonStyle(.lovePress)
            }
        }
    }
}

struct DiaryPageRow: View {
    let page: DiaryPage
    let author: String
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(page.mood.isEmpty ? "📖" : page.mood).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(.headline).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Image(systemName: page.visibility.symbol)
                        Text(author)
                        if compact { Text("· " + page.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) }
                        if page.aiAssisted { Image(systemName: "wand.and.sparkles").accessibilityLabel("Mit KI geschrieben") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            if !page.prompt.isEmpty { Text("„\(page.prompt)“").font(.caption.italic()).foregroundStyle(LovePalette.violet).lineLimit(2) }
            if !page.location.isEmpty || !page.tags.isEmpty {
                HStack(spacing: 8) {
                    if !page.location.isEmpty { Label(page.location, systemImage: "mappin").lineLimit(1) }
                    if !page.tags.isEmpty { Text(page.tags.prefix(3).map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
                }.font(.caption2).foregroundStyle(LovePalette.cyan)
            }
            if !page.text.isEmpty { Text(page.text).font(.subheadline).foregroundStyle(.primary.opacity(0.85)).lineLimit(compact ? 3 : 6).multilineTextAlignment(.leading) }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

// MARK: - Reader

struct DiaryReaderView: View {
    let page: DiaryPage
    let edit: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var reflection: String?
    @State private var reflecting = false
    private var editable: Bool { page.visibility != .shared || page.ownerID == app.me?.id }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        LoveEyebrow(text: page.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()), tint: LovePalette.violet)
                        HStack(alignment: .top) {
                            Text(page.title).font(.loveDisplay(30)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if !page.mood.isEmpty { Text(page.mood).font(.system(size: 40)) }
                        }
                        Label(page.visibility.title, systemImage: page.visibility.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                    if !page.prompt.isEmpty {
                        Text("„\(page.prompt)“").font(.system(.title3, design: .serif).italic()).foregroundStyle(LovePalette.violet)
                    }
                    Text(page.text).font(.system(.body, design: .serif)).lineSpacing(6).textSelection(.enabled)
                    if !page.location.isEmpty || !page.context.isEmpty || !page.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !page.location.isEmpty { Label(page.location, systemImage: "mappin.and.ellipse").font(.subheadline) }
                            if !page.context.isEmpty { Label(page.context, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                            if !page.tags.isEmpty { Text(page.tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption.weight(.semibold)).foregroundStyle(LovePalette.violet) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(LovePalette.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if page.notes.isEmpty, AICompanion.shared.signedIn, !page.text.isEmpty {
                        if let reflection {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Gespiegelt von ChatGPT", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                                Text(reflection).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LovePalette.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            Button { Task { reflecting = true; reflection = try? await DiaryAI.reflection(text: page.text, app: app); reflecting = false } } label: {
                                HStack { if reflecting { ProgressView().controlSize(.small) }; Label("Spiegeln lassen", systemImage: "sparkles") }.frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).tint(LovePalette.violet).disabled(reflecting)
                        }
                    }
                    if !page.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Ein Gedanke dazu", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                            Text(page.notes).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LovePalette.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Text("\(page.words) Wörter · zuletzt \(page.updatedAt.formatted(date: .abbreviated, time: .shortened))" + (page.aiAssisted ? " · mit KI-Hilfe" : "")).font(.caption2).foregroundStyle(.secondary)
                }.padding(LoveMetrics.screenPadding).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(LoveBackground()).navigationTitle("Tagebuch").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                if editable {
                    ToolbarItem(placement: .confirmationAction) { Button("Bearbeiten") { dismiss(); Task { try? await Task.sleep(for: .milliseconds(350)); edit() } } }
                    ToolbarItem(placement: .bottomBar) { Button("Seite löschen", systemImage: "trash", role: .destructive) { deleting = true } }
                }
            }
            .confirmationDialog("Diese Seite löschen?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { Task { if await app.deleteDiary(page) { dismiss() } } }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text(page.visibility == .privateOnly ? "Die private Seite wird von diesem iPhone entfernt." : "Die Seite wird für euch beide entfernt.") }
        }.presentationDragIndicator(.visible)
    }
}

// MARK: - Daily prompt

struct DiaryPromptCard: View {
    let day: String
    let write: (String) -> Void
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var prompt: String?
    @State private var loading = false
    @State private var offset = 0
    private static let prompts = [
        "Wofür bist du heute dankbar?", "Welcher Moment heute hat dich zum Lächeln gebracht?", "Was hat dein Lieblingsmensch heute Schönes getan?",
        "Was möchtest du morgen anders machen?", "Welches Gefühl hat deinen Tag bestimmt?", "Worauf freust du dich gerade am meisten?",
        "Was hast du heute über dich gelernt?", "Welche kleine Geste würde euch morgen guttun?", "Was war heute überraschend?",
        "Welcher Satz beschreibt euren Tag am besten?",
    ]
    private var fallback: String {
        let seed = day.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.prompts.count
        return Self.prompts[(seed + offset) % Self.prompts.count]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Frage für heute", systemImage: "questionmark.bubble.fill").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                Spacer()
                Button { offset += 1; prompt = nil } label: { Image(systemName: "shuffle") }.accessibilityLabel("Andere Frage")
                if ai.signedIn {
                    Button { Task { await personal() } } label: { if loading { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.sparkles") } }
                        .disabled(loading).accessibilityLabel("Persönliche Frage mit KI")
                }
            }
            Text(prompt ?? fallback).font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Button("Darauf antworten", systemImage: "pencil") { write(prompt ?? fallback) }.buttonStyle(.bordered).tint(LovePalette.violet)
        }.loveCard()
    }
    private func personal() async {
        loading = true
        defer { loading = false }
        let answer = try? await ai.ask("Stelle mir genau eine kurze, persönliche Tagebuchfrage für heute Abend, passend zu dem, was bei uns in letzter Zeit los war. Nur die Frage, ohne Anführungszeichen.", system: "Du hilfst beim Tagebuchschreiben.", app: app, includeContext: true)
        if let answer, !answer.isEmpty { prompt = answer.trimmingCharacters(in: CharacterSet(charactersIn: "\"„“ \n")) }
    }
}

// MARK: - Review

private enum ReviewSpan: String, CaseIterable, Identifiable { case week = "Woche", month = "Monat", year = "Jahr"; var id: String { rawValue }
    var days: Int { switch self { case .week: 7; case .month: 31; case .year: 365 } }
}

struct DiaryReviewPanel: View {
    let pages: [DiaryPage]
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var span: ReviewSpan = .week
    @State private var includePrivate = false
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false

    private var selection: [DiaryPage] {
        let since = DiaryDay.key(Calendar.current.date(byAdding: .day, value: -span.days, to: .now) ?? .now)
        let partnerShares = ai.serverStatus?.partnerSharing == true
        return pages.filter { page in
            guard page.day >= since else { return false }
            if page.visibility == .privateOnly { return includePrivate }
            if page.visibility == .shared && page.ownerID != app.me?.id { return partnerShares }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Euer Rückblick", systemImage: "sparkles").font(.headline).foregroundStyle(LovePalette.violet)
                Picker("Zeitraum", selection: $span) { ForEach(ReviewSpan.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Toggle("Meine privaten Seiten einbeziehen", isOn: $includePrivate)
                Text("\(selection.count) Seiten im Zeitraum" + (ai.serverStatus?.partnerSharing == true ? "" : " · Seiten deines Lieblingsmenschen erst nach dessen KI-Freigabe")).font(.caption).foregroundStyle(.secondary)
                if ai.signedIn {
                    Button { Task { await generate() } } label: {
                        HStack { if busy { ProgressView().tint(.white) }; Label(busy ? "Euer Rückblick entsteht …" : "Rückblick schreiben", systemImage: "wand.and.sparkles").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).tint(LovePalette.violet).controlSize(.large).disabled(busy || selection.isEmpty)
                } else { AISignInPrompt() }
            }.loveCard()
            if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            if !text.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    LoveEyebrow(text: "Mit KI formuliert", tint: LovePalette.violet)
                    Text(AIChatBubble.rendered(text)).font(.system(.body, design: .serif)).lineSpacing(5).textSelection(.enabled)
                    if !busy {
                        AdaptiveLoveRow {
                            Button(saved ? "Gespeichert ✓" : "Als gemeinsame Seite speichern", systemImage: "book.pages") { Task { await save() } }.buttonStyle(.bordered).disabled(saved)
                            Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }.buttonStyle(.bordered)
                        }
                    }
                }.loveCard()
            }
        }
        .onChange(of: span) { _, _ in text = ""; saved = false }
    }

    private func generate() async {
        busy = true; error = nil; text = ""; saved = false
        defer { busy = false }
        let source = selection.sorted { $0.day < $1.day }.map { page -> String in
            "[" + page.day + "] " + who(page) + " " + page.mood + " " + page.title + ": " + String(page.text.prefix(1500))
        }.joined(separator: "\n")
        let prompt = "Hier sind unsere Tagebuchseiten der letzten \(span.rawValue):\n\n\(source)\n\nSchreibe einen liebevollen Rückblick mit einer Überschrift, 3–5 kurzen Abschnitten zu den schönsten Momenten und Themen, einem Muster, das dir auffällt, und einer Frage für unser nächstes Gespräch. Höchstens 350 Wörter."
        do {
            text = try await ai.ask(prompt, system: "Du schreibst einfühlsame Tagebuch-Rückblicke für ein Paar. Nutze nur die gelieferten Seiten, erfinde nichts. Private Seiten nur sinngemäß und behutsam verwenden.", app: app, includeContext: false) { value in text = value }
        } catch { self.error = error.localizedDescription }
    }

    private func who(_ page: DiaryPage) -> String {
        switch page.visibility {
        case .privateOnly: return "privat"
        case .together: return "gemeinsam"
        case .shared: return page.ownerID == app.me?.id ? (app.me?.displayName ?? "ich") : (app.partner?.displayName ?? "Partner")
        }
    }

    private func save() async {
        let page = DiaryPage(entry: PrivateDiaryEntry(day: DiaryDay.key(.now), title: "Unser Rückblick · \(span.rawValue)", text: text, aiAssisted: true))
        if let existing = app.togetherPage(on: page.day) {
            var merged = DiaryPage(record: existing)
            merged.text += "\n\n— Rückblick —\n" + text
            merged.aiAssisted = true
            saved = await app.saveDiary(merged, visibility: .together, existingID: existing.id)
        } else {
            saved = await app.saveDiary(page, visibility: .together, existingID: nil)
        }
    }
}


// MARK: - Insights (Tagebuch 2.0)

struct DiaryInsightsPanel: View {
    let pages: [DiaryPage]
    let ask: () -> Void
    @Environment(AppState.self) private var app
    @State private var span = 30

    private var recent: [DiaryPage] {
        let since = DiaryDay.key(Calendar.current.date(byAdding: .day, value: -span, to: .now) ?? .now)
        return pages.filter { $0.day >= since }
    }
    private struct MoodPoint: Identifiable { let id: String; let date: Date; let score: Double }
    private var points: [MoodPoint] {
        let mine = recent.filter { $0.moodScore != nil && ($0.visibility != .shared || $0.ownerID == app.me?.id) }
        let grouped = Dictionary(grouping: mine, by: { $0.day })
        var result: [MoodPoint] = []
        for (day, list) in grouped {
            let scores = list.compactMap { $0.moodScore }
            guard !scores.isEmpty, let date = DiaryDay.date(day) else { continue }
            result.append(MoodPoint(id: day, date: date, score: Double(scores.reduce(0, +)) / Double(scores.count)))
        }
        return result.sorted { $0.date < $1.date }
    }
    private struct Count: Identifiable { let id: String; let count: Int }
    private static func counted(_ values: [String]) -> [Count] {
        Dictionary(grouping: values, by: { $0 }).map { Count(id: $0.key, count: $0.value.count) }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }
    private var moods: [Count] { Self.counted(recent.map(\.mood).filter { !$0.isEmpty }) }
    private var topTags: [Count] { Self.counted(recent.flatMap(\.tags)) }
    private var places: [Count] { Self.counted(recent.map(\.location).filter { !$0.isEmpty }) }

    private static func axisEmoji(_ value: Double) -> String { value >= 4.5 ? "🥰" : value <= 1.5 ? "😢" : "😌" }

    var body: some View {
        VStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
            Picker("Zeitraum", selection: $span) { Text("7 Tage").tag(7); Text("30 Tage").tag(30); Text("1 Jahr").tag(365) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 12) {
                Label("Deine Stimmung", systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(LovePalette.pink)
                if points.count >= 2 {
                    Chart(points) { point in
                        AreaMark(x: .value("Tag", point.date), y: .value("Stimmung", point.score)).foregroundStyle(LinearGradient(colors: [LovePalette.pink.opacity(0.35), LovePalette.pink.opacity(0.02)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Tag", point.date), y: .value("Stimmung", point.score)).foregroundStyle(LovePalette.pink).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Tag", point.date), y: .value("Stimmung", point.score)).foregroundStyle(LovePalette.pink).symbolSize(24)
                    }
                    .chartYScale(domain: 1...5)
                    .chartYAxis { AxisMarks(values: [1, 3, 5]) { value in AxisGridLine(); AxisValueLabel { Text(Self.axisEmoji(value.as(Double.self) ?? 3)) } } }
                    .frame(height: 180)
                } else {
                    Text("Sobald du an ein paar Tagen eine Stimmung hast, siehst du hier deinen Verlauf.").font(.subheadline).foregroundStyle(.secondary)
                }
                if !moods.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(moods.prefix(5)) { item in
                            VStack(spacing: 2) { Text(item.id).font(.title2); Text("\(item.count)×").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.loveCard()
            HStack(spacing: 10) {
                LoveMetric(title: "Seiten", value: recent.count.formatted(), symbol: "doc.text.fill", tint: LovePalette.violet)
                LoveMetric(title: "Wörter", value: recent.reduce(0) { $0 + $1.words }.formatted(), symbol: "text.word.spacing", tint: LovePalette.cyan)
            }
            if !topTags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Deine Themen", systemImage: "number").font(.headline).foregroundStyle(LovePalette.violet)
                    FlowLayout(spacing: 6) {
                        ForEach(topTags.prefix(16)) { item in
                            Text("#\(item.id) · \(item.count)").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(LovePalette.violet.opacity(0.12), in: Capsule())
                        }
                    }
                }.loveCard()
            }
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Orte deines Tagebuchs", systemImage: "mappin.and.ellipse").font(.headline).foregroundStyle(LovePalette.cyan)
                    ForEach(places.prefix(6)) { item in
                        HStack { Text(item.id).font(.subheadline); Spacer(); Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }.loveCard()
            }
            Button(action: ask) {
                Label("Frag dein Tagebuch", systemImage: "bubble.left.and.text.bubble.right.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(LovePalette.violet).controlSize(.large).disabled(!AICompanion.shared.signedIn)
            Text("Die KI sieht deine Seiten nur, wenn du fragst. Private Seiten kennt nur deine eigene KI.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
