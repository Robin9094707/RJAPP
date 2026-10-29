import SwiftUI

private enum TogetherSection: String, CaseIterable, Identifiable {
    case notes = "Notizen"
    case reminders = "Erinnerungen"
    case calendar = "Kalender"
    var id: String { rawValue }
}

private struct RecordEditorRoute: Identifiable {
    let id = UUID()
    let kind: RecordKind
    let record: SharedRecord?
}

struct TogetherView: View {
    @Environment(AppState.self) private var appState
    @State private var section: TogetherSection = .notes
    @State private var editor: RecordEditorRoute?
    @State private var deleting: SharedRecord?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker("Bereich", selection: $section) {
                    ForEach(TogetherSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 3)

                switch section {
                case .notes: notesContent
                case .reminders: remindersContent
                case .calendar: calendarContent
                }
            }
            .padding(18)
        }
        .background(LoveBackground())
        .navigationTitle("Gemeinsam")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = RecordEditorRoute(kind: recordKind, record: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neuen Eintrag erstellen")
            }
        }
        .sheet(item: $editor) { route in
            switch route.kind {
            case .note: NoteEditorView(record: route.record)
            case .reminder: ReminderEditorView(record: route.record)
            case .calendar: CalendarEditorView(record: route.record)
            default: EmptyView()
            }
        }
        .alert("Eintrag wirklich löschen?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                guard let deleting else { return }
                Task { _ = await appState.deleteRecord(deleting); self.deleting = nil }
            }
            Button("Abbrechen", role: .cancel) { deleting = nil }
        } message: {
            Text("Der Eintrag wird für euch beide gelöscht. Diese Aktion lässt sich nicht rückgängig machen.")
        }
    }

    private var recordKind: RecordKind {
        switch section {
        case .notes: .note
        case .reminders: .reminder
        case .calendar: .calendar
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        if appState.notes.isEmpty {
            emptyCard("Noch keine Notizen", message: "Haltet hier Ideen, Einkaufslisten oder kleine Liebesbotschaften fest.", symbol: "note.text")
        } else {
            ForEach(appState.notes) { note in
                Button { editor = RecordEditorRoute(kind: .note, record: note) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "note.text").foregroundStyle(LovePalette.cyan)
                            Text(note.payload.title ?? "Gemeinsame Notiz").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(note.payload.text ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                        recordFooter(note)
                    }
                    .loveCard()
                }
                .buttonStyle(.lovePress)
                .contextMenu {
                    Button("Bearbeiten", systemImage: "pencil") { editor = RecordEditorRoute(kind: .note, record: note) }
                    Button("Löschen", systemImage: "trash", role: .destructive) { deleting = note }
                }
            }
        }
    }

    @ViewBuilder
    private var remindersContent: some View {
        if appState.reminders.isEmpty {
            emptyCard("Noch keine Erinnerungen", message: "Erstellt euch gegenseitig verlässliche AlarmKit-Erinnerungen.", symbol: "alarm")
        } else {
            ForEach(appState.reminders.sorted(by: reminderSort)) { reminder in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Image(systemName: reminder.payload.completed == true ? "checkmark.circle.fill" : "alarm.fill")
                            .font(.title2)
                            .foregroundStyle(reminder.payload.completed == true ? .green : LovePalette.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.payload.title ?? "Erinnerung").font(.headline)
                            if let message = reminder.payload.message, !message.isEmpty {
                                Text(message).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let due = reminder.payload.dueAt?.rjDate {
                                Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.clock")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(due < .now ? .red : LovePalette.violet)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Bearbeiten", systemImage: "pencil") { editor = RecordEditorRoute(kind: .reminder, record: reminder) }
                            Button(reminder.payload.completed == true ? "Als offen markieren" : "Erledigt", systemImage: "checkmark") {
                                toggleReminder(reminder)
                            }
                            Button("Löschen", systemImage: "trash", role: .destructive) { deleting = reminder }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    recordFooter(reminder)
                }
                .loveCard()
            }
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        if appState.calendarEvents.isEmpty {
            emptyCard("Noch keine Termine", message: "Teilt ausgewählte Termine – ohne euren ganzen iOS-Kalender offenzulegen.", symbol: "calendar.badge.plus")
        } else {
            ForEach(appState.calendarEvents.sorted(by: calendarSort)) { event in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        calendarDateBadge(event)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.payload.title ?? "Gemeinsamer Termin").font(.headline)
                            if let start = event.payload.startAt?.rjDate {
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                            }
                            if let location = event.payload.location, !location.isEmpty {
                                Label(location, systemImage: "mappin")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    HStack {
                        Button("In iOS-Kalender") {
                            Task {
                                do { try await appState.calendar.addToCalendar(event); Haptics.success() }
                                catch { appState.alert = AppAlert(title: "Kalender", message: error.localizedDescription) }
                            }
                        }
                        .buttonStyle(.glass)
                        Spacer()
                        Button("Bearbeiten") { editor = RecordEditorRoute(kind: .calendar, record: event) }
                        Button(role: .destructive) { deleting = event } label: { Image(systemName: "trash") }
                    }
                    .font(.caption.weight(.semibold))
                }
                .loveCard()
            }
        }
    }

    private func emptyCard(_ title: String, message: String, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity)
            .loveCard()
    }

    private func recordFooter(_ record: SharedRecord) -> some View {
        HStack {
            Label(record.ownerID == appState.me?.id ? "Von dir" : "Von Schatzi", systemImage: "person.crop.circle")
            Spacer()
            if let updated = record.updatedAt.rjDate {
                Text(updated.formatted(.relative(presentation: .named)))
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func toggleReminder(_ reminder: SharedRecord) {
        var payload = reminder.payload
        payload.completed = !(payload.completed ?? false)
        Task { _ = await appState.saveRecord(id: reminder.id, kind: .reminder, payload: payload) }
    }

    private func reminderSort(_ lhs: SharedRecord, _ rhs: SharedRecord) -> Bool {
        (lhs.payload.dueAt?.rjDate ?? .distantFuture) < (rhs.payload.dueAt?.rjDate ?? .distantFuture)
    }

    private func calendarSort(_ lhs: SharedRecord, _ rhs: SharedRecord) -> Bool {
        (lhs.payload.startAt?.rjDate ?? .distantFuture) < (rhs.payload.startAt?.rjDate ?? .distantFuture)
    }

    private func calendarDateBadge(_ event: SharedRecord) -> some View {
        let date = event.payload.startAt?.rjDate ?? .now
        return VStack(spacing: 1) {
            Text(date.formatted(.dateTime.month(.abbreviated))).font(.caption2.bold()).textCase(.uppercase)
            Text(date.formatted(.dateTime.day())).font(.title2.bold())
        }
        .foregroundStyle(LovePalette.pink)
        .frame(width: 48, height: 52)
        .background(LovePalette.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let record: SharedRecord?
    @State private var title: String
    @State private var text: String
    @State private var saving = false

    init(record: SharedRecord?) {
        self.record = record
        _title = State(initialValue: record?.payload.title ?? "")
        _text = State(initialValue: record?.payload.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                TextField("Eure Notiz", text: $text, axis: .vertical)
                    .lineLimit(8...18)
            }
            .navigationTitle(record == nil ? "Neue Notiz" : "Notiz bearbeiten")
            .toolbar { editorToolbar(save: save) }
        }
    }

    private func save() {
        saving = true
        Task {
            var payload = record?.payload ?? RecordPayload()
            payload.title = title
            payload.text = text
            if await appState.saveRecord(id: record?.id, kind: .note, payload: payload) != nil { dismiss() }
            saving = false
        }
    }

    @ToolbarContentBuilder
    private func editorToolbar(save: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button("Speichern", action: save)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
    }
}

struct ReminderEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let record: SharedRecord?
    @State private var title: String
    @State private var message: String
    @State private var due: Date
    @State private var targetID: String
    @State private var alarmEnabled: Bool
    @State private var saving = false
    @State private var confirmation = false

    init(record: SharedRecord?) {
        self.record = record
        _title = State(initialValue: record?.payload.title ?? "")
        _message = State(initialValue: record?.payload.message ?? "")
        _due = State(initialValue: record?.payload.dueAt?.rjDate ?? .now.addingTimeInterval(3600))
        _targetID = State(initialValue: record?.payload.targetID ?? "both")
        _alarmEnabled = State(initialValue: record?.payload.alarmEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerung") {
                    TextField("Titel", text: $title)
                    TextField("Nachricht", text: $message, axis: .vertical).lineLimit(2...5)
                    DatePicker("Zeitpunkt", selection: $due, in: .now..., displayedComponents: [.date, .hourAndMinute])
                }
                Section("Für wen?") {
                    Picker("Empfänger", selection: $targetID) {
                        Text("Für euch beide").tag("both")
                        if let me = appState.me { Text("Nur \(me.displayName)").tag(me.id) }
                        if let partner = appState.partner { Text("Nur \(partner.displayName)").tag(partner.id) }
                    }
                    Toggle("Kritischer Bark-Weckruf", isOn: $alarmEnabled)
                }
                Section {
                    Text("Der Server sendet zur Fälligkeit über Bark oder ntfy. Kritisches Klingeln gibt es mit Bark und deiner Freigabe; die Ruhezeiten des Empfängers gelten immer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(record == nil ? "Neue Erinnerung" : "Erinnerung")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { confirmation = true }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .confirmationDialog("Erinnerung speichern?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Speichern") { save() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(alarmEnabled ? "Der Server berücksichtigt die Bark-Berechtigung und die Ruhezeiten des Empfängers." : "Die Erinnerung wird ohne Systemalarm geteilt.")
            }
        }
    }

    private func save() {
        saving = true
        Task {
            var payload = record?.payload ?? RecordPayload()
            payload.title = title
            payload.message = message
            payload.dueAt = due.rjISO8601
            payload.targetID = targetID == "both" ? nil : targetID
            payload.alarmEnabled = alarmEnabled
            payload.completed = record?.payload.completed ?? false
            if await appState.saveRecord(id: record?.id, kind: .reminder, payload: payload) != nil { dismiss() }
            saving = false
        }
    }
}

struct CalendarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let record: SharedRecord?
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var saving = false

    init(record: SharedRecord?) {
        self.record = record
        let initialStart = record?.payload.startAt?.rjDate ?? .now.addingTimeInterval(3600)
        _title = State(initialValue: record?.payload.title ?? "")
        _start = State(initialValue: initialStart)
        _end = State(initialValue: record?.payload.endAt?.rjDate ?? initialStart.addingTimeInterval(3600))
        _location = State(initialValue: record?.payload.location ?? "")
        _notes = State(initialValue: record?.payload.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $title)
                    DatePicker("Beginn", selection: $start)
                    DatePicker("Ende", selection: $end, in: start...)
                    TextField("Ort (optional)", text: $location)
                    TextField("Notizen", text: $notes, axis: .vertical).lineLimit(3...7)
                }
                Section {
                    Label("Der Termin wird in RJ Love geteilt. Jede Person entscheidet selbst, ob er zusätzlich in den eigenen iOS-Kalender kommt.", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(record == nil ? "Neuer Termin" : "Termin bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            var payload = record?.payload ?? RecordPayload()
            payload.title = title
            payload.startAt = start.rjISO8601
            payload.endAt = end.rjISO8601
            payload.location = location
            payload.notes = notes
            if await appState.saveRecord(id: record?.id, kind: .calendar, payload: payload) != nil { dismiss() }
            saving = false
        }
    }
}

