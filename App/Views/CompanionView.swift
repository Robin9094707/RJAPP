import SwiftUI

private struct ChatStarter: Identifiable, Hashable { let id = UUID(); let text: String }

/// KI & Tagebuch: the hub for the ChatGPT companion, the shared diary and quick AI ideas.
struct CompanionView: View {
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var question = ""
    @State private var starter: ChatStarter?
    @State private var writing: DiaryEditorRoute?
    private var partnerName: String { app.partner?.displayName ?? "meinen Lieblingsmenschen" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
                hero
                if ai.signedIn { askField } else { AISignInPrompt() }
                diaryToday
                NavigationLink { GroupChatView() } label: {
                    HStack(spacing: 14) {
                        LoveIcon(symbol: "person.3.fill", tint: LovePalette.pink, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Unser Gruppenchat").font(.headline).foregroundStyle(.primary)
                            Text("Ihr zwei und ChatGPT · Sprachnachrichten werden mitgeschrieben").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.loveCard()
                }.buttonStyle(.lovePress)
                LoveSectionTitle("Ideen auf Knopfdruck", subtitle: ai.signedIn ? "Ein Tipp öffnet den Chat mit eurem App-Wissen." : "Nach der ChatGPT-Anmeldung verfügbar.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    idea("Liebesbrief", "heart.text.square.fill", LovePalette.pink, "Schreib mir einen kurzen, persönlichen Liebesbrief an \(partnerName), mit Bezug auf etwas, das wir zuletzt erlebt haben.")
                    idea("Date-Idee", "sparkles", LovePalette.violet, "Schlag uns drei Date-Ideen für die nächsten Tage vor, passend zu dem, was uns zuletzt gefallen hat. Mit einem Satz Begründung.")
                    idea("Unsere Woche", "calendar", LovePalette.cyan, "Fasse unsere letzte Woche liebevoll zusammen: schönste Momente, was wir geschrieben haben und was ansteht.")
                    idea("Gesprächsfragen", "bubble.left.and.bubble.right.fill", LovePalette.coral, "Gib uns fünf schöne Gesprächsfragen für heute Abend, inspiriert von unseren letzten Momenten und dem Tagebuch.")
                    idea("Überraschung", "gift.fill", LovePalette.plum, "Welche kleine Überraschung könnte ich \(partnerName) diese Woche machen? Nutze unsere Wünsche und Notizen. Drei Ideen.")
                    idea("Duft-Jury", "wind", LovePalette.violet, "Sei die Duft-Jury: Kür mit viel Humor das Meisterwerk des Monats aus unserem Duftstudio und begründe es.")
                }
                if !ai.conversations.isEmpty {
                    LoveSectionTitle("Zuletzt besprochen")
                    LoveGroup {
                        ForEach(Array(ai.conversations.prefix(3).enumerated()), id: \.element.id) { index, conversation in
                            if index > 0 { LoveRowDivider() }
                            NavigationLink { AIChatView(conversationID: conversation.id) } label: {
                                LoveSettingsRow(title: conversation.title, subtitle: conversation.updatedAt.formatted(.relative(presentation: .named)), symbol: "bubble.left.and.text.bubble.right.fill", tint: LovePalette.violet)
                            }.buttonStyle(.lovePress)
                        }
                        LoveRowDivider()
                        NavigationLink { AIChatListView() } label: { LoveSettingsRow(title: "Alle Gespräche", symbol: "tray.full.fill", tint: LovePalette.cyan) }.buttonStyle(.lovePress)
                    }
                }
                LoveGroup("Mehr") {
                    NavigationLink { AIDaySummaryView() } label: { LoveSettingsRow(title: "Server-Tagesrückblick", subtitle: "Der bisherige Rückblick über den Server-Schlüssel", symbol: "sparkles", tint: LovePalette.cyan) }.buttonStyle(.lovePress)
                    LoveRowDivider()
                    NavigationLink { ChatGPTAccountView() } label: { LoveSettingsRow(title: "KI & ChatGPT einstellen", subtitle: ai.signedIn ? ai.account + " · " + ai.modelName : "Anmeldung, Modell und Freigaben", symbol: "slider.horizontal.3", tint: LovePalette.violet) }.buttonStyle(.lovePress)
                }
            }
            .padding(.horizontal, LoveMetrics.screenPadding).padding(.vertical, 14)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LoveBackground()).navigationTitle("KI & Tagebuch").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $starter) { AIChatEntryView(starter: $0.text) }
        .sheet(item: $writing) { DiaryEditorView(route: $0) }
        .task { ai.refreshAccount(); if ai.signedIn && ai.serverStatus == nil { await ai.loadStatus(api: app.api) } }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    LoveEyebrow(text: ai.signedIn ? "Verbunden mit ChatGPT" : "Ganz optional", tint: LovePalette.violet)
                    Text("Euer KI-Begleiter.").font(.loveDisplay(32))
                    Text(ai.signedIn ? "Kennt eure Momente, euer Tagebuch und eure Pläne, wenn ihr es erlaubt." : "Chat, Schreibhilfe und Rückblicke über dein eigenes ChatGPT-Abo.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                LoveIcon(symbol: "wand.and.sparkles", tint: LovePalette.violet, size: 58)
            }
            if ai.signedIn {
                HStack(spacing: 8) {
                    StatusChip(title: ai.modelName, symbol: "cpu", tint: LovePalette.violet)
                    if ai.serverStatus?.partnerSharing == true { StatusChip(title: "Gemeinsames Wissen", symbol: "person.2.fill", tint: LovePalette.pink) }
                }
            }
        }.loveCard()
    }

    private var askField: some View {
        HStack(spacing: 10) {
            TextField("Frag etwas über euch …", text: $question, axis: .vertical).lineLimit(1...4).submitLabel(.send).onSubmit(ask)
            Button(action: ask) {
                Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(LovePalette.dusk, in: Circle())
            }.buttonStyle(.lovePress).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Fragen")
        }.loveCard()
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        question = ""
        starter = ChatStarter(text: text)
    }

    private var diaryToday: some View {
        let today = DiaryDay.key(.now)
        let pages = app.diaryPages(on: today)
        let mine = pages.contains { $0.visibility == .privateOnly || $0.ownerID == app.me?.id }
        let partnerWrote = pages.contains { $0.visibility == .shared && $0.ownerID != app.me?.id }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Unser Tagebuch", systemImage: "book.pages.fill").font(.headline).foregroundStyle(LovePalette.violet)
                Spacer()
                NavigationLink { DiaryView() } label: { Text("Öffnen").font(.subheadline.weight(.semibold)) }
            }
            HStack(spacing: 10) {
                badge(mine ? "Du hast heute geschrieben" : "Deine Seite fehlt noch", mine)
                badge(partnerWrote ? "\(app.partner?.displayName ?? "Partner") hat geschrieben" : "\(app.partner?.displayName ?? "Partner") noch nicht", partnerWrote)
            }
            AdaptiveLoveRow {
                Button("Heute schreiben", systemImage: "pencil") { writing = DiaryEditorRoute(day: today, visibility: .shared) }.buttonStyle(.borderedProminent).tint(LovePalette.violet)
                if ai.signedIn { Button("KI schreibt mit", systemImage: "wand.and.sparkles") { writing = DiaryEditorRoute(day: today, visibility: .shared, autoCompose: true) }.buttonStyle(.bordered) }
            }
        }.loveCard()
    }

    private func badge(_ text: String, _ done: Bool) -> some View {
        Label(text, systemImage: done ? "checkmark.circle.fill" : "circle.dashed").font(.caption.weight(.semibold))
            .foregroundStyle(done ? Color.green : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background((done ? Color.green : Color.secondary).opacity(0.1), in: Capsule())
    }

    private func idea(_ title: String, _ symbol: String, _ tint: Color, _ prompt: String) -> some View {
        Button { if ai.signedIn { starter = ChatStarter(text: prompt) } } label: {
            VStack(alignment: .leading, spacing: 10) {
                LoveIcon(symbol: symbol, tint: tint, size: 38)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).padding(14)
            .loveGlass(in: RoundedRectangle(cornerRadius: LoveMetrics.tileRadius, style: .continuous))
        }.buttonStyle(.lovePress).disabled(!ai.signedIn)
    }
}

