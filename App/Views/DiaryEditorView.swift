import SwiftUI

struct DiaryEditorRoute: Identifiable {
    let id = UUID()
    var day: String
    var visibility: DiaryVisibility
    var page: DiaryPage?
    var prompt: String?
    var seed: String?
    var autoCompose = false

    init(day: String, visibility: DiaryVisibility, prompt: String? = nil, seed: String? = nil, autoCompose: Bool = false) {
        self.day = day; self.visibility = visibility; self.prompt = prompt; self.seed = seed; self.autoCompose = autoCompose
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
    }
    init(day: String, seed: String) { self.init(route: DiaryEditorRoute(day: day, visibility: .shared, seed: seed)) }

    private var dayKey: String { DiaryDay.key(date) }
    private var changed: Bool {
        guard let original else { return !text.isEmpty || !title.isEmpty }
        return original.text != text || original.title != title || original.mood != mood || original.notes != notes || original.day != dayKey
    }
    private var tooLong: Bool { text.count > 20_000 || title.count > 120 || notes.count > 6_000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
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
                        HStack {
                            Text("\(text.split { $0.isWhitespace || $0.isNewline }.count) Wörter").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if let undoText, working == nil { Button("KI rückgängig", systemImage: "arrow.uturn.backward") { text = undoText; self.undoText = nil }.font(.caption) }
                        }
                    }.loveCard()
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
                if autoCompose { autoCompose = false; await run(.compose) }
                else if original == nil && text.isEmpty { writing = true }
            }
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
        }.loveCard()
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
        var page = original ?? DiaryPage(entry: PrivateDiaryEntry(day: dayKey, title: title, text: text))
        page = DiaryPage(copying: page, day: dayKey, title: title, text: text, mood: mood, notes: notes, prompt: prompt, aiAssisted: aiAssisted)
        var existingID = original?.record?.id
        if original == nil, visibility == .together, let current = app.togetherPage(on: dayKey) {
            // Someone else started the shared page meanwhile: continue it instead of creating a second one.
            let other = DiaryPage(record: current)
            page = DiaryPage(copying: page, day: dayKey, title: title.isEmpty ? other.title : title, text: other.text + "\n\n" + text, mood: mood, notes: notes, prompt: prompt, aiAssisted: aiAssisted || other.aiAssisted)
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
