import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingWakeComposer = false
    @State private var showingStatusEditor = false
    @State private var heartPulse = false
    @State private var showingHealth = false
    @State private var showingNearby = false
    @State private var editingHome = false
    @Namespace private var profileTransition
    private var homeTint: Color { appState.homeLayout.theme == "ocean" ? LovePalette.cyan : appState.homeLayout.theme == "violet" ? LovePalette.violet : LovePalette.pink }
    private var partnerName: String { appState.partner?.displayName ?? "Dein Lieblingsmensch" }
    private var milestone: SharedRecord? { appState.records.first { $0.kind == .milestone } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                connection
                ForEach(appState.homeLayout.cards) { card in
                    homeCard(card).accessibilityIdentifier("home-card-" + card.id)
                }
                if appState.homeLayout.cards.isEmpty {
                    ContentUnavailableView("Platz für dein Wir", systemImage: "square.grid.2x2", description: Text("Füge über Anpassen deine Lieblingskarten hinzu."))
                }
                Text("Ein kleiner Ort. Nur für euch zwei.")
                    .font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 16)
            }.padding(.horizontal, 22).padding(.bottom, 20)
        }
        .background(LoveBackground()).tint(homeTint)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingHome) { HomeEditorView() }
        .sheet(isPresented: $showingWakeComposer) { WakeComposerView() }
        .sheet(isPresented: $showingStatusEditor) { StatusEditorSheet() }
        .sheet(isPresented: $showingHealth) { NavigationStack { HealthDashboardView() } }
        .sheet(isPresented: $showingNearby) { NavigationStack { NearbyView() } }
        .refreshable { await appState.syncNow(showErrors: false) }
    }

    @ViewBuilder private func homeCard(_ card: HomeCard) -> some View {
        switch card.kind {
        case .shortcuts: HomeShortcutsView()
        case .cinema:
            if card.size == .compact { homeLink(card,detail:"Plex, YouTube & AirPlay") { CinemaView() } }
            else { CinemaHomeCard() }
        case .homeKit:
            if card.size == .compact { homeLink(card,detail:"Kameras, Geräte & Szenen") { HomeKitView() } }
            else { HomeKitDashboardCard() }
        case .eveningPlayer:
            if EveningPlaylistService.shared.active && card.size == .large { EveningPlayerHomeCard() }
            else { homeLink(card,detail:"Eure Momente und Aufnahmen") { EveningPlaylistView() } }
        case .dailyJournal:
            if card.size == .compact { homeLink(card,detail:"Euer gemeinsamer Tag") { SharedJournalView() } }
            else { DailyJournalHomeCard() }
        case .documents: homeLink(card,detail:"Dateien, Ordner & Favoriten") { DocumentsView() }
        case .heart:
            if card.size == .compact {
                Button { Task { await appState.sendThought() } } label: {
                    HStack { Image(systemName: "heart.fill").foregroundStyle(homeTint).font(.title); VStack(alignment: .leading) { Text("Ein Herz für " + partnerName).font(.headline); Text("Du: \(appState.myThoughtCount) · Dein Lieblingsmensch: \(appState.partnerThoughtCount)").font(.caption).foregroundStyle(.secondary) }; Spacer() }.loveCard()
                }.buttonStyle(.plain)
            } else { heartSpace }
        case .partner:
            if card.size == .compact { HStack { PartnerAvatar(name: partnerName, size: 38); Text(partnerName).font(.headline); Spacer(); BatteryBadge(level: appState.partner?.presence?.batteryLevel, state: appState.partner?.presence?.batteryState) }.loveCard().onTapGesture{appState.showingPartnerProfile=true} }
            else { partnerCard }
        case .quickActions:
            if card.size == .compact { HStack { Button("Dich finden") { showingNearby = true }; Spacer(); Button("Wecken") { showingWakeComposer = true }; Spacer(); Button("Status") { showingStatusEditor = true } }.font(.subheadline.bold()).loveCard() }
            else { quickActions }
        case .studio:
            if card.size == .compact { Button { appState.selectedTab = .moments; appState.experienceSection = .farts } label: { Label("Duftstudio öffnen", systemImage: "wind").frame(maxWidth: .infinity, alignment: .leading).padding(16).loveGlass(in: RoundedRectangle(cornerRadius: 24)) }.buttonStyle(.plain) }
            else { studioSpotlight }
        case .messenger: homeLink(card, detail: "Fotos, Worte & deine Stimme") { MessengerView() }
        case .history: homeLink(card, detail: "Jeder kleine Ich-denke-an-dich-Moment") { ThoughtHistoryView() }
        case .planner: homeLink(card, detail: "Termine, Erinnerungen und Jahrestage") { PlannerView() }
        case .instant: homeLink(card, detail: "Ein Lächeln nur für euch") { InstantGalleryView() }
        case .milestone: homeLink(card,detail:"Jahrestag, gemeinsame Tage und eure Countdowns") {CountdownHubView()}
        case .health:
            if card.size == .compact {
                HStack { Label("RJ-Schlafindex", systemImage: "moon.stars.fill"); Spacer(); Text(appState.partner?.presence?.sleepScore.map { "\($0) / 100" } ?? "–").bold() }.loveCard()
            } else { healthCard }
        case .live:
            if card.size == .compact { homeLink(card, detail: "Deine Live-Aktivitäten") { DeliveryCenterView() } }
            else { liveCard }
        case .relationship: RelationshipHomeCard()
        case .poop: homeLink(card,detail:"Euer privates Thronarchiv & eure Kack-Karte") {DropPoopView()}
        case .delivery: homeLink(card, detail: "Push, Wecker & Hintergrund prüfen") { DeliveryCenterView() }
        }
    }
    private func homeLink<Destination: View>(_ card: HomeCard, detail: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 14) {
                LoveIcon(symbol:card.kind.symbol,tint:homeTint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.kind.title).font(.headline)
                    if card.size == .large { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(card.size == .large ? 18 : 14).loveGlass(in:RoundedRectangle(cornerRadius:24))
        }.buttonStyle(.plain)
    }

    private var studioSpotlight: some View {
        HStack(spacing: 12) {
            Button {
                appState.selectedTab = .moments; appState.experienceSection = .farts
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wind").font(.title2).foregroundStyle(LovePalette.violet)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Euer neues Duftstudio").font(.subheadline.bold())
                        Text("Kalender, Karte & kleine Klassiker").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity,alignment: .leading)
                }
            }.buttonStyle(.plain)
            Button { appState.openFartRecorder() } label: {
                Image(systemName: "mic.fill").font(.title3).foregroundStyle(.white).frame(width: 48,height: 48).background(LovePalette.violet.gradient,in: Circle())
            }.accessibilityLabel("Duftaufnahme starten")
        }.loveCard()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                LoveEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Text(appState.homeLayout.title).font(.system(size: 32, weight: .medium, design: .serif)).tracking(-0.5).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rj-home-title")
            }
            Spacer(minLength: 4)
            Button { editingHome = true } label: {
                Image(systemName: "slider.horizontal.3").font(.headline).frame(width: 44, height: 44).background(homeTint.opacity(0.12), in: Circle())
            }.accessibilityLabel("Startseite anpassen").accessibilityIdentifier("home-customize")
            Button { appState.showingProfile = true } label: {
                PartnerAvatar(name: appState.me?.displayName ?? "R", size: 46)
            }.matchedTransitionSource(id:"profile",in:profileTransition).accessibilityLabel("Dein Profil und Einstellungen").accessibilityIdentifier("home-profile")
        }.padding(.top, 20)
    }

    private var connection: some View {
        HStack(spacing: 7) {
            Circle().fill(isFresh ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(appState.isSyncing ? "Ein Moment für euch …" : isFresh ? "Euer privater Raum ist verbunden" : appState.connectionMessage)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if appState.isUsingHTTPS { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
        }
    }
    private var isFresh: Bool { appState.lastSync.map { Date.now.timeIntervalSince($0) < 40 } ?? false }

    private var heartSpace: some View {
        VStack(spacing: 18) {
            LoveEyebrow(text: "Robin & Raphaela")
            Text("Ein kleiner Gedanke.\nGanz nah bei dir.")
                .font(.system(size: 27, weight: .medium, design: .serif)).multilineTextAlignment(.center).lineSpacing(3)
            ZStack {
                ForEach(0..<3) { ring in
                    Circle().stroke(LovePalette.pink.opacity(0.12 - Double(ring) * 0.025), lineWidth: 1)
                        .frame(width: CGFloat(130 + ring * 27), height: CGFloat(130 + ring * 27))
                        .scaleEffect(heartPulse && !reduceMotion ? 1.06 : 1)
                }
                Button {
                    Task { await appState.sendThought() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { heartPulse = true }
                    Task { try? await Task.sleep(for: .milliseconds(400)); withAnimation { heartPulse = false } }
                } label: {
                    Image(systemName: "heart.fill").font(.system(size: 45, weight: .light))
                        .foregroundStyle(.white.gradient).frame(width: 116, height: 116)
                        .background(LinearGradient(colors: [Color(red: 0.98, green: 0.49, blue: 0.57), LovePalette.pink, Color(red: 0.60, green: 0.16, blue: 0.36)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))
                        .shadow(color: LovePalette.pink.opacity(0.3), radius: 22, y: 10)
                        .scaleEffect(heartPulse && !reduceMotion ? 1.12 : 1)
                }.buttonStyle(.plain).accessibilityLabel("Herzgedanken an \(partnerName) senden")
            }.frame(maxWidth: .infinity).frame(height: 190).accessibilityIdentifier("rj-heart-space")
            Text("Ein Tipp. Ein Ich-denke-an-dich.").font(.caption).foregroundStyle(.secondary)
            HStack {
                thoughtCount("Von dir", appState.myThoughtCount)
                Image(systemName: "infinity").foregroundStyle(LovePalette.pink).frame(maxWidth: .infinity)
                thoughtCount("Von \(partnerName)", appState.partnerThoughtCount)
            }.padding(.top, 5)
        }.frame(maxWidth: .infinity).padding(.vertical, 8).loveCard()
    }
    private func thoughtCount(_ title: String, _ count: Int) -> some View {
        VStack(spacing: 3) {
            Text(count.formatted()).font(.system(.title2, design: .rounded, weight: .semibold)).contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private var partnerCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            LoveEyebrow(text: "Dein Lieblingsmensch")
            HStack(spacing: 13) {
                PartnerAvatar(name: partnerName, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(partnerName).font(.title3.bold())
                    Text(appState.partner?.presence?.visibleStatus ?? "Euer nächster kleiner Moment wartet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if appState.partner?.presence?.isQuiet == true {Label("Bitte nicht stören",systemImage:"moon.fill").font(.caption).foregroundStyle(.secondary)}
            Divider().opacity(0.5)
            HStack {
                Label(appState.partner?.presence?.motion ?? "Noch kein Bewegungsstatus", systemImage: MotionPresentation.symbol(appState.partner?.presence?.motion ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                BatteryBadge(level: appState.partner?.presence?.batteryLevel, state: appState.partner?.presence?.batteryState)
            }
            if let date = appState.partner?.presence?.updatedAt?.rjDate {
                Text("Zuletzt geteilt \(date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
            }
            Button("Profil & Aktivität ansehen",systemImage:"person.text.rectangle"){appState.showingPartnerProfile=true}.font(.subheadline.bold())
        }.loveCard()
    }

    private var quickActions: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145))], spacing: 12) {
            action("Dich finden", "Ganz in eurer Nähe", "location.north.circle.fill", LovePalette.cyan) { showingNearby = true }
            action("Ein paar Worte", "Euer privater Chat", "bubble.left.and.bubble.right.fill", LovePalette.violet) { appState.selectedTab = .together }
            action("Sanft wecken", "Ein lieber Weckruf", "sunrise.fill", LovePalette.coral) { showingWakeComposer = true }
            action("Mein Gefühl", "Lass mich teilhaben", "face.smiling", LovePalette.pink) { showingStatusEditor = true }
        }
    }
    private func action(_ title: String, _ detail: String, _ symbol: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                LoveIcon(symbol:symbol,tint:tint)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .loveGlass(in:RoundedRectangle(cornerRadius:24))
        }.buttonStyle(.plain)
    }
    private func milestoneCard(_ record: SharedRecord) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "calendar.badge.heart").font(.largeTitle).foregroundStyle(LovePalette.pink)
            VStack(alignment: .leading, spacing: 6) {
                LoveEyebrow(text: "Eure Zeit")
                Text(record.payload.title ?? "Ein besonderer Tag").font(.headline)
                if let date = record.payload.startAt?.rjDate {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
                    Text(days >= 0 ? "Noch \(days) Tage" : "Seit \(abs(days)) Tagen")
                        .font(.system(.title2, design: .serif)).foregroundStyle(LovePalette.pink)
                }
            }
            Spacer()
        }.loveCard()
    }
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                LoveSectionTitle("Ein gutes Gefühl", subtitle: "Was dein Lieblingsmensch mit dir teilt")
                Button { showingHealth = true } label: { Image(systemName: "arrow.up.right").font(.headline) }.accessibilityLabel("Health-Übersicht öffnen")
            }
            HStack(spacing: 10) {
                LoveMetric(title: "Schritte heute", value: appState.partner?.presence?.steps?.formatted() ?? "–", symbol: "figure.walk", tint: LovePalette.cyan)
                LoveMetric(title: "Letzter Schlaf", value: appState.partner?.presence?.sleepMinutes.map { "\($0 / 60) h \($0 % 60)" } ?? "–", symbol: "moon.zzz.fill", tint: LovePalette.violet)
            }
            HStack { Label("RJ-Schlafindex", systemImage: "moon.stars.fill"); Spacer(); Text(appState.partner?.presence?.sleepScore.map { "\($0) / 100" } ?? "Noch kein Wert").bold() }.font(.subheadline).padding(16).background(homeTint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        }.loveCard()
    }
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(LovePalette.pink)
                Text("Euer Wir. Immer im Blick.").font(.headline)
            }
            Text("Status, Akku und Herzgedanken auf Sperrbildschirm und Dynamic Island. Bis zu acht Stunden; bei eingeschalteter Option startet sie beim nächsten Öffnen erneut. Hintergrund-Ortung aktivierst du getrennt im Profil.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button(appState.liveActivity.isStarting ? "Startet …":appState.liveActivity.isRunning ? "Live-Aktivität beenden":"Jetzt starten",systemImage:"livephoto") {
                    Task {if appState.liveActivity.isRunning {await appState.liveActivity.stop()}else{await appState.startLiveActivity()}}
                }.buttonStyle(.borderedProminent).disabled(appState.liveActivity.isStarting)
                NavigationLink{LiveActivitySettingsView()}label:{Image(systemName:"slider.horizontal.3")}.buttonStyle(.bordered).accessibilityLabel("Live-Aktivität einstellen")
            }
            if appState.liveActivity.isRunning {Label("Live-Aktivität aktiv",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green)}
        }.loveCard()
    }
}
private struct WakeComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var message = "Guten Morgen, mein Schatz 💗"
    @State private var confirming = false
    @State private var scheduled = false
    @State private var dueAt = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
    @State private var sending = false
    @State private var repeatUntilAck = false
    @State private var partnerPush: PartnerPushStatus?

    var body: some View {
        NavigationStack {
            Form {
                Section("Wecknachricht") {
                    TextField("Nachricht", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Zeitpunkt") {
                    Toggle("Weckruf im Voraus planen", isOn: $scheduled)
                    if scheduled { DatePicker("Weckzeit", selection: $dueAt, in: Date.now.addingTimeInterval(10)...Date.now.addingTimeInterval(30 * 86400)).datePickerStyle(.compact) }
                    Text("Der Server versendet den Weckruf zur gewählten Zeit. Das Empfänger-iPhone braucht Bark und Internet. Ruhezeiten werden beim Versand erneut geprüft.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    if let partnerPush, partnerPush.quiet.active {
                        Label(partnerPush.quiet.label + " · Weckrufe derzeit gesperrt", systemImage: "moon.zzz.fill")
                    }
                    Toggle("Wiederholen, bis Schatzi bestätigt", isOn: $repeatUntilAck)
                        .disabled(partnerPush?.provider == "ntfy")
                    Label("Bark klingelt bis zu 30 Sekunden. Optional alle 45 Sekunden erneut, bis zur Bestätigung, Ruhezeit oder der gewählten Zeitgrenze. ntfy versendet nur normale Hinweise.", systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Schatzi wecken")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Wecken") { confirming = true }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            }
            .confirmationDialog(
                "Weckruf wirklich senden?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button(scheduled ? "Weckruf für diese Zeit senden" : "Ja, jetzt wecken", role: .destructive) {
                    sending = true
                    Task {
                        if await appState.sendWake(message: message, dueAt: scheduled ? dueAt : .now.addingTimeInterval(2), repeatUntilAck: repeatUntilAck) { dismiss() }
                        sending = false
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der Weckruf wird über den gewählten Push-Dienst versendet. Die Ruhezeit deines Gegenübers hat Vorrang.")
            }
        }
        .task { if let status = try? await appState.api.externalPushStatus() { partnerPush = status.partners.first } }
        .presentationDetents([.medium, .large])
    }
}


