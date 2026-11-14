import SwiftUI

struct DiaryEditorRoute: Identifiable {
    let id = UUID()
    var day: String
    var visibility: DiaryVisibility
    var page: DiaryPage?
    var prompt: String?
    var seed: String?
    var autoCompose = false
    var template: DiaryTemplate?
    var startVoice = false

    init(day: String, visibility: DiaryVisibility, prompt: String? = nil, seed: String? = nil, autoCompose: Bool = false, template: DiaryTemplate? = nil, startVoice: Bool = false) {
        self.day = day; self.visibility = visibility; self.prompt = prompt; self.seed = seed; self.autoCompose = autoCompose
        self.template = template; self.startVoice = startVoice
    }
    init(page: DiaryPage) {
        day = page.day; visibility = page.visibility; self.page = page
    }
}

private enum DiaryTool: String, CaseIterable, Identifiable {
    case compose, expand, polish, shorten, reflect
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compose: "Aus eurem Tag schreiben"
        case .expand: "Aus Stichpunkten schreiben"
        case .polish: "Schöner formulieren"
        case .shorten: "Kürzer fassen"
        case .reflect: "Gedanken dazu"
        }
    }
    var symbol: String {
        switch self {
        case .compose: "wand.and.sparkles"
        case .expand: "list.bullet.indent"
        case .polish: "paintbrush.pointed.fill"
        case .shorten: "scissors"
        case .reflect: "lightbulb.fill"
        }
    }
}