/// Home card: today's diary at a glance and a direct line to the companion.
struct CompanionHomeCard: View {
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var writing: DiaryEditorRoute?
    var body: some View {
        let today = DiaryDay.key(.now)
        let pages = app.diaryPages(on: today)
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink { CompanionView() } label: {
                HStack(spacing: 14) {
                    LoveIcon(symbol: "wand.and.sparkles", tint: LovePalette.violet, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KI & Tagebuch").font(.headline)
                        Text(pages.isEmpty ? "Heute ist noch keine Seite geschrieben." : "\(pages.count) \(pages.count == 1 ? "Seite" : "Seiten") für heute").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }.contentShape(Rectangle())
            }.buttonStyle(.lovePress)
            HStack(spacing: 10) {
                Button { writing = DiaryEditorRoute(day: today, visibility: .shared) } label: { Label("Schreiben", systemImage: "pencil").frame(maxWidth: .infinity) }
                NavigationLink { DiaryView() } label: { Label("Tagebuch", systemImage: "book.pages").frame(maxWidth: .infinity) }
                NavigationLink { GroupChatView() } label: { Label("Gruppe", systemImage: "person.3").frame(maxWidth: .infinity) }
            }.font(.caption.bold()).buttonStyle(.bordered).tint(LovePalette.violet)
        }
        .loveCard()
        .sheet(item: $writing) { DiaryEditorView(route: $0) }
    }
}
