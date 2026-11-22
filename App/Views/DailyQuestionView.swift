import SwiftUI

extension APIClient {
    func dailyQuestion(day: String) async throws -> DailyQuestionState {
        var req = try request(path: "/v1/daily-question", method: "GET")
        var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "day", value: day)]; req.url = url.url
        return try await execute(req, as: DailyQuestionState.self)
    }
    func answerDailyQuestion(day: String, question: String, answer: String) async throws -> DailyQuestionState {
        let body = try JSONSerialization.data(withJSONObject: ["day": day, "question": question, "answer": answer])
        return try await execute(try request(path: "/v1/daily-question", method: "POST", body: body), as: DailyQuestionState.self)
    }
    func dailyQuestionHistory() async throws -> [DailyQuestionState] {
        struct Page: Decodable { let days: [DailyQuestionState] }
        return try await execute(try request(path: "/v1/daily-question/history", method: "GET"), as: Page.self).days
    }
}

/// One question a day for both of you. The other answer unlocks once you answered yourself.
struct DailyQuestionCard: View {
    @Environment(AppState.self) private var app
    var compact = false
    @State private var answering = false
    private var state: DailyQuestionState? { app.dailyQuestion }
    private var day: String { state?.day ?? app.serverDay }
    private var question: String { state?.mine?.question ?? DailyQuestions.question(for: day) }
    private var partnerName: String { app.partner?.displayName ?? "Dein Lieblingsmensch" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LoveIcon(symbol: "bubble.left.and.text.bubble.right.fill", tint: LovePalette.violet, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frage des Tages").font(.headline)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                NavigationLink { DailyQuestionHistoryView() } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.body.weight(.semibold)).frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless).accessibilityLabel("Frühere Fragen")
            }
            Text(question).font(.loveDisplay(compact ? 19 : 22)).fixedSize(horizontal: false, vertical: true)
            if !compact {
                if let mine = state?.mine {
                    answerBubble(title: "Du", text: mine.answer, tint: LovePalette.pink)
                    if let partner = state?.partner {
                        answerBubble(title: partnerName, text: partner.answer, tint: LovePalette.violet)
                    } else {
                        Label("Sobald \(partnerName) antwortet, erscheint die Antwort hier.", systemImage: "hourglass")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if state?.partnerAnswered == true {
                    Label("\(partnerName) hat schon geantwortet. Antworte, um es zu sehen.", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(LovePalette.violet)
                }
            }
            Button {
                answering = true
            } label: {
                Label(state?.mine == nil ? "Antworten" : "Antwort ändern", systemImage: state?.mine == nil ? "square.and.pencil" : "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(LovePalette.violet).controlSize(.large)
        }
        .loveCard()
        .sheet(isPresented: $answering) { DailyAnswerSheet(day: day, question: question, existing: state?.mine?.answer ?? "") }
    }

    private var statusLine: String {
        switch (state?.mine != nil, state?.partnerAnswered == true) {
        case (true, true): return "Ihr habt beide geantwortet 💞"
        case (true, false): return "Du hast geantwortet · warte auf \(partnerName)"
        case (false, true): return "\(partnerName) wartet auf deine Antwort"
        default: return "Neu für euch beide"
        }
    }

    private func answerBubble(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DailyAnswerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let day: String
    let question: String
    @State var existing: String
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    init(day: String, question: String, existing: String) {
        self.day = day; self.question = question; _existing = State(initialValue: existing)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(question).font(.loveDisplay(22)).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                }
                Section {
                    TextField("Deine Antwort", text: $existing, axis: .vertical).lineLimit(4...10).focused($focused)
                } footer: {
                    Text("Eure Antworten seht ihr erst, wenn ihr beide geantwortet habt.")
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Frage des Tages").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Sendet …" : "Senden") { Task { await save() } }
                        .disabled(saving || existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let state = try await app.api.answerDailyQuestion(day: day, question: question, answer: existing.trimmingCharacters(in: .whitespacesAndNewlines))
            app.dailyQuestion = state
            Haptics.success(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DailyQuestionHistoryView: View {
    @Environment(AppState.self) private var app
    @State private var days: [DailyQuestionState] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            if loading && days.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.orange) }
            if !loading && days.isEmpty && error == nil {
                ContentUnavailableView("Noch keine Antworten", systemImage: "bubble.left.and.text.bubble.right", description: Text("Hier sammeln sich eure Fragen des Tages."))
            }
            ForEach(days, id: \.day) { item in
                Section(Self.title(item.day)) {
                    Text(item.mine?.question ?? DailyQuestions.question(for: item.day)).font(.headline)
                    if let mine = item.mine { LabeledContent("Du") { Text(mine.answer).multilineTextAlignment(.trailing) } }
                    if let partner = item.partner { LabeledContent(app.partner?.displayName ?? "Lieblingsmensch") { Text(partner.answer).multilineTextAlignment(.trailing) } }
                    else { Text("Noch keine Antwort von \(app.partner?.displayName ?? "deinem Lieblingsmenschen")").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Eure Fragen")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { days = try await app.api.dailyQuestionHistory(); error = nil } catch { self.error = error.localizedDescription }
    }
    static func title(_ day: String) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "de_DE")
        guard let date = formatter.date(from: day) else { return day }
        return date.formatted(date: .complete, time: .omitted)
    }
}

/// A full page for the question, also reachable from notifications and the tab bar.
struct DailyQuestionView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ScrollView {
            VStack(spacing: LoveMetrics.stackSpacing) {
                DailyQuestionCard()
                NavigationLink { DailyQuestionHistoryView() } label: {
                    LoveSettingsRow(title: "Frühere Fragen", subtitle: "Alle Antworten von euch beiden", symbol: "clock.arrow.circlepath", tint: LovePalette.violet)
                }
                .buttonStyle(.lovePress).loveCard()
            }
            .padding(LoveMetrics.screenPadding).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(LoveBackground())
        .navigationTitle("Frage des Tages")
        .refreshable { await app.refreshDailyQuestion() }
        .task { await app.refreshDailyQuestion() }
    }
}