struct DiaryEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var ai = AICompanion.shared
    @State private var date: Date
    @State private var visibility: DiaryVisibility
    @State private var title: String
    @State private var text: String
    @State private var mood: String
    @State private var notes: String
    @State private var prompt: String
    @State private var aiAssisted: Bool
    @State private var saving = false
    @State private var working: DiaryTool?
    @State private var undoText: String?
    @State private var error: String?
    @State private var autoCompose: Bool
    @State private var confirmDiscard = false
    // Tagebuch 2.0
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var place: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var contextSummary: String
    @State private var template: DiaryTemplate
    @State private var followUps: [String] = []
    @State private var askingQuestions = false
    @State private var questionedLength = 0
    @State private var suggestion = DiaryAI.Analysis()
    @State private var analyzedLength = 0
    @State private var transcriber = LiveTranscriber()
    @State private var dictationBase = ""
    @State private var startVoice: Bool
    @AppStorage("rjlove.diary.capture-location") private var captureLocation = true
    @FocusState private var writing: Bool
    private let original: DiaryPage?

    init(route: DiaryEditorRoute) {
        original = route.page
        _date = State(initialValue: DiaryDay.date(route.day) ?? .now)
        _visibility = State(initialValue: route.visibility)
        _title = State(initialValue: route.page?.title ?? "")
        _text = State(initialValue: route.page?.text ?? route.seed ?? "")
        _mood = State(initialValue: route.page?.mood ?? "")
        _notes = State(initialValue: route.page?.notes ?? "")
        _prompt = State(initialValue: route.page?.prompt ?? route.prompt ?? "")
        _aiAssisted = State(initialValue: route.page?.aiAssisted ?? (route.seed != nil))
        _autoCompose = State(initialValue: route.autoCompose)
        _tags = State(initialValue: route.page?.tags ?? [])
        _place = State(initialValue: route.page?.location ?? "")
        _latitude = State(initialValue: route.page?.latitude)
        _longitude = State(initialValue: route.page?.longitude)
        _contextSummary = State(initialValue: route.page?.context ?? "")
        let template = route.template ?? DiaryTemplate(rawValue: route.page?.template ?? "") ?? .free
        _template = State(initialValue: template)
        _startVoice = State(initialValue: route.startVoice)
        if route.page == nil, route.prompt == nil, !template.opening.isEmpty { _prompt = State(initialValue: template.opening) }
    }
    init(day: String, seed: String) { self.init(route: DiaryEditorRoute(day: day, visibility: .shared, seed: seed)) }

    private var dayKey: String { DiaryDay.key(date) }
    private var changed: Bool {
        guard let original else { return !text.isEmpty || !title.isEmpty }
        return original.text != text || original.title != title || original.mood != mood || original.notes != notes || original.day != dayKey || original.tags != tags || original.location != place
    }
    private var tooLong: Bool { text.count > 20_000 || title.count > 120 || notes.count > 6_000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    contextCard
                    if mood.isEmpty, let suggested = suggestion.mood { moodSuggestion(suggested) }
                    moodPicker
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Überschrift (optional)", text: $title).font(.system(.title2, design: .serif).weight(.medium))
                        if !prompt.isEmpty {
                            HStack(alignment: .top) {
                                Text("„\(prompt)“").font(.system(.subheadline, design: .serif).italic()).foregroundStyle(LovePalette.violet)
                                Spacer()
                                Button { prompt = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.accessibilityLabel("Frage entfernen")
                            }
                        }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(prompt.isEmpty ? "Liebes Tagebuch, …" : "Deine Antwort …").font(.system(.body, design: .serif)).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                            TextEditor(text: $text).font(.system(.body, design: .serif)).lineSpacing(5).frame(minHeight: 240).scrollContentBackground(.hidden).focused($writing)
                                .disabled(working != nil)
                        }
                        if transcriber.isRunning { dictationBar }
                        HStack(spacing: 10) {
                            Button { Task { await toggleDictation() } } label: {
                                Label(transcriber.isRunning ? "Fertig" : "Sprechen", systemImage: transcriber.isRunning ? "stop.circle.fill" : "mic.fill").font(.caption.weight(.semibold))
                            }.buttonStyle(.bordered).tint(transcriber.isRunning ? .red : LovePalette.pink).disabled(working != nil)
                            if ai.signedIn {
                                Button { Task { await loadQuestions(force: true) } } label: {
                                    HStack(spacing: 4) { if askingQuestions { ProgressView().controlSize(.mini) }; Label("Frag mich", systemImage: "questionmark.bubble") }.font(.caption.weight(.semibold))
                                }.buttonStyle(.bordered).tint(LovePalette.violet).disabled(askingQuestions || working != nil)
                            }
                            Spacer()
                            Text("\(text.split { $0.isWhitespace || $0.isNewline }.count) Wörter").font(.caption2).foregroundStyle(.secondary)
                            if let undoText, working == nil { Button("KI rückgängig", systemImage: "arrow.uturn.backward") { text = undoText; self.undoText = nil }.font(.caption) }
                        }
                        if let error = transcriber.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    }.loveCard()
                    if !followUps.isEmpty { questionCards }
                    tagEditor
                    aiTools
                    if !notes.isEmpty || working == .reflect {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Label("Ein Gedanke dazu", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet); Spacer(); if working == nil { Button("Entfernen") { notes = "" }.font(.caption) } }
                            Text(notes.isEmpty ? "…" : notes).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LovePalette.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if tooLong { Text("Die Seite ist zu lang (höchstens 20.000 Zeichen, Überschrift 120).").font(.footnote).foregroundStyle(.orange) }
                }.padding(LoveMetrics.screenPadding).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LoveBackground())
            .navigationTitle(original == nil ? "Neue Seite" : "Seite bearbeiten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if changed { confirmDiscard = true } else { dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Speichert …" : "Speichern") { Task { await save() } }
                        .disabled(saving || working != nil || tooLong || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && notes.isEmpty))
                        .accessibilityIdentifier("diary-save")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fertig") { writing = false } }
            }
            .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { dismiss() }
                Button("Weiter schreiben", role: .cancel) {}
            }
            .task {
                if original == nil { await captureContext() }
                if followUps.isEmpty, original == nil { followUps = template.followUps }
                if startVoice { startVoice = false; await toggleDictation() }
                else if autoCompose { autoCompose = false; await run(.compose) }
                else if original == nil && text.isEmpty { writing = true }
            }
            .task(id: text.count / 40) { await liveAssist() }
            .onChange(of: transcriber.transcript) { _, value in if transcriber.isRunning { text = Self.joined(dictationBase, value) } }
            .onChange(of: template) { _, value in
                if original == nil, text.isEmpty { prompt = value.opening; followUps = value.followUps }
            }
            .onDisappear { if transcriber.isRunning { transcriber.cancel() } }
        }
        .interactiveDismissDisabled(changed || saving || working != nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Tag", selection: $date, in: ...Date.now, displayedComponents: .date)
            if original == nil {
                Picker("Wo diese Seite liegt", selection: $visibility) {
                    ForEach(DiaryVisibility.allCases) { Label($0.short, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.segmented)
            } else {
                Label(visibility.title, systemImage: visibility.symbol).font(.subheadline.weight(.semibold))
            }
            Text(visibility.explanation).font(.caption).foregroundStyle(.secondary)
            if original == nil {
                Menu {
                    Picker("Vorlage", selection: $template) {
                        ForEach(DiaryTemplate.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label("Vorlage: " + template.title, systemImage: template.symbol).font(.subheadline.weight(.semibold))
                }.tint(LovePalette.violet)
            }
        }.loveCard()
    }

    // MARK: Tagebuch 2.0 pieces

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Kontext dieses Eintrags", systemImage: "info.circle.fill").font(.caption.bold()).foregroundStyle(LovePalette.cyan)
                Spacer()
                Button { Task { await captureContext(force: true) } } label: { Image(systemName: "arrow.clockwise") }.font(.caption).accessibilityLabel("Kontext aktualisieren")
            }
            if !place.isEmpty {
                HStack {
                    Label(place, systemImage: "mappin.and.ellipse").font(.subheadline)
                    Spacer()
                    Button { place = ""; latitude = nil; longitude = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.accessibilityLabel("Ort entfernen")
                }
            }
            if !contextSummary.isEmpty { Text(contextSummary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if place.isEmpty && contextSummary.isEmpty { Text("Für diesen Tag ist noch nichts bekannt.").font(.caption).foregroundStyle(.secondary) }
            Toggle("Ort automatisch hinzufügen", isOn: $captureLocation).font(.caption).tint(LovePalette.cyan)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(LovePalette.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func moodSuggestion(_ emoji: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Klingt nach: " + DiaryMood.title(emoji)).font(.subheadline.weight(.semibold))
                Text(suggestion.tags.isEmpty ? "Vorschlag aus deinem Text" : "Themen: " + suggestion.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Übernehmen") { applySuggestion() }.buttonStyle(.borderedProminent).tint(LovePalette.violet).font(.caption.bold())
        }.padding(12).background(LovePalette.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var questionCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Schreib weiter …", systemImage: "bubble.left.and.text.bubble.right.fill").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                Spacer()
                Button { followUps = [] } label: { Image(systemName: "xmark") }.font(.caption).foregroundStyle(.secondary).accessibilityLabel("Fragen ausblenden")
            }
            ForEach(followUps, id: \.self) { question in
                Button { answer(question) } label: {
                    HStack {
                        Text(question).font(.system(.subheadline, design: .serif)).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.turn.down.left").font(.caption).foregroundStyle(LovePalette.violet)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LoveSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LovePalette.violet.opacity(0.18), lineWidth: 0.7) }
                }.buttonStyle(.lovePress).foregroundStyle(.primary)
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Themen", systemImage: "number").font(.caption.bold()).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button { tags.removeAll { $0 == tag } } label: {
                        HStack(spacing: 4) { Text("#" + tag); Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(LovePalette.violet.opacity(0.14), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(LovePalette.violet)
                }
                ForEach(suggestion.tags.filter { !tags.contains($0) }, id: \.self) { tag in
                    Button { tags.append(tag) } label: {
                        Text("+ #" + tag).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay { Capsule().strokeBorder(LovePalette.violet.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3])) }
                    }.buttonStyle(.plain).foregroundStyle(LovePalette.violet)
                }
            }
            HStack {
                TextField("Thema hinzufügen", text: $newTag).font(.subheadline).textInputAutocapitalization(.never).onSubmit(addTag)
                Button("Hinzufügen", action: addTag).font(.caption).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty || tags.count >= 10)
            }
        }.loveCard()
    }

    private var dictationBar: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9).scaleEffect(1 + transcriber.level).animation(.linear(duration: 0.1), value: transcriber.level)
            Text(String(format: "%d:%02d", Int(transcriber.elapsed) / 60, Int(transcriber.elapsed) % 60)).font(.caption.monospacedDigit())
            Text("Ich schreibe mit, was du sagst …").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Verwerfen", role: .destructive) { transcriber.cancel(); text = dictationBase }.font(.caption)
        }.padding(10).background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addTag() {
        let value = newTag.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
        guard !value.isEmpty, !tags.contains(value), tags.count < 10 else { return }
        tags.append(String(value.prefix(30))); newTag = ""
    }

    private func answer(_ question: String) {
        followUps.removeAll { $0 == question }
        let spacer = text.isEmpty || text.hasSuffix("\n") ? "" : "\n\n"
        text += spacer + question + "\n"
        writing = true
        Haptics.selection()
    }

    private func applySuggestion() {
        if let value = suggestion.mood { mood = value }
        for tag in suggestion.tags where !tags.contains(tag) && tags.count < 10 { tags.append(tag) }
        if title.isEmpty, let value = suggestion.title { title = value }
        Haptics.success()
    }

    private func captureContext(force: Bool = false) async {
        guard force || (contextSummary.isEmpty && place.isEmpty) else { return }
        let snapshot = await DiaryContextCapture.capture(app: app, day: dayKey, includeLocation: captureLocation)
        contextSummary = snapshot.summary
        if !snapshot.place.isEmpty || force { place = snapshot.place; latitude = snapshot.latitude; longitude = snapshot.longitude }
    }

    private func toggleDictation() async {
        if transcriber.isRunning {
            let result = await transcriber.stop()
            text = Self.joined(dictationBase, result.text)
            return
        }
        dictationBase = text
        writing = false
        await transcriber.start(record: false)
    }

    private static func joined(_ base: String, _ addition: String) -> String {
        guard !addition.isEmpty else { return base }
        if base.isEmpty { return addition }
        return base + (base.hasSuffix("\n") || base.hasSuffix(" ") ? "" : " ") + addition
    }

    /// Live help while writing: local mood guess at once, ChatGPT questions and suggestions after a pause.
    private func liveAssist() async {
        if mood.isEmpty, suggestion.mood == nil, let guess = DiaryMood.guess(text) { suggestion.mood = guess }
        guard ai.signedIn, working == nil, !transcriber.isRunning else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        if ai.diaryAutoMood, text.count >= 80, text.count - analyzedLength >= 250 || (analyzedLength == 0 && text.count >= 80) {
            analyzedLength = text.count
            if let result = try? await DiaryAI.analyze(text: text, app: app) {
                if result.mood != nil { suggestion.mood = result.mood }
                suggestion.tags = result.tags
                suggestion.title = result.title
            }
        }
        if ai.diaryLiveQuestions { await loadQuestions(force: false) }
    }

    private func loadQuestions(force: Bool) async {
        guard ai.signedIn, !askingQuestions else { return }
        guard force || (text.count >= 140 && text.count - questionedLength >= 280) else { return }
        askingQuestions = true
        defer { askingQuestions = false }
        questionedLength = text.count
        if let questions = try? await DiaryAI.followUps(text: text.isEmpty ? prompt : text, template: template, visibility: visibility, app: app), !questions.isEmpty {
            followUps = questions
            Haptics.selection()
        }
    }

    private var moodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiaryMood.all) { item in
                    let selected = mood == item.emoji
                    Button { mood = selected ? "" : item.emoji; Haptics.selection() } label: {
                        VStack(spacing: 3) {
                            Text(item.emoji).font(.title2)
                            Text(item.title).font(.caption2).foregroundStyle(selected ? .white : .secondary)
                        }
                        .frame(width: 70, height: 62)
                        .background(selected ? AnyShapeStyle(LovePalette.violet) : AnyShapeStyle(LoveSurface.card), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LoveSurface.hairline, lineWidth: 0.5) }
                    }.buttonStyle(.lovePress).accessibilityLabel(item.title).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.horizontal, 2)
        }
    }

    @ViewBuilder private var aiTools: some View {
        if ai.signedIn {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Schreibhilfe", systemImage: "wand.and.sparkles").font(.headline).foregroundStyle(LovePalette.violet)
                    Spacer()
                    if working != nil { ProgressView().controlSize(.small) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DiaryTool.allCases) { tool in
                            Button { Task { await run(tool) } } label: { Label(tool.title, systemImage: tool.symbol).font(.subheadline) }
                                .buttonStyle(.bordered).tint(LovePalette.violet)
                                .disabled(working != nil || (tool != .compose && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        }
                    }
                }
                Text(visibility == .privateOnly ? "Private Seiten gehen nur zur Formulierung an dein ChatGPT und werden nie zum Server übertragen." : "Läuft über dein ChatGPT-Abo. Du entscheidest vor dem Speichern, was bleibt.").font(.caption2).foregroundStyle(.secondary)
            }.loveCard()
        } else {
            NavigationLink { ChatGPTAccountView() } label: {
                Label("KI-Schreibhilfe mit ChatGPT einschalten", systemImage: "wand.and.sparkles").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(LovePalette.violet)
        }
    }

    private func run(_ tool: DiaryTool) async {
        guard ai.signedIn, working == nil else { return }
        working = tool
        error = nil
        writing = false
        defer { working = nil }
        let me = app.me?.displayName ?? "ich"
        let partner = app.partner?.displayName ?? "mein Lieblingsmensch"
        let dayTitle = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let style = "Schreibe in der Ich-Form von \(me), natürlich, warm und persönlich, wie ein echter Tagebucheintrag. Kein Markdown, keine Überschrift, keine Anführungszeichen um den ganzen Text."
        let together = visibility == .together ? "Schreibe als gemeinsame Seite von \(me) und \(partner) in der Wir-Form." : style
        let prompt: String
        var context = false
        switch tool {
        case .compose:
            let pages = app.diaryPages(on: dayKey).filter { $0.id != original?.id && ($0.visibility != .shared || $0.ownerID == app.me?.id || ai.serverStatus?.partnerSharing == true) }
            let myID = app.me?.id
            var sources: [String] = []
            for page in pages {
                let who: String
                if page.visibility == .together { who = "Gemeinsam" }
                else if page.visibility == .privateOnly || page.ownerID == myID { who = me }
                else { who = partner }
                sources.append(who + ": " + page.title + " – " + String(page.text.prefix(1500)))
            }
            var request = "Schreibe einen Tagebucheintrag für \(dayTitle) (\(dayKey)). Nutze dafür ausschließlich, was im App-Wissen für diesen Tag steht"
            if !sources.isEmpty { request += " und diese Seiten des Tages:\n" + sources.joined(separator: "\n") + "\n" }
            if !text.isEmpty { request += "\nMeine bisherigen Notizen:\n" + text + "\n" }
            request += "\nHöchstens 220 Wörter. Wenn kaum etwas bekannt ist, schreibe kurz und ehrlich darüber, ohne etwas zu erfinden. " + together
            prompt = request
            context = true
        case .expand:
            prompt = "Mach aus diesen Stichpunkten einen lebendigen Tagebucheintrag für \(dayTitle). Behalte alle Fakten, erfinde nichts dazu.\n\n\(text)\n\n\(together)"
        case .polish:
            prompt = "Formuliere diesen Tagebucheintrag schöner und flüssiger, ohne den Inhalt oder die Stimme zu verändern. Gib nur den neuen Text zurück.\n\n\(text)"
        case .shorten:
            prompt = "Fasse diesen Tagebucheintrag auf etwa die Hälfte zusammen, behalte die wichtigsten Gefühle und Momente. Gib nur den Text zurück.\n\n\(text)"
        case .reflect:
            prompt = "Lies diesen Tagebucheintrag und schreibe 2–3 behutsame, wertschätzende Sätze als Gedanken dazu, plus eine kleine Frage für morgen. Keine Ratschläge zu Gesundheit, keine Bewertung der Beziehung.\n\n\(text)"
        }
        do {
            if tool == .reflect {
                notes = ""
                notes = try await ai.ask(prompt, system: "Du bist ein einfühlsamer Tagebuch-Begleiter.", app: app, includeContext: false) { value in notes = value }
            } else {
                undoText = text
                let before = text
                let result = try await ai.ask(prompt, system: "Du hilfst beim Schreiben eines privaten Tagebuchs. Antworte nur mit dem Eintrag selbst.", app: app, includeContext: context) { value in text = value }
                text = result.isEmpty ? before : result
                if title.isEmpty, tool == .compose || tool == .expand {
                    let headline = try? await ai.ask("Gib diesem Tagebucheintrag eine kurze, poetische Überschrift (höchstens 6 Wörter, ohne Anführungszeichen):\n\n\(text)", system: "Antworte nur mit der Überschrift.", app: app, includeContext: false)
                    if let headline { title = String(headline.trimmingCharacters(in: CharacterSet(charactersIn: "\"„“ .\n")).prefix(120)) }
                }
            }
            aiAssisted = true
            Haptics.success()
        } catch {
            if let undoText, text.isEmpty { text = undoText }
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if transcriber.isRunning { await toggleDictation() }
        // Mood is filled in automatically when you did not pick one yourself.
        if mood.isEmpty, let suggested = suggestion.mood ?? DiaryMood.guess(text) { mood = suggested }
        if tags.isEmpty { tags = suggestion.tags }
        if title.isEmpty, let suggested = suggestion.title { title = suggested }
        var page = original ?? DiaryPage(entry: PrivateDiaryEntry(day: dayKey, title: title, text: text))
        page = DiaryPage(copying: page, day: dayKey, title: title, text: text, mood: mood, notes: notes, prompt: prompt, aiAssisted: aiAssisted)
        page.tags = tags; page.location = place; page.latitude = latitude; page.longitude = longitude
        page.context = contextSummary; page.template = template == .free ? "" : template.rawValue
        var existingID = original?.record?.id
        if original == nil, visibility == .together, let current = app.togetherPage(on: dayKey) {
            // Someone else started the shared page meanwhile: continue it instead of creating a second one.
            let other = DiaryPage(record: current)
            page = DiaryPage(copying: page, day: dayKey, title: title.isEmpty ? other.title : title, text: other.text + "\n\n" + text, mood: mood, notes: notes, prompt: prompt, aiAssisted: aiAssisted || other.aiAssisted)
            page.tags = Array(Set(tags + other.tags)).sorted()
            existingID = current.id
        }
        if await app.saveDiary(page, visibility: visibility, existingID: existingID) { dismiss() }
    }
}

extension DiaryPage {
    init(copying base: DiaryPage, day: String, title: String, text: String, mood: String, notes: String, prompt: String, aiAssisted: Bool) {
        self = base
        self.title = title
        self.text = text
        self.mood = mood
        self.notes = notes
        self.prompt = prompt
        self.aiAssisted = aiAssisted
        self.day = day
    }
}
