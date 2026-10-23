import SwiftUI

private enum HubSection: String, CaseIterable, Identifiable {
    case chat = "Worte", wishes = "Wünsche", milestones = "Unsere Zeit", checkin = "Gefühle"
    var id: String { rawValue }
}

struct LoveHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: HubSection = .chat
    @AppStorage("rjlove.chat-draft") private var draft = ""
    @State private var sending = false
    @State private var composing: RecordKind?
    @State private var deleting: SharedRecord?
    private var chats: [SharedRecord] { appState.records.filter { $0.kind == .chat }.sorted { $0.createdAt < $1.createdAt } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Für uns", selection: $section) {
                ForEach(HubSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 18).padding(.vertical, 10)
            if section == .chat { chatContent }
            else if section == .milestones {CountdownHubView()}
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introduction
                        if entries.isEmpty {
                            ContentUnavailableView("Hier beginnt etwas Schönes", systemImage: icon, description: Text("Eure Ideen, eure Gefühle, eure Geschichte."))
                        }
                        ForEach(entries) { record in entryCard(record) }
                        Button("Hinzufügen", systemImage: "plus") { composing = kind }
                            .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    }.padding(22)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: section)
        .background(LoveBackground()).navigationTitle("Nur wir zwei").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { PlannerView() } label: { Image(systemName:"calendar.badge.clock") }
                    .accessibilityLabel("Gemeinsame Planung")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { TogetherView() } label: { Image(systemName: "tray.full") }
                    .accessibilityLabel("Notizen, Erinnerungen und Kalender")
            }
        }
        .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { composing = nil } })) {
            HubComposerView(kind: composing ?? .wish)
        }
        .alert("Für euch beide löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Löschen", role: .destructive) { if let deleting { Task { _ = await appState.deleteRecord(deleting) } }; deleting = nil }
            Button("Abbrechen", role: .cancel) { deleting = nil }
        }
    }

    private var chatContent: some View { MessengerView() }
    private var question: String {
        let questions = ["Welcher kleine Moment mit mir macht dich glücklich?", "Was möchtest du dieses Jahr mit mir erleben?", "Wobei kann ich dich gerade unterstützen?", "Was war heute dein schönster Gedanke?", "Welchen Ort würdest du mir gern zeigen?", "Wann fühlst du dich mir besonders nah?", "Worauf freust du dich bei unserem nächsten Treffen?"]
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return questions[day % questions.count]
    }
    private var kind: RecordKind { section == .wishes ? .wish : section == .milestones ? .milestone : .checkin }
    private var entries: [SharedRecord] { appState.records.filter { $0.kind == kind } }
    private var icon: String { section == .wishes ? "sparkles" : section == .milestones ? "calendar.badge.heart" : "face.smiling" }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            LoveEyebrow(text: section == .wishes ? "Noch so viel vor" : section == .milestones ? "Jeder Tag mit dir" : "Ich bin für dich da")
            Text(section == .wishes ? "Unsere kleine Wunschliste." : section == .milestones ? "Momente, die bleiben." : "Wie geht es dir wirklich?")
                .font(.system(size: 29, weight: .medium, design: .serif))
        }.padding(.vertical, 10)
    }
    private func entryCard(_ record: SharedRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if record.kind == .wish {
                    Button {
                        var payload = record.payload; payload.completed = !(payload.completed ?? false)
                        Task { _ = await appState.saveRecord(id: record.id, kind: .wish, payload: payload) }
                    } label: { Image(systemName: record.payload.completed == true ? "checkmark.circle.fill" : "circle").font(.title2) }
                    .accessibilityLabel(record.payload.completed == true ? "Als offen markieren" : "Als erfüllt markieren")
                } else { Text(record.kind == .checkin ? record.payload.message ?? "💗" : "🗓️").font(.title) }
                Text(record.payload.title ?? "").font(.headline).strikethrough(record.payload.completed == true)
                Spacer()
                Menu { Button("Löschen", systemImage: "trash", role: .destructive) { deleting = record } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Eintrag verwalten")
            }
            if let text = record.payload.text, !text.isEmpty { Text(text).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            if let date = record.payload.startAt?.rjDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
                Text(days >= 0 ? "Noch \(days) Tage" : "Seit \(abs(days)) Tagen").font(.system(.title, design: .serif)).foregroundStyle(LovePalette.pink)
                Text(date.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Text(record.ownerID == appState.me?.id ? "Von dir" : "Von \(appState.partner?.displayName ?? "Schatzi")").font(.caption2).foregroundStyle(.tertiary)
        }.loveCard()
    }
}

private struct HubComposerView: View {
    let kind: RecordKind
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var date = Date.now
    @State private var mood = "💗"
    @State private var saving = false
    private let moods = ["💗", "🥰", "😊", "🥱", "😔", "😰", "🤒", "🤗"]
    var body: some View {
        NavigationStack {
            Form {
                if kind == .checkin {
                    Section("So fühle ich mich") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                            ForEach(moods, id: \.self) { emoji in
                                Button { mood = emoji } label: {
                                    Text(emoji).font(.largeTitle).padding(8).background(mood == emoji ? LovePalette.pink.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain).accessibilityLabel(emoji).accessibilityAddTraits(mood == emoji ? .isSelected : [])
                            }
                        }
                    }
                }
                TextField(kind == .wish ? "Das möchte ich mit dir erleben" : kind == .milestone ? "Unser besonderer Tag" : "So geht es mir gerade", text: $title)
                TextField("Ein paar Worte dazu", text: $text, axis: .vertical).lineLimit(4...8)
                if kind == .milestone { DatePicker("Datum", selection: $date, displayedComponents: .date) }
            }.navigationTitle(kind == .wish ? "Ein Wunsch" : kind == .milestone ? "Unsere Zeit" : "Mein Gefühl")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Teilen") {
                        saving = true
                        Task {
                            let payload = RecordPayload(title: title.trimmingCharacters(in: .whitespacesAndNewlines), text: text, message: kind == .checkin ? mood : nil, completed: kind == .wish ? false : nil, startAt: kind == .milestone ? date.rjISO8601 : nil)
                            if await appState.saveRecord(kind: kind, payload: payload) != nil { dismiss() }
                            saving = false
                        }
                    }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || text.count > 4000)
                }
            }
        }
    }
}
