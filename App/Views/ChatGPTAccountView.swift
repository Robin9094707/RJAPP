import SwiftUI

/// Profile → KI & ChatGPT: sign-in, model, behaviour and what the AI may know.
struct ChatGPTAccountView: View {
    @Environment(AppState.self) private var app
    @StateObject private var login = ChatGPTLogin()
    @State private var ai = AICompanion.shared
    @State private var signingOut = false
    @State private var clearingChats = false
    @State private var sharingBusy = false
    @State private var sharingError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if ai.signedIn { modelGroup; behaviourGroup }
                knowledgeGroup
                privacyGroup
                if ai.signedIn {
                    LoveGroup("Verwaltung") {
                        Button(role: .destructive) { clearingChats = true } label: { Label("Alle KI-Gespräche auf diesem iPhone löschen", systemImage: "trash") }
                            .disabled(ai.conversations.isEmpty)
                        LoveRowDivider()
                        Button(role: .destructive) { signingOut = true } label: { Label("Von ChatGPT abmelden", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                }
            }.padding(LoveMetrics.screenPadding).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(LoveBackground()).navigationTitle("KI & ChatGPT").navigationBarTitleDisplayMode(.inline)
        .task { ai.refreshAccount(); await ai.loadStatus(api: app.api); if ai.signedIn && ai.models.isEmpty { await ai.refreshModels() } }
        .confirmationDialog("Von ChatGPT abmelden?", isPresented: $signingOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await ai.signOut() } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Der Zugang auf diesem iPhone wird widerrufen. Dein Tagebuch und eure gemeinsamen Daten bleiben unverändert.") }
        .confirmationDialog("Alle KI-Gespräche löschen?", isPresented: $clearingChats, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { ai.deleteAllConversations() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    LoveEyebrow(text: "Optional · mit deinem eigenen Abo", tint: LovePalette.violet)
                    Text(ai.signedIn ? "Dein KI-Begleiter ist bereit." : "Mit ChatGPT anmelden.").font(.loveDisplay(30)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                LoveIcon(symbol: ai.signedIn ? "checkmark.seal.fill" : "wand.and.sparkles", tint: ai.signedIn ? .green : LovePalette.violet, size: 58)
            }
            if ai.signedIn {
                Label(ai.account, systemImage: "person.crop.circle.badge.checkmark").font(.subheadline.weight(.semibold))
                Text("Chat, Tagebuch-Hilfe und Rückblicke laufen über dein ChatGPT-Abo, direkt von diesem iPhone. Kein API-Schlüssel, keine Extrakosten am Server.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Jede Person meldet sich auf dem eigenen iPhone an. Ihr könnt auch beide dasselbe ChatGPT-Konto verwenden. Passwort und Bestätigungscodes gibst du nur auf der Seite von OpenAI ein.").font(.subheadline).foregroundStyle(.secondary)
                Button { login.start() } label: {
                    HStack { if login.busy { ProgressView().tint(.white) }; Label(login.busy ? "Anmeldung läuft …" : "Mit ChatGPT anmelden", systemImage: "person.badge.key.fill").frame(maxWidth: .infinity) }
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(LovePalette.violet).disabled(login.busy).accessibilityIdentifier("chatgpt-sign-in")
                if login.busy { Button("Abbrechen") { login.cancel() }.font(.caption).frame(maxWidth: .infinity) }
            }
            if let status = login.status { Text(status).font(.footnote).foregroundStyle(login.succeeded ? .green : .secondary) }
        }.loveCard()
    }

    private var modelGroup: some View {
        LoveGroup("Modell", footer: "Die Liste kommt direkt von deinem ChatGPT-Abo. Ist ein Modell gerade nicht verfügbar, nimmt RJ Love automatisch das nächste.") {
            if ai.models.isEmpty {
                HStack { if ai.loadingModels { ProgressView() }; Text(ai.loadingModels ? "Modelle werden geladen …" : "Noch keine Modelle geladen.").foregroundStyle(.secondary) }
            } else {
                Picker("Modell", selection: Binding(get: { ai.effectiveModel }, set: { ai.model = $0 })) {
                    ForEach(ai.models) { Text($0.name).tag($0.id) }
                }.pickerStyle(.navigationLink)
            }
            LoveRowDivider()
            Picker("Denktiefe", selection: Binding(get: { ai.effort }, set: { ai.effort = $0 })) {
                ForEach(AIEffort.allCases) { Text($0.title).tag($0) }
            }
            LoveRowDivider()
            Button { Task { await ai.refreshModels() } } label: { Label("Modelle aktualisieren", systemImage: "arrow.clockwise") }.disabled(ai.loadingModels)
        }
    }

    private var behaviourGroup: some View {
        VStack(alignment: .leading, spacing: 22) {
        LoveGroup("Persönlichkeit") {
            Picker("Ton", selection: Binding(get: { ai.personality }, set: { ai.personality = $0 })) {
                Text("Warm & liebevoll").tag("warm")
                Text("Verspielt & frech").tag("playful")
                Text("Ruhig & achtsam").tag("calm")
                Text("Direkt & praktisch").tag("direct")
            }
        }
        LoveGroup("Fähigkeiten", footer: "Die Internetsuche läuft über ChatGPT und nur, wenn dein Abo sie zulässt; sonst antwortet die KI automatisch ohne Suche. Spracheingabe und Transkription laufen immer auf dem iPhone, das ChatGPT-Abo unterstützt kein Audio.") {
            Toggle("Internetsuche erlauben", isOn: Binding(get: { ai.allowWeb }, set: { ai.allowWeb = $0; if $0 { ChatGPTClient.resetWebSearchCheck() } }))
            if ChatGPTClient.webSearchBlocked { Text("Dein Abo hat die Suche zuletzt abgelehnt. Morgen wird es erneut versucht.").font(.caption).foregroundStyle(.orange) }
            LoveRowDivider()
            Toggle("Tagebuch: Rückfragen beim Schreiben", isOn: Binding(get: { ai.diaryLiveQuestions }, set: { ai.diaryLiveQuestions = $0 }))
            LoveRowDivider()
            Toggle("Tagebuch: Stimmung & Themen vorschlagen", isOn: Binding(get: { ai.diaryAutoMood }, set: { ai.diaryAutoMood = $0 }))
        }
        }
    }

    private var knowledgeGroup: some View {
        LoveGroup("Was die KI wissen darf", footer: "Das App-Wissen wird nur beim Senden einer Frage als Text mitgeschickt. Fotos, Videos, Audio, GPS-Koordinaten und Passwörter werden nie übertragen.") {
            Stepper("Zeitraum: \(ai.contextDays) Tage", value: Binding(get: { ai.contextDays }, set: { ai.contextDays = $0; ai.invalidateContext() }), in: 7...120, step: 7)
            LoveRowDivider()
            Toggle("Nachrichten einbeziehen", isOn: Binding(get: { ai.includeChats }, set: { ai.includeChats = $0 }))
            LoveRowDivider()
            Toggle("Duftstudio einbeziehen", isOn: Binding(get: { ai.includeFarts }, set: { ai.includeFarts = $0 }))
            LoveRowDivider()
            Toggle("Schritte & Schlaf einbeziehen", isOn: Binding(get: { ai.includeHealth }, set: { ai.includeHealth = $0 }))
        }
    }

    private var privacyGroup: some View {
        let partner = app.partner?.displayName ?? "Dein Lieblingsmensch"
        return LoveGroup("Eure gegenseitige Freigabe", footer: "Ohne deine Freigabe sieht die KI deines Lieblingsmenschen nur dessen eigene Inhalte. Private Tagebuchseiten bleiben immer auf deinem iPhone.") {
            if let status = ai.serverStatus {
                Toggle(isOn: Binding(get: { status.mySharing == true }, set: { value in Task { await setSharing(value) } })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Meine Inhalte für \(partner)s KI")
                        Text("Momente, Tagebuch für uns, Wünsche, Nachrichten und Duftpost").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(sharingBusy).accessibilityIdentifier("ai-sharing")
                LoveRowDivider()
                Label(status.partnerSharing == true ? "\(partner) teilt Inhalte mit deiner KI" : "\(partner) hat noch nicht freigegeben", systemImage: status.partnerSharing == true ? "checkmark.circle.fill" : "person.crop.circle.badge.clock")
                    .font(.subheadline).foregroundStyle(status.partnerSharing == true ? .green : .secondary)
            } else {
                HStack { ProgressView(); Text("Freigaben werden geladen …").foregroundStyle(.secondary) }
            }
            if let sharingError { Text(sharingError).font(.footnote).foregroundStyle(.orange) }
            LoveRowDivider()
            NavigationLink { AISettingsView() } label: { LoveSettingsRow(title: "Server-Tagesrückblick", subtitle: "Älterer Rückblick über einen API-Schlüssel am Server", symbol: "server.rack", tint: LovePalette.cyan) }
        }
    }

    private func setSharing(_ value: Bool) async {
        sharingBusy = true
        defer { sharingBusy = false }
        do { try await ai.setSharing(value, api: app.api); sharingError = nil; Haptics.selection() }
        catch { sharingError = error.localizedDescription }
    }
}
