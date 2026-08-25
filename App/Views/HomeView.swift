import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showingWakeComposer = false
    @State private var showingStatusEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                connectionCard
                partnerCard
                thoughtCard
                actionGrid
                liveActivityCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(LoveBackground())
        .navigationTitle("RJ Love")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await appState.syncNow() }
                } label: {
                    if appState.isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("Jetzt synchronisieren")
            }
        }
        .sheet(isPresented: $showingWakeComposer) {
            WakeComposerView()
        }
        .sheet(isPresented: $showingStatusEditor) {
            StatusEditorView()
        }
        .refreshable { await appState.syncNow(showErrors: false) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.bold())
                Text("\(appState.me?.displayName ?? "Du") & \(appState.partner?.displayName ?? "Schatzi")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 38))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, LovePalette.pink)
        }
        .padding(.top, 8)
    }

    private var connectionCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.lastSync == nil ? Color.orange : Color.green)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.connectionMessage)
                    .font(.subheadline.weight(.semibold))
                if let date = appState.lastSync {
                    Text("Letzter Abgleich \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: appState.isUsingHTTPS ? "lock.fill" : "lock.open.fill")
                .foregroundStyle(appState.isUsingHTTPS ? .green : .orange)
        }
        .padding(14)
        .loveGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var partnerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 15) {
                PartnerAvatar(name: appState.partner?.displayName ?? "Schatzi")
                VStack(alignment: .leading, spacing: 5) {
                    Text(appState.partner?.displayName ?? "Schatzi")
                        .font(.title2.bold())
                    Text(appState.partner?.presence?.statusMessage ?? "Noch kein Status geteilt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    lastSeen
                }
                Spacer()
                BatteryBadge(
                    level: appState.partner?.presence?.batteryLevel,
                    state: appState.partner?.presence?.batteryState
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusChip(
                        title: networkLabel,
                        symbol: networkSymbol,
                        tint: LovePalette.cyan
                    )
                    StatusChip(
                        title: appState.partner?.presence?.motion ?? "Bewegung unbekannt",
                        symbol: motionSymbol,
                        tint: LovePalette.violet
                    )
                    if let focus = appState.partner?.presence?.focusActive {
                        StatusChip(
                            title: focus ? "Fokus aktiv" : "Erreichbar",
                            symbol: focus ? "moon.fill" : "bell.fill",
                            tint: focus ? .indigo : .green
                        )
                    }
                    if appState.partner?.presence?.locationSharing == true {
                        StatusChip(title: "Standort geteilt", symbol: "location.fill", tint: .green)
                    }
                }
            }

            if let steps = appState.partner?.presence?.steps,
               let sleep = appState.partner?.presence?.sleepMinutes {
                HStack(spacing: 10) {
                    metric(title: "Schritte", value: steps.formatted(), symbol: "figure.walk", tint: LovePalette.cyan)
                    metric(title: "Schlaf", value: durationLabel(sleep), symbol: "bed.double.fill", tint: LovePalette.violet)
                    if let score = appState.partner?.presence?.sleepScore {
                        metric(title: "Balance", value: "\(score)", symbol: "sparkles", tint: LovePalette.pink)
                    }
                }
            }
        }
        .loveCard()
    }

    private var thoughtCard: some View {
        VStack(spacing: 18) {
            LoveSectionTitle("Ein kleiner Herzschlag", subtitle: "Sag ohne Worte, dass du gerade an dein Schatzi denkst.")
            Button {
                Haptics.impact(.soft)
                Task { await appState.sendThought() }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [LovePalette.pink, LovePalette.coral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 98, height: 98)
                        .shadow(color: LovePalette.pink.opacity(0.42), radius: 24, y: 9)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("An Schatzi denken")

            HStack {
                thoughtCount(name: "Du", count: appState.myThoughtCount, tint: LovePalette.cyan)
                Spacer()
                Image(systemName: "infinity")
                    .foregroundStyle(LovePalette.pink)
                Spacer()
                thoughtCount(name: appState.partner?.displayName ?? "Schatzi", count: appState.partnerThoughtCount, tint: LovePalette.pink)
            }
        }
        .loveCard()
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            LoveSectionTitle("Schnell für euch")
            HStack(spacing: 12) {
                actionButton("Sanft wecken", symbol: "alarm.waves.left.and.right.fill", tint: LovePalette.pink) {
                    showingWakeComposer = true
                }
                actionButton("Mein Status", symbol: "quote.bubble.fill", tint: LovePalette.cyan) {
                    showingStatusEditor = true
                }
            }
        }
    }

    private var liveActivityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.title2)
                .foregroundStyle(LovePalette.pink)
            VStack(alignment: .leading, spacing: 3) {
                Text("Unsere Live-Aktivität")
                    .font(.headline)
                Text("Akku, Bewegung und Herzgedanken auf Sperrbildschirm & Dynamic Island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(appState.liveActivity.isRunning ? "Stop" : "Start") {
                Task {
                    if appState.liveActivity.isRunning {
                        await appState.liveActivity.stop()
                    } else {
                        do {
                            try await appState.liveActivity.start(
                                partnerName: appState.partner?.displayName ?? "Schatzi",
                                battery: appState.partner?.presence?.batteryLevel,
                                motion: appState.partner?.presence?.motion ?? "Unbekannt",
                                mine: appState.myThoughtCount,
                                partner: appState.partnerThoughtCount
                            )
                        } catch {
                            appState.alert = AppAlert(title: "Live-Aktivität", message: error.localizedDescription)
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .loveCard()
    }

    private var lastSeen: some View {
        Group {
            if let value = appState.partner?.presence?.updatedAt?.rjDate ?? appState.partner?.presence?.reportedAt?.rjDate {
                Label(value.formatted(.relative(presentation: .named)), systemImage: "clock.fill")
                    .foregroundStyle(Date.now.timeIntervalSince(value) < 90 ? .green : .secondary)
            } else {
                Label("Noch nie synchronisiert", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "Guten Morgen 💗"
        case 11..<18: "Hallöchen 💗"
        default: "Schönen Abend 💗"
        }
    }

    private var networkLabel: String {
        if let wifi = appState.partner?.presence?.wifiName, !wifi.isEmpty { return wifi }
        return switch appState.partner?.presence?.networkType {
        case "wifi": "WLAN"
        case "cellular": "Mobilfunk"
        case "offline": "Offline"
        case "ethernet": "Ethernet"
        default: "Netz unbekannt"
        }
    }

    private var networkSymbol: String {
        return switch appState.partner?.presence?.networkType {
        case "wifi": "wifi"
        case "cellular": "antenna.radiowaves.left.and.right"
        case "offline": "wifi.slash"
        default: "network"
        }
    }

    private var motionSymbol: String {
        return switch appState.partner?.presence?.motion {
        case "Auto": "car.fill"
        case "Fahrrad": "bicycle"
        case "Laufen": "figure.run"
        case "Zu Fuß": "figure.walk"
        default: "figure.stand"
        }
    }

    private func metric(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func thoughtCount(name: String, count: Int, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(count.formatted()).font(.title2.bold()).monospacedDigit().foregroundStyle(tint)
            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .loveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func durationLabel(_ minutes: Int) -> String {
        "\(minutes / 60) h \(minutes % 60) min"
    }
}

private struct WakeComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var message = "Guten Morgen, mein Schatz 💗"
    @State private var confirming = false
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Wecknachricht") {
                    TextField("Nachricht", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Label("AlarmKit kann den Systemwecker erst auslösen, wenn das andere iPhone den Befehl per Push oder Synchronisierung empfangen hat.", systemImage: "info.circle.fill")
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
                Button("Ja, jetzt wecken", role: .destructive) {
                    sending = true
                    Task {
                        if await appState.sendWake(message: message) { dismiss() }
                        sending = false
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Auf dem iPhone von \(appState.partner?.displayName ?? "Schatzi") wird nach dem Empfang ein AlarmKit-Weckruf geplant.")
            }
        }
        .presentationDetents([.medium])
    }
}

private struct StatusEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Was möchtest du mitteilen?", text: $value, axis: .vertical)
                    .lineLimit(3...6)
                Text("Maximal 120 Zeichen · wird nur mit deinem Partner geteilt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Mein Status")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        appState.statusMessage = String(value.prefix(120))
                        appState.queuePresenceUpload(force: true)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { value = appState.statusMessage }
        .presentationDetents([.medium])
    }
}
