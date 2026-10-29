import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingWakeComposer = false
    @State private var showingStatusEditor = false
    @State private var heartBursts = 0
    @State private var showingHealth = false
    @State private var showingNearby = false
    @State private var editingHome = false
    @State private var revealed = false
    @Namespace private var profileTransition
    private var homeTint: Color { appState.homeLayout.theme == "ocean" ? LovePalette.cyan : appState.homeLayout.theme == "violet" ? LovePalette.violet : LovePalette.pink }
    private var partnerName: String { appState.partner?.displayName ?? "Dein Lieblingsmensch" }
    private var milestone: SharedRecord? { appState.records.first { $0.kind == .milestone } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LoveMetrics.stackSpacing) {
                header.loveReveal(revealed, index: 0)
                connection.loveReveal(revealed, index: 1)
                ForEach(Array(appState.homeLayout.cards.enumerated()), id: \.element.id) { index, card in
                    homeCard(card).accessibilityIdentifier("home-card-" + card.id)
                        .loveReveal(revealed, index: index + 2)
                        .loveScrollEffect()
                }
                if appState.homeLayout.cards.isEmpty {
                    ContentUnavailableView("Platz für dein Wir", systemImage: "square.grid.2x2", description: Text("Füge über Anpassen deine Lieblingskarten hinzu."))
                }
                Label("Ein kleiner Ort. Nur für euch zwei.", systemImage: "heart")
                    .font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 16)
            }.padding(.horizontal, LoveMetrics.screenPadding).padding(.bottom, 24)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(LoveBackground()).tint(homeTint)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingHome) { HomeEditorView() }
        .sheet(isPresented: $showingWakeComposer) { WakeComposerView() }
        .sheet(isPresented: $showingStatusEditor) { StatusEditorSheet() }
        .sheet(isPresented: $showingHealth) { NavigationStack { HealthDashboardView() } }
        .sheet(isPresented: $showingNearby) { NavigationStack { NearbyView() } }
        .refreshable { await appState.syncNow(showErrors: false) }
        .onAppear { revealed = true }
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
                Button { sendHeart() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "heart.fill").font(.title2).foregroundStyle(LovePalette.heart)
                            .symbolEffect(.bounce, value: heartBursts)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ein Herz für " + partnerName).font(.headline)
                            Text("Du: \(appState.myThoughtCount) · Dein Lieblingsmensch: \(appState.partnerThoughtCount)").font(.caption).foregroundStyle(.secondary)
                                .contentTransition(.numericText()).animation(LoveMotion.snappy, value: appState.myThoughtCount)
                        }
                        Spacer()
                    }.loveCard().overlay { LoveHeartBurst(trigger: heartBursts, tint: homeTint) }.contentShape(Rectangle())
                }.buttonStyle(.lovePress)
            } else { heartSpace }
        case .partner:
            if card.size == .compact {
                Button { appState.showingPartnerProfile = true } label: {
                    HStack(spacing: 12) {
                        PartnerAvatar(name: partnerName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(partnerName).font(.headline)
                            if let status = appState.partner?.presence?.visibleStatus { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        BatteryBadge(level: appState.partner?.presence?.batteryLevel, state: appState.partner?.presence?.batteryState)
                    }.loveCard()
                }.buttonStyle(.lovePress)
            }
            else { partnerCard }
        case .quickActions:HomeShortcutsView(shortcuts:appState.homeLayout.actions,title:"Deine Schnellaktionen",compact:card.size == .compact)
        case .studio:
            if card.size == .compact {
                Button { appState.selectedTab = .moments; appState.experienceSection = .farts } label: {
                    HStack(spacing: 14) {
                        LoveIcon(symbol: "wind", tint: LovePalette.violet, size: 40)
                        Text("Duftstudio öffnen").font(.headline)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }.padding(14).loveGlass(in: RoundedRectangle(cornerRadius: LoveMetrics.tileRadius, style: .continuous))
                }.buttonStyle(.lovePress)
            }
            else { studioSpotlight }
        case .messenger: homeLink(card, detail: "Fotos, Worte & deine Stimme") { MessengerView() }
        case .history: homeLink(card, detail: "Jeder kleine Ich-denke-an-dich-Moment") { ThoughtHistoryView() }
        case .planner: homeLink(card, detail: "Termine, Erinnerungen und Jahrestage") { PlannerView() }
        case .instant: homeLink(card, detail: "Ein Lächeln nur für euch") { InstantGalleryView() }
        case .milestone: homeLink(card,detail:"Jahrestag, gemeinsame Tage und eure Countdowns") {CountdownHubView()}
        case .health:
            if card.size == .compact {
                HStack { Label("RJ-Schlafindex", systemImage: "moon.stars.fill").foregroundStyle(LovePalette.violet); Spacer(); Text(appState.partner?.presence?.sleepScore.map { "\($0) / 100" } ?? "–").bold().contentTransition(.numericText()) }.loveCard()
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
                LoveIcon(symbol:card.kind.symbol,tint:homeTint,size: card.size == .large ? 46 : 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.kind.title).font(.headline).foregroundStyle(.primary)
                    if card.size == .large { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(card.size == .large ? 18 : 14)
                .loveGlass(in:RoundedRectangle(cornerRadius:LoveMetrics.tileRadius + 2, style: .continuous))
        }.buttonStyle(.lovePress)
    }

    private var studioSpotlight: some View {
        HStack(spacing: 14) {
            Button {
                appState.selectedTab = .moments; appState.experienceSection = .farts
            } label: {
                HStack(spacing: 14) {
                    LoveIcon(symbol: "wind", tint: LovePalette.violet, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Euer Duftstudio").font(.headline)
                        Text("Kalender, Karte & kleine Klassiker").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity,alignment: .leading)
                }
            }.buttonStyle(.lovePress)
            Button { Haptics.impact(.soft); appState.openFartRecorder() } label: {
                Image(systemName: "mic.fill").font(.title3.weight(.semibold)).foregroundStyle(.white).frame(width: 52,height: 52)
                    .background(LovePalette.dusk, in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                    .shadow(color: LovePalette.violet.opacity(0.3), radius: 10, y: 5)
            }.buttonStyle(.lovePress).accessibilityLabel("Duftaufnahme starten")
        }.loveCard()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base: String
        switch hour {
        case 5..<11: base = "Guten Morgen"
        case 11..<17: base = "Schön, dass du da bist"
        case 17..<22: base = "Guten Abend"
        default: base = "Gute Nacht"
        }
        guard let first = appState.me?.displayName.split(separator: " ").first, !first.isEmpty else { return base }
        return base + ", " + first
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                LoveEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), tint: homeTint)
                Text(greeting).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(appState.homeLayout.title).font(.loveDisplay(34)).tracking(-0.6).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rj-home-title")
            }
            Spacer(minLength: 4)
            Button { editingHome = true } label: {
                Image(systemName: "slider.horizontal.3").font(.headline).foregroundStyle(homeTint).frame(width: 46, height: 46)
                    .loveInteractiveGlass(in: Circle(), tint: homeTint.opacity(0.06))
            }.buttonStyle(.lovePress).accessibilityLabel("Startseite anpassen").accessibilityIdentifier("home-customize")
            Button { appState.showingProfile = true } label: {
                PartnerAvatar(name: appState.me?.displayName ?? "R", size: 48)
            }.buttonStyle(.lovePress).matchedTransitionSource(id:"profile",in:profileTransition).accessibilityLabel("Dein Profil und Einstellungen").accessibilityIdentifier("home-profile")
        }.padding(.top, 18)
    }

    private var connection: some View {
        HStack(spacing: 8) {
            LovePulseDot(color: isFresh ? .green : .orange, active: isFresh || appState.isSyncing)
            Text(appState.isSyncing ? "Ein Moment für euch …" : isFresh ? "Euer privater Raum ist verbunden" : appState.connectionMessage)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                .contentTransition(.opacity)
            if appState.isUsingHTTPS { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(LoveSurface.card, in: Capsule())
        .accessibilityElement(children: .combine)
    }
    private var isFresh: Bool { appState.lastSync.map { Date.now.timeIntervalSince($0) < 40 } ?? false }

    private func sendHeart() {
        heartBursts += 1
        Task { await appState.sendThought() }
    }

    private var heartSpace: some View {
        VStack(spacing: 18) {
            LoveEyebrow(text: "Robin & Raphaela", tint: homeTint)
            Text("Ein kleiner Gedanke.\nGanz nah bei dir.")
                .font(.loveDisplay(27)).multilineTextAlignment(.center).lineSpacing(3)
            ZStack {
                ForEach(0..<3) { ring in
                    Circle().stroke(homeTint.opacity(0.14 - Double(ring) * 0.035), lineWidth: 1)
                        .frame(width: CGFloat(130 + ring * 28), height: CGFloat(130 + ring * 28))
                }
                LoveHeartBurst(trigger: heartBursts, tint: homeTint)
                Button {
                    sendHeart()
                } label: {
                    Image(systemName: "heart.fill").font(.system(size: 46, weight: .light))
                        .foregroundStyle(.white.gradient).frame(width: 118, height: 118)
                        .background(LovePalette.heart, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1.5))
                        .shadow(color: homeTint.opacity(0.3), radius: 12, y: 6)
                        .symbolEffect(.bounce, value: heartBursts)
                }.buttonStyle(.lovePress).accessibilityLabel("Herzgedanken an \(partnerName) senden")
            }.frame(maxWidth: .infinity).frame(height: 196).accessibilityIdentifier("rj-heart-space")
            Text("Ein Tipp. Ein Ich-denke-an-dich.").font(.caption).foregroundStyle(.secondary)
            HStack {
                thoughtCount("Von dir", appState.myThoughtCount)
                Image(systemName: "infinity").foregroundStyle(homeTint).frame(maxWidth: .infinity)
                thoughtCount("Von \(partnerName)", appState.partnerThoughtCount)
            }.padding(.top, 5)
        }.frame(maxWidth: .infinity).padding(.vertical, 8).loveCard()
    }
    private func thoughtCount(_ title: String, _ count: Int) -> some View {
        VStack(spacing: 3) {
            Text(count.formatted()).font(.system(.title2, design: .rounded, weight: .semibold))
                .contentTransition(.numericText(value: Double(count))).animation(LoveMotion.snappy, value: count)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private var partnerCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            LoveEyebrow(text: "Dein Lieblingsmensch", tint: homeTint)
            HStack(spacing: 14) {
                PartnerAvatar(name: partnerName, size: 60)
                    .overlay(alignment: .bottomTrailing) {
                        if let presence = appState.partner?.presence, presence.appState == "foreground",
                           let seen = (presence.updatedAt ?? presence.reportedAt)?.rjDate, Date.now.timeIntervalSince(seen) < 120 {
                            Circle().fill(.green).frame(width: 14, height: 14).overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                                .accessibilityLabel("Gerade in der App")
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(partnerName).font(.title3.bold())
                    Text(appState.partner?.presence?.visibleStatus ?? "Euer nächster kleiner Moment wartet.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if appState.partner?.presence?.isQuiet == true { StatusChip(title: "Bitte nicht stören", symbol: "moon.fill", tint: LovePalette.violet) }
            HStack(spacing: 10) {
                Label(MotionPresentation.title(appState.partner?.presence?.motion ?? "Unbekannt"), systemImage: MotionPresentation.symbol(appState.partner?.presence?.motion ?? ""))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                BatteryBadge(level: appState.partner?.presence?.batteryLevel, state: appState.partner?.presence?.batteryState)
            }
            .padding(12).background(homeTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let date = appState.partner?.presence?.updatedAt?.rjDate {
                Text("Zuletzt geteilt \(date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
            }
            Button { appState.showingPartnerProfile = true } label: {
                Label("Profil & Aktivität ansehen", systemImage: "person.text.rectangle").font(.subheadline.bold()).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }.loveCard()
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
                Button { showingHealth = true } label: { Image(systemName: "arrow.up.right").font(.headline).frame(width: 40, height: 40).loveInteractiveGlass(in: Circle()) }.buttonStyle(.lovePress).accessibilityLabel("Health-Übersicht öffnen")
            }
            HStack(spacing: 10) {
                LoveMetric(title: "Schritte heute", value: appState.partner?.presence?.steps?.formatted() ?? "–", symbol: "figure.walk", tint: LovePalette.cyan)
                LoveMetric(title: "Letzter Schlaf", value: appState.partner?.presence?.sleepMinutes.map { "\($0 / 60) h \($0 % 60)" } ?? "–", symbol: "moon.zzz.fill", tint: LovePalette.violet)
            }
            HStack { Label("RJ-Schlafindex", systemImage: "moon.stars.fill"); Spacer(); Text(appState.partner?.presence?.sleepScore.map { "\($0) / 100" } ?? "Noch kein Wert").bold() }.font(.subheadline).padding(16).background(homeTint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.loveCard()
    }
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LoveIcon(symbol: "waveform.path.ecg", tint: homeTint, size: 40)
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
            if appState.liveActivity.isRunning {Label("Live-Aktivität aktiv",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.green).transition(.opacity)}
        }.loveCard().animation(LoveMotion.gentle, value: appState.liveActivity.isRunning)
    }
}
struct WakeComposerView: View {
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


