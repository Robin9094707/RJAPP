import SwiftUI

private enum DiaryMode: String, CaseIterable, Identifiable { case day = "Tag", pages = "Alle Seiten", review = "Rückblick"; var id: String { rawValue } }

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
    private var cal: Calendar { .current }
    private var dayKey: String { DiaryDay.key(day) }
    private var partnerName: String { app.partner?.displayName ?? "Dein Lieblingsmensch" }

    var body: some View {
        let pages = app.diaryPages()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
                hero(pages)
                Picker("Ansicht", selection: $mode) { ForEach(DiaryMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                switch mode {
                case .day: dayView(pages.filter { $0.day == dayKey })
                case .pages: allPages(pages)
                case .review: DiaryReviewPanel(pages: pages)
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
        NavigationLink { SharedJournalView(initialDay: day) } label: {
            Label("Momente & Aktivität dieses Tages", systemImage: "sparkles.rectangle.stack").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered)
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
