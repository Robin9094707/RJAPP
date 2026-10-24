import SwiftUI
import UIKit

struct DeliveryCenterView: View {
    @Environment(AppState.self) private var app
    @State private var status: ExternalPushStatus?
    @State private var settings = ExternalPushSettings()
    @State private var deliveries: [CommandDelivery] = []
    @State private var loading = false
    @State private var error: String?
    @State private var message: String?
    private var dirty: Bool { status.map { $0.settings != settings } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                if let status {
                    recipientStatus(status)
                    providerSettings(status)
                    quietSettings
                    integrations(status)
                    activeAlarms(status)
                    deliveryHistory(status)
                } else if loading { ProgressView("Push-Einstellungen laden …") }
                if let error { Label(error, systemImage: "exclamationmark.bubble.fill").font(.footnote).foregroundStyle(.orange).loveCard() }
                if let message { Text(message).font(.footnote).foregroundStyle(LovePalette.cyan).loveCard() }
                Button("Status aktualisieren", systemImage: "arrow.clockwise") { Task { await load() } }
                    .buttonStyle(.bordered).disabled(loading || dirty)
            }.padding(20)
        }
        .background(LoveBackground()).navigationTitle("Push & Wecker").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { Task { await save() } }.disabled(loading || !dirty)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            LoveEyebrow(text: "Auch wenn RJ Love geschlossen ist")
            Text("Ein Zeichen von dir.").font(.system(size: 31, weight: .medium, design: .serif))
                .accessibilityIdentifier("rj-delivery-title")
            Text("Bark bringt eure Nachrichten, Bilder und Weckrufe aufs iPhone. ntfy bleibt als Alternative verfügbar. Jeder wählt seinen eigenen Empfangsweg.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.loveCard()
    }

    private func recipientStatus(_ status: ExternalPushStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(status.quiet.active ? status.quiet.label : "Du bist erreichbar", systemImage: status.quiet.active ? "moon.zzz.fill" : "bell.badge.fill").font(.headline)
            if let until = status.quiet.until?.rjDate { Text("Ruhe bis \(until.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            ForEach(status.partners) { partner in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(partner.displayName): \(partner.quiet.active ? partner.quiet.label : "Erreichbar")")
                    if let until = partner.quiet.until?.rjDate { Text("Bis \(until.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
                }.font(.footnote)
            }
            Label(status.ready ? "Empfang eingerichtet" : "Einrichtung noch offen", systemImage: status.ready ? "checkmark.circle.fill" : "wrench.adjustable.fill")
                .font(.footnote).foregroundStyle(status.ready ? .green : .orange)
            ForEach(status.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }.loveCard()
    }

    private func providerSettings(_ status: ExternalPushStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dein Empfangsweg").font(.headline)
            Picker("Push-App", selection: $settings.provider) {
                Text("Bark").tag("bark"); Text("ntfy").tag("ntfy")
            }.pickerStyle(.segmented).accessibilityIdentifier("push-provider")
            if settings.provider == "bark" {
                Link("Bark im App Store öffnen", destination: URL(string: "https://apps.apple.com/app/id1403753865")!)
                Text("1. In Bark einen eigenen Server hinzufügen und diese Adresse einfügen:").font(.footnote)
                copyRow("Dein Bark-Server", status.barkServerURL)
                Text("2. In Bark den Geräteschlüssel oder die Test-URL kopieren und hier einfügen:").font(.footnote)
                TextField("Bark-Geräteschlüssel / Test-URL", text: $settings.barkDeviceKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("bark-device-key")
                Text("3. Speichern. In Bark und in den iOS-Einstellungen Mitteilungen und kritische Hinweise erlauben.").font(.footnote)
                Toggle("Kritische Weckrufe erlauben", isOn: $settings.allowCritical)
                TextField("Bark-Sound (z. B. alarm)", text: $settings.sound).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                Stepper("Wecklautstärke: \(settings.volume)/10", value: $settings.volume, in: 0...10)
                Text("Eigene Töne zuerst in Bark importieren: CAF, höchstens 30 Sekunden. Hier den Namen eintragen.").font(.caption).foregroundStyle(.secondary)
                Toggle("Bei Bark-Sendefehler über ntfy versuchen", isOn: $settings.fallbackNtfy)
                Text("Der Ersatzversand erfolgt nur bei einem erkannten Sendefehler. Eine von Apple angenommene Nachricht bestätigt den Empfang noch nicht.").font(.caption).foregroundStyle(.secondary)
            }
            if settings.provider == "ntfy" || settings.fallbackNtfy { ntfySettings }
            Button("Einstellungen speichern", systemImage: "checkmark.circle.fill") { Task { await save() } }
                .buttonStyle(.borderedProminent).disabled(loading || !dirty)
            Button("Testnachricht an mich", systemImage: "bell.badge.fill") {
                Task {
                    do { try await app.api.testExternalPush(); message = "Test angefordert. Prüfe die gewählte Push-App."; await refreshStatus() }
                    catch { self.error = error.localizedDescription }
                }
            }.buttonStyle(.bordered).disabled(loading || dirty || !status.ready)
        }.font(.subheadline).loveCard()
    }

    private var ntfySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ntfy einrichten").font(.headline)
            TextField("Server", text: $settings.ntfyServerURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder)
            TextField("Privates Topic", text: $settings.ntfyTopic).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("Zugriffstoken (optional)", text: $settings.ntfyAccessToken).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            copyRow("Server kopieren", settings.ntfyServerURL)
            copyRow("Topic kopieren", settings.ntfyTopic)
            if !settings.ntfyAccessToken.isEmpty { Button("Zugriffstoken kopieren") { copy(settings.ntfyAccessToken) } }
            Text("In der ntfy-App diesen Server und dieses Topic abonnieren. Vollständige Texte werden als normale Mitteilungen versendet. Bei eigenem ntfy-Server hängt die schnelle iOS-Zustellung von dessen APNs-/Upstream-Konfiguration ab.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var quietSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Deine Ruhezeiten", systemImage: "moon.zzz.fill").font(.headline)
            Text("Während deiner Ruhezeit gehen keine kritischen Hinweise oder Weckrufe raus. Laufende Wiederholungen enden. Normale Bark-Nachrichten kommen leise. Der manuelle Nicht-stören-Status sperrt zusätzlich normale Hinweise.").font(.footnote).foregroundStyle(.secondary)
            ForEach($settings.quietSchedules) { $schedule in
                QuietScheduleEditor(schedule: $schedule)
                Button("Ruheplan entfernen", role: .destructive) { settings.quietSchedules.removeAll { $0.id == schedule.id } }.font(.caption)
                Divider()
            }
            Button("Ruheplan hinzufügen", systemImage: "plus.circle") { settings.quietSchedules.append(QuietSchedule()) }
                .disabled(settings.quietSchedules.count >= 20)
            Text("Die Wochentage beziehen sich auf den Beginn der Ruhezeit. 20:00–06:00 läuft bis zum nächsten Morgen; gleiche Start- und Endzeit bedeutet 24 Stunden. Jeder verwaltet seine eigenen Grenzen.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
    }

    private func integrations(_ status: ExternalPushStatus) -> some View {
        DisclosureGroup("Dein Zugang für Automationen") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diese private URL kann Nachrichten oder geplante Weckrufe an dein Konto senden. Nur für eigene Automationen kopieren.").font(.caption)
                Button("Private Webhook-URL kopieren") { copy(status.integrationURL) }
                Text("POST mit JSON, z. B.:").font(.caption)
                Text(#"{"title":"Guten Morgen","body":"Zeit aufzustehen 💗","alarm":true,"repeat_until_ack":true}"#)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Optional: due_at als ISO-8601-Zeit mit Zeitzone. Auch diese Aufträge beachten deine Ruhezeiten. ChatGPT-Aufgaben müssen die URL tatsächlich aufrufen können; allein das Kopieren verbindet sie noch nicht.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 12)
        }.loveCard()
    }

    @ViewBuilder private func activeAlarms(_ status: ExternalPushStatus) -> some View {
        if !status.activeAlarms.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label("Deine Weckrufe", systemImage: "alarm.waves.left.and.right.fill").font(.headline)
                ForEach(status.activeAlarms) { alarm in
                    Text(alarm.message).font(.subheadline)
                    Text("Alle 45 Sekunden · endet nach Bestätigung, bei Ruhezeit oder spätestens nach einer Stunde.").font(.caption).foregroundStyle(.secondary)
                    Button("Bin wach · beenden", systemImage: "checkmark.circle.fill") {
                        Task { do { try await app.api.acknowledgePushAlarm(id: alarm.id); await refreshStatus() } catch { self.error = error.localizedDescription } }
                    }.buttonStyle(.borderedProminent)
                    Divider()
                }
            }.loveCard()
        }
    }

    private func deliveryHistory(_ status: ExternalPushStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup("Zustellung & gesendete Weckrufe") {
                ForEach(deliveries) { delivery in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(delivery.message).font(.subheadline.bold())
                        Text(delivery.title).font(.caption)
                        if let reason = delivery.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                ForEach(status.attempts) { attempt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(attempt.kind) · \(attempt.status)").font(.caption.bold())
                        Text(attempt.reason).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            Text("Bark klingelt pro Weckmitteilung bis zu 30 Sekunden. Server-Wiederholungen brauchen Internet. iOS-Berechtigungen, die Lautstärke und Apples Zustellung bestimmen, ob du es hörst.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button(title, systemImage: "doc.on.doc") { copy(value) }.font(.footnote)
        }
    }
    private func copy(_ value: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(300)])
        message = "Kopiert."
    }
    private func refreshStatus() async {
        do { status = try await app.api.externalPushStatus(); deliveries = try await app.api.commandDeliveries() }
        catch { self.error = error.localizedDescription }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { let value = try await app.api.externalPushStatus(); status = value; settings = value.settings; deliveries = try await app.api.commandDeliveries(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { let value = try await app.api.saveExternalPush(settings); status = value; settings = value.settings; error = nil; message = "Deine Push-Einstellungen sind gespeichert." }
        catch { self.error = error.localizedDescription }
    }
}

private struct QuietScheduleEditor: View {
    @Binding var schedule: QuietSchedule
    private let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Ruheplan aktiv", isOn: $schedule.enabled)
            TextField("Sichtbarer Schlafstatus", text: $schedule.label).textFieldStyle(.roundedBorder)
            DatePicker("Ab", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
            DatePicker("Bis", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<7) { day in
                        Button(weekdays[day]) {
                            if schedule.days.contains(day) { schedule.days.removeAll { $0 == day } }
                            else { schedule.days.append(day); schedule.days.sort() }
                        }.buttonStyle(.bordered).tint(schedule.days.contains(day) ? LovePalette.pink : .secondary)
                            .accessibilityLabel("\(weekdays[day]): \(schedule.days.contains(day) ? "aktiv" : "inaktiv")")
                    }
                }
            }
            TextField("Zeitzone", text: $schedule.timezone).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            if schedule.days.isEmpty { Text("Wähle mindestens einen Wochentag.").font(.caption).foregroundStyle(.orange) }
        }.font(.subheadline)
    }
    private func timeBinding(_ keyPath: WritableKeyPath<QuietSchedule, String>) -> Binding<Date> {
        Binding(get: {
            let parts = schedule[keyPath: keyPath].split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: parts.first ?? 22, minute: parts.last ?? 0)) ?? .now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule[keyPath: keyPath] = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }
}
