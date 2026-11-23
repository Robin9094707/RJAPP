import Charts
import SwiftUI

/// 10.0: Live data and nerd info for both iPhones. When battery, position and health last reached
/// the server, through which wake path, plus the full device telemetry and the local wake journal.
struct LiveTelemetryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @ObservedObject private var location = LocationService.shared
    @State private var engine = LiveBackgroundEngine.shared
    @State private var data: PresenceTelemetryResponse?
    @State private var loading = false
    @State private var error: String?
    @State private var pinging = false
    @State private var pingMessage: String?
    @State private var watchedPing: String?
    @State private var showAllWakes = false
    private var journal: WakeJournal { WakeJournal.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let error { errorBanner(error) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 16) {
                        ForEach(orderedUsers) { user in DeviceTelemetryCard(user: user, now: context.date) }
                        if data == nil && loading { placeholderCard }
                    }
                }
                pingCard
                if let data, data.users.contains(where: { !$0.reports.isEmpty }) {
                    batteryChart(data.users)
                    sourceChart(data.users)
                }
                engineCard
                journalCard
                limitsCard
            }
            .padding(LoveMetrics.screenPadding)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(LoveBackground())
        .navigationTitle("Live-Daten")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(watchedPing == nil ? 10 : 2))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
        .accessibilityIdentifier("rj-live-telemetry")
    }

    private var orderedUsers: [TelemetryUser] {
        (data?.users ?? []).sorted { !$0.me && $1.me }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.62, 0.42], [1, 0.5], [0, 1], [0.5, 1], [1, 1]
            ], colors: [LovePalette.plum, LovePalette.violet, LovePalette.blue,
                        LovePalette.pink, LovePalette.violet.opacity(0.9), LovePalette.cyan,
                        LovePalette.blush, LovePalette.pink, LovePalette.violet])
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LovePulseDot(color: .green)
                    Text("LIVE").font(.caption2.weight(.heavy)).tracking(1.6)
                    Spacer()
                    if let data {
                        Label(data.apnsEnabled ? "APNs aktiv" : "APNs aus", systemImage: data.apnsEnabled ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                Text("Wann welches iPhone zuletzt gefunkt hat.")
                    .font(.loveDisplay(26, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(data.map { "Server \($0.serverVersion) · aktualisiert sich jede Sekunde" } ?? "Verbinde mit dem Server …")
                    .font(.footnote.weight(.medium)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(minHeight: 176)
        .clipShape(RoundedRectangle(cornerRadius: LoveMetrics.cardRadius + 4, style: .continuous))
        .shadow(color: LovePalette.plum.opacity(0.25), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text("Telemetrie wird geladen …").font(.subheadline).foregroundStyle(.secondary)
        }.loveCard()
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(.orange)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Ping

    private var pingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                LoveIcon(symbol: "dot.radiowaves.left.and.right", tint: LovePalette.pink, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live-Abfrage").font(.headline)
                    Text("Weckt das andere iPhone per stillem Push und holt Akku und Standort sofort.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Task { await ping() }
            } label: {
                HStack {
                    if pinging { ProgressView().controlSize(.small).tint(.white) }
                    Text(pinging ? "Sende …" : watchedPing != nil ? "Warte auf Antwort …" : "Jetzt live abfragen")
                }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(pinging || app.partner == nil)
            .sensoryFeedback(.impact(weight: .medium), trigger: pinging)
            if let pingMessage {
                Text(pingMessage).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let pings = data?.pings, !pings.isEmpty {
                VStack(spacing: 0) {
                    ForEach(pings.prefix(4)) { ping in
                        PingRow(ping: ping, outgoing: ping.requesterID == app.me?.id)
                        if ping.id != pings.prefix(4).last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(LoveSurface.inset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .loveCard()
        .animation(LoveMotion.gentle, value: pingMessage)
    }

    // MARK: Charts

    private struct BatteryPoint: Identifiable { let id: String; let person: String; let date: Date; let level: Int; let located: Bool }
    private struct SourceBar: Identifiable { let id: String; let person: String; let source: String; let count: Int }

    private func batteryChart(_ users: [TelemetryUser]) -> some View {
        let points = users.flatMap { user in
            user.reports.enumerated().compactMap { index, report -> BatteryPoint? in
                guard let date = report.createdAt.rjDate, let level = report.batteryLevel else { return nil }
                return BatteryPoint(id: "\(user.id)-\(index)", person: user.displayName, date: date, level: level, located: report.hasLocation)
            }
        }
        return LoveGroup("Akkuverlauf · 24 Stunden", footer: "Jeder Punkt ist eine tatsächlich am Server angekommene Meldung, größere Punkte enthielten einen Standort. Lücken bedeuten, dass iOS die App in dieser Zeit nicht geweckt hat.") {
            Chart(points) { point in
                LineMark(x: .value("Zeit", point.date), y: .value("Akku", point.level))
                    .foregroundStyle(by: .value("Person", point.person))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Zeit", point.date), y: .value("Akku", point.level))
                    .foregroundStyle(by: .value("Person", point.person))
                    .symbolSize(point.located ? 26 : 12)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v) %") } }
                }
            }
            .chartForegroundStyleScale(range: [LovePalette.pink, LovePalette.blue])
            .frame(height: 190)
        }
    }

    private func sourceChart(_ users: [TelemetryUser]) -> some View {
        let rows = users.flatMap { user in
            user.stats.bySource.map { SourceBar(id: user.id + "|" + $0.key, person: user.displayName, source: $0.key, count: $0.value) }
        }.sorted { $0.count > $1.count }
        let shown = Array(rows.prefix(16))
        return LoveGroup("Wodurch die Daten kamen", footer: "Weckquellen der letzten 24 Stunden je iPhone.") {
            Chart(shown) { row in
                BarMark(x: .value("Meldungen", row.count), y: .value("Quelle", row.source))
                    .foregroundStyle(by: .value("Person", row.person))
                    .cornerRadius(5)
            }
            .chartForegroundStyleScale(range: [LovePalette.pink, LovePalette.blue])
            .frame(height: CGFloat(max(110, Set(shown.map(\.source)).count * 34)))
        }
    }

    // MARK: Local engine

    private var engineCard: some View {
        LoveGroup("Dieses iPhone · Hintergrund-Engine", footer: "Alles, was iOS einer installierten App erlaubt, ist hier aktiv. Je mehr Häkchen, desto näher an live.") {
            Group {
            EngineRow(title: "Standort „Immer“", detail: "Weckt die App bei Ortswechseln, auch nach dem Wegwischen.", ok: location.authorizationStatus == .authorizedAlways)
            LoveRowDivider()
            EngineRow(title: "Genauer Standort", detail: "Für 150-m-Geofence und Karte.", ok: location.accuracyAuthorization == .fullAccuracy)
            LoveRowDivider()
            EngineRow(title: "Standort teilen im Hintergrund", detail: "Hält die App aktiv: Akku wird sekundengenau gemeldet.", ok: location.sharingEnabled && location.backgroundSharingEnabled)
            LoveRowDivider()
            EngineRow(title: "Abfahrts-Geofence", detail: DepartureFence.shared.armed ? "Scharf · 150 m um die letzte Position" : "Wird beim nächsten Standort gesetzt", ok: DepartureFence.shared.armed)
            LoveRowDivider()
            EngineRow(title: "Hintergrundaktualisierung", detail: "BGAppRefresh und Wartungsfenster.", ok: DeviceTelemetry.backgroundRefresh == "available")
            LoveRowDivider()
            EngineRow(title: "Push registriert", detail: data?.apnsEnabled == true ? "Server kann still wecken" : "Server ohne APNs-Schlüssel: Live-Abfrage wartet auf das nächste iOS-Fenster", ok: UIApplication.shared.isRegisteredForRemoteNotifications && data?.apnsEnabled == true)
            LoveRowDivider()
            EngineRow(title: "Health-Hintergrundlieferung", detail: "Neue Schritte wecken die App (höchstens stündlich).", ok: HealthBackgroundDelivery.shared.active)
            }
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                LoveRowDivider()
                EngineRow(title: "Stromsparmodus aktiv", detail: "iOS pausiert Hintergrundaktualisierung und drosselt Standort.", ok: false)
            }
            LoveRowDivider()
            Toggle(isOn: $engine.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live-Modus").font(.body.weight(.semibold))
                    Text(engine.running ? "Läuft seit \(engine.startedAt?.formatted(date: .omitted, time: .shortened) ?? "–")" : "Startet, sobald du die App verlässt")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Picker("Herzschlag", selection: $engine.interval) {
                ForEach(LiveBackgroundEngine.intervals, id: \.self) { seconds in
                    Text(seconds < 60 ? "\(Int(seconds)) s" : "\(Int(seconds / 60)) min").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!engine.enabled)
            if location.authorizationStatus != .authorizedAlways || !location.backgroundSharingEnabled {
                HStack {
                    if !location.backgroundSharingEnabled && location.sharingEnabled {
                        Button("Hintergrund aktivieren") { location.backgroundSharingEnabled = true }
                            .buttonStyle(.bordered)
                    }
                    Button("iOS-Einstellungen") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var journalCard: some View {
        let entries = Array(journal.entries.prefix(showAllWakes ? 80 : 8))
        return LoveGroup("Weckprotokoll", footer: "\(journal.wakesLast24h) Weckungen in 24 h · \(journal.processLaunches) Prozessstarts insgesamt. Nur auf diesem iPhone gespeichert.") {
            if entries.isEmpty {
                Text("Noch keine Hintergrundweckung. Verlasse die App, und iOS meldet sich hier.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                WakeRow(entry: entry)
                if entry.id != entries.last?.id { LoveRowDivider() }
            }
            if journal.entries.count > 8 {
                Button(showAllWakes ? "Weniger anzeigen" : "Alle \(min(journal.entries.count, 80)) anzeigen") {
                    withAnimation(LoveMotion.gentle) { showAllWakes.toggle() }
                }.font(.subheadline.weight(.semibold))
            }
        }
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Was iOS erlaubt – ehrlich", systemImage: "info.circle.fill").font(.headline)
            Text("Keine iPhone-App kann ununterbrochen laufen. Live wird es, solange die Hintergrund-Standortfreigabe die App wach hält: dann gehen Akkuänderungen in Sekunden raus. Wurde die App weggewischt, weckt iOS sie trotzdem bei Ortswechseln, beim Verlassen des 150-m-Geofence und bei Besuchen. Stille Pushes und Hintergrundaktualisierung teilt iOS nach Akku, Nutzung und Stromsparmodus zu; nach einem weggewischten Zustand liefert iOS sie bis zum nächsten Öffnen nicht.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.loveCard()
    }

    // MARK: Actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let next = try await app.api.presenceTelemetry()
            withAnimation(LoveMotion.gentle) { data = next; error = nil }
            if let watchedPing, let ping = next.pings.first(where: { $0.id == watchedPing }) {
                if ping.status == "answered" {
                    pingMessage = "Antwort da " + (ping.answerLatencyMs.map { "nach \(String(format: "%.1f", Double($0) / 1000)) s." } ?? ".")
                    self.watchedPing = nil
                } else if let created = ping.createdAt.rjDate, Date.now.timeIntervalSince(created) > 60 {
                    pingMessage = ping.reason + " Noch keine Antwort; iOS hat das iPhone (noch) nicht geweckt."
                    self.watchedPing = nil
                } else {
                    pingMessage = ping.reason
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func ping() async {
        pinging = true
        defer { pinging = false }
        do {
            let result = try await app.api.pingPartnerPresence()
            pingMessage = result.reason
            watchedPing = result.status == "queued" ? result.id : nil
            await load()
        } catch {
            pingMessage = error.localizedDescription
        }
    }
}

// MARK: - Device card

private struct DeviceTelemetryCard: View {
    let user: TelemetryUser
    let now: Date
    private var presence: PresencePayload? { user.presence }
    private var telemetry: [String: TelemetryValue] { presence?.telemetry ?? [:] }
    private var tint: Color { user.me ? LovePalette.blue : LovePalette.pink }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .center, spacing: 18) {
                BatteryRing(level: presence?.batteryLevel, state: presence?.batteryState, lowPower: presence?.lowPowerMode == true, tint: tint)
                VStack(alignment: .leading, spacing: 9) {
                    FreshnessRow(title: "Akku übertragen", date: (presence?.batteryReportedAt ?? presence?.reportedAt)?.rjDate, now: now, symbol: "battery.100percent.bolt")
                    FreshnessRow(title: "Standort übertragen", date: presence?.locationReportedAt?.rjDate, now: now, symbol: "location.fill",
                                 missing: presence?.locationSharing == false ? "nicht freigegeben" : "noch nie")
                    FreshnessRow(title: "Health übertragen", date: presence?.healthReportedAt?.rjDate ?? presence?.healthUpdatedAt?.rjDate, now: now, symbol: "heart.fill")
                    FreshnessRow(title: "Letzte Meldung", date: presence?.updatedAt?.rjDate, now: now, symbol: "antenna.radiowaves.left.and.right")
                }
            }
            if let source = presence?.reportSource {
                Label("Zuletzt über: \(source)", systemImage: "arrow.down.forward.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(tint.opacity(0.1), in: Capsule())
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(nerdFacts, id: \.title) { fact in NerdTile(fact: fact, tint: tint) }
            }
        }
        .loveCard()
    }

    private var header: some View {
        HStack(spacing: 12) {
            PartnerAvatar(name: user.displayName, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.me ? "\(user.displayName) · Du" : user.displayName).font(.title3.bold())
                Text(stateText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle().fill(stateColor).frame(width: 12, height: 12)
                .overlay { Circle().stroke(stateColor.opacity(0.35), lineWidth: 6) }
                .accessibilityHidden(true)
        }
    }

    private var age: TimeInterval? { presence?.updatedAt?.rjDate.map { now.timeIntervalSince($0) } }
    private var stateText: String {
        guard let age else { return "Noch keine Daten" }
        if presence?.appState == "foreground", age < 120 { return "Gerade in der App" }
        if age < 300 { return "Im Hintergrund aktiv" }
        if age < 3600 { return "Zuletzt vor \(Int(age / 60)) min" }
        return "Ruht · iOS hat nicht geweckt"
    }
    private var stateColor: Color {
        guard let age else { return .gray }
        if presence?.appState == "foreground", age < 120 { return .green }
        if age < 300 { return LovePalette.cyan }
        if age < 3600 { return .orange }
        return .gray
    }

    struct Fact { let title: String; let value: String; let symbol: String }

    private var nerdFacts: [Fact] {
        var facts: [Fact] = []
        func add(_ title: String, _ value: String?, _ symbol: String) { if let value, !value.isEmpty { facts.append(Fact(title: title, value: value, symbol: symbol)) } }
        func text(_ key: String) -> String? { telemetry[key]?.text }
        add("Netz", networkText, presence?.networkType == "wifi" ? "wifi" : "antenna.radiowaves.left.and.right")
        add("Temperatur", text("thermal_state").map(Self.thermalName), "thermometer.medium")
        add("Stromsparen", presence?.lowPowerMode.map { $0 ? "an" : "aus" }, "leaf.fill")
        add("Weckquelle", text("wake_source"), "alarm.fill")
        add("Upload-Latenz", telemetry["last_upload_latency_ms"]?.number.map { "\(Int($0)) ms" }, "speedometer")
        add("Meldungen 24 h", "\(user.stats.reports24h)", "waveform.path.ecg")
        add("Median-Abstand", user.stats.medianGapS.map(Self.duration), "metronome.fill")
        add("Längste Lücke", user.stats.longestGapS.map(Self.duration), "hourglass")
        add("Meldungen gesamt", presence?.reportCount.map { "\($0)" }, "number")
        add("Weckungen 24 h", text("wakes_24h"), "bell.badge.fill")
        add("Prozessstarts", text("process_launches"), "power")
        add("Standortrecht", text("location_authorization").map(Self.authorizationName), "location.circle.fill")
        add("Genau", telemetry["precise_location"]?.bool.map { $0 ? "ja" : "ungefähr" }, "scope")
        if let accuracy = presence?.horizontalAccuracy { add("Genauigkeit", "± \(Int(accuracy)) m", "circle.dashed") }
        if let speed = presence?.speed, speed >= 0 { add("Tempo", String(format: "%.0f km/h", speed * 3.6), "gauge.with.needle.fill") }
        if let altitude = presence?.altitude { add("Höhe", "\(Int(altitude)) m", "mountain.2.fill") }
        add("Fix-Alter", telemetry["location_age_s"]?.number.map(Self.duration), "clock.arrow.circlepath")
        add("Geofence", telemetry["geofence_armed"]?.bool.map { $0 ? "scharf" : "aus" }, "mappin.and.ellipse")
        add("Live-Modus", telemetry["live_mode"]?.bool.map { $0 ? "läuft" : "aus" }, "bolt.heart.fill")
        add("Health-Wecker", telemetry["health_background"]?.bool.map { $0 ? "aktiv" : "aus" }, "heart.text.square.fill")
        add("Hintergrund-Refresh", text("background_refresh").map { $0 == "available" ? "an" : $0 == "denied" ? "aus" : $0 }, "arrow.triangle.2.circlepath")
        add("Push", telemetry["push_registered"]?.bool.map { $0 ? "registriert" : "fehlt" } ?? (user.pushDevices > 0 ? "registriert" : nil), "app.badge.fill")
        add("iOS", text("os_version"), "apple.logo")
        add("Modell", text("device_model"), "iphone")
        add("App", [presence?.appVersion, text("app_build").map { "(\($0))" }].compactMap { $0 }.joined(separator: " "), "app.fill")
        add("Uptime", telemetry["uptime_s"]?.number.map(Self.duration), "timer")
        add("Speicher frei", telemetry["storage_free_gb"]?.number.map { String(format: "%.1f GB", $0) }, "internaldrive.fill")
        add("RAM frei (App)", telemetry["memory_mb"]?.number.map { "\(Int($0)) MB" }, "memorychip.fill")
        add("Audio", text("audio_route"), "speaker.wave.2.fill")
        add("Zeitzone", text("timezone"), "globe.europe.africa.fill")
        return facts
    }

    private var networkText: String? {
        guard let type = presence?.networkType else { return nil }
        var value = ["wifi": "WLAN", "cellular": "Mobilfunk", "ethernet": "Kabel", "offline": "offline"][type] ?? type
        if presence?.networkType == "wifi", let name = presence?.wifiName { value += " · " + name }
        if telemetry["network_constrained"]?.bool == true { value += " · Datensparen" }
        else if telemetry["network_expensive"]?.bool == true { value += " · Hotspot" }
        return value
    }

    static func thermalName(_ value: String) -> String {
        ["nominal": "normal", "fair": "leicht warm", "serious": "warm", "critical": "kritisch"][value] ?? value
    }
    static func authorizationName(_ value: String) -> String {
        ["always": "Immer", "when_in_use": "Beim Verwenden", "denied": "Abgelehnt", "restricted": "Eingeschränkt", "not_determined": "Nicht gefragt"][value] ?? value
    }
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        if s < 86_400 { return "\(s / 3600) h \((s % 3600) / 60) min" }
        return "\(s / 86_400) d \((s % 86_400) / 3600) h"
    }
}

/// "vor 42 s" with a color that ages: green, then orange, then grey.
private struct FreshnessRow: View {
    let title: String
    let date: Date?
    let now: Date
    let symbol: String
    var missing = "noch nie"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var age: TimeInterval? { date.map { max(0, now.timeIntervalSince($0)) } }
    private var value: String {
        guard let age, let date else { return missing }
        if age < 60 { return "vor \(Int(age)) s" }
        if age < 3600 { return "vor \(Int(age / 60)) min \(Int(age) % 60) s" }
        if age < 86_400 { return "vor \(Int(age / 3600)) h \(Int(age / 60) % 60) min" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private var color: Color {
        guard let age else { return .secondary }
        if age < 300 { return .green }
        if age < 1800 { return .orange }
        return .secondary
    }
}

/// Circular battery gauge with charging and Low Power states.
struct BatteryRing: View {
    let level: Int?
    let state: String?
    var lowPower = false
    var tint: Color = LovePalette.pink
    var size: CGFloat = 92

    private var fraction: Double { Double(level ?? 0) / 100 }
    private var charging: Bool { state == "charging" || state == "full" }
    private var color: Color {
        guard let level else { return .gray }
        if lowPower { return .yellow }
        if charging { return .green }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return tint
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 10)
            Circle().trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: fraction)
            VStack(spacing: 0) {
                if charging {
                    Image(systemName: "bolt.fill").font(.caption.weight(.bold)).foregroundStyle(.green)
                        .symbolEffect(.pulse, options: .repeating, isActive: state == "charging")
                }
                Text(level.map { "\($0)" } ?? "–")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(level ?? 0)))
                Text("%").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "Akku \($0) Prozent" + (charging ? ", lädt" : "") } ?? "Akku unbekannt")
    }
}

private struct NerdTile: View {
    let fact: DeviceTelemetryCard.Fact
    let tint: Color
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: fact.symbol).font(.footnote.weight(.semibold)).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(fact.value).font(.footnote.weight(.semibold).monospacedDigit()).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoveSurface.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct EngineRow: View {
    let title: String
    let detail: String
    let ok: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3).foregroundStyle(ok ? .green : .orange).symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WakeRow: View {
    let entry: WakeEntry
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.success ? .green : .red).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source).font(.subheadline.weight(.medium))
                Text([entry.date.formatted(date: .abbreviated, time: .standard),
                      entry.battery.map { "\($0) %" }, entry.latencyMs.map { "\($0) ms" }, entry.detail]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PingRow: View {
    let ping: PresencePing
    let outgoing: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(outgoing ? "Abfrage gesendet" : "Abfrage erhalten").font(.footnote.weight(.semibold))
                Text(ping.createdAt.rjDate?.formatted(date: .omitted, time: .standard) ?? "").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 9)
    }
    private var label: String {
        switch ping.status {
        case "answered": return ping.answerLatencyMs.map { String(format: "%.1f s", Double($0) / 1000) } ?? "beantwortet"
        case "sent": return "zugestellt"
        case "queued": return "unterwegs"
        case "failed": return "fehlgeschlagen"
        default: return "ohne APNs"
        }
    }
    private var symbol: String {
        switch ping.status {
        case "answered": return "checkmark.seal.fill"
        case "failed", "unavailable": return "exclamationmark.triangle.fill"
        default: return "paperplane.fill"
        }
    }
    private var color: Color {
        switch ping.status {
        case "answered": return .green
        case "failed", "unavailable": return .orange
        default: return LovePalette.blue
        }
    }
}
