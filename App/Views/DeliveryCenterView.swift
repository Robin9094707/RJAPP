import AlarmKit
import SwiftUI
import UIKit

struct DeliveryCenterView: View {
    @Environment(AppState.self) private var app
    @ObservedObject private var registration = PushRegistrationStatus.shared
    @State private var readiness: PushReadiness?
    @State private var deliveries: [CommandDelivery] = []
    @State private var error: String?
    @State private var message: String?
    @State private var loading = false
    private let signing = SigningProfile.current
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 13) {
                    LoveEyebrow(text: "Verbunden, auch wenn die App ruht")
                    Text("Kommt mein Weckruf an?").font(.system(size: 31, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rj-delivery-title")
                    Text("Hier siehst du getrennt, was das Signierprofil erlaubt, was Apple annimmt und was das andere iPhone tatsächlich eingeplant hat.").font(.subheadline).foregroundStyle(.secondary)
                }.loveCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("1 · Dieses iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right").font(.headline)
                    detail("Profil", signing.profileDescription)
                    detail("Bundle-ID", signing.bundleID)
                    detail("Signing-Team", signing.teamID ?? "Nicht auslesbar")
                    detail("APNs-Umgebung", signing.environment ?? "Im Profil nicht gefunden")
                    detail("APNs-Gerätetoken", app.notifications.deviceTokenAvailable ? "Von iOS empfangen" : "Noch nicht empfangen")
                    if let expires = signing.expires { detail("Profil gültig bis", expires.formatted(date: .abbreviated, time: .omitted)) }
                    if let failure = registration.error { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Button("Push-Registrierung erneut anfragen", systemImage: "arrow.clockwise") {
                        Task { _ = await app.notifications.requestAuthorization(); await load() }
                    }.buttonStyle(.bordered)
                    Text("ArcticSign Prime Plus kann Distribution und Developer/JIT anbieten. Prüfe das tatsächlich installierte Profil. Die Bundle-ID von Zello zu übernehmen erzeugt keine Zello-Teamrechte und keinen passenden APNs-Server-Schlüssel.").font(.caption).foregroundStyle(.secondary)
                }.font(.footnote).loveCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("2 · Python-Server & Push", systemImage: "server.rack").font(.headline)
                    if let readiness {
                        Label(readiness.ready ? "Lokale Voraussetzungen vorhanden" : "Einrichtung noch unvollständig", systemImage: readiness.ready ? "checkmark.circle.fill" : "wrench.adjustable.fill")
                        detail("Server-Topic", readiness.bundleID)
                        detail("Registrierte Geräte dieses Kontos", String(readiness.registeredDevices))
                        if !readiness.issues.isEmpty {
                            DisclosureGroup("Technische Details anzeigen") { ForEach(readiness.issues,id: \.self) { Text($0).foregroundStyle(.secondary) } }
                        }
                        Text("Ein grüner Vorabcheck bestätigt weder den Empfang noch eine Hintergrundausführung. Dafür Push-Test auslösen und unten die Rückmeldungen ansehen.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Push-Test an dieses iPhone senden", systemImage: "bell.badge.fill") {
                        Task { do { try await app.api.testPush(); message = "Test angefordert. Warte auf die sichtbare Mitteilung und prüfe die Rückmeldung."; await load() } catch { self.error = error.localizedDescription } }
                    }.buttonStyle(.borderedProminent).disabled(loading || readiness?.ready != true)
                    if let status = readiness?.automaticSetup { Text(status).font(.footnote) }
                    Text("Der Server prüft beim Start und regelmäßig automatisch den Ordner „push“. Lege dort deinen Apple-APNs-Schlüssel ab. Eine passende Datei wird ohne Konsolenbefehl übernommen. Apple muss diesen Schlüssel zuvor ausgestellt haben.").font(.caption).foregroundStyle(.secondary)
                    Button("Automatische Prüfung jetzt wiederholen") { Task { do { try await app.api.automaticPushSetup(); await load() } catch { self.error = error.localizedDescription } } }.buttonStyle(.bordered)
                    if let message { Text(message).foregroundStyle(LovePalette.cyan) }
                }.font(.footnote).loveCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("3 · Hintergrund & AlarmKit", systemImage: "alarm.fill").font(.headline)
                    detail("Letzter Hintergrundaufruf", UserDefaults.standard.string(forKey: "rjlove.last-background-at")?.rjDate?.formatted(date: .abbreviated, time: .shortened) ?? "Noch keiner protokolliert")
                    detail("Auslöser", UserDefaults.standard.string(forKey: "rjlove.last-background-source") ?? "–")
                    Text(UserDefaults.standard.string(forKey: "rjlove.last-background-result") ?? "Ein Push kann einen kurzen Hintergrundabruf ermöglichen. Noch kein Ergebnis vorhanden.")
                    detail("iOS-Hintergrundaktualisierung", backgroundStatus)
                    Button("AlarmKit-Berechtigung prüfen") { Task { _ = await app.alarms.requestAuthorization(); await load() } }.buttonStyle(.bordered)
                    Text("Bereits auf dem iPhone geplante Alarme laufen unabhängig von der geöffneten App. Ein neuer Fernweckruf braucht vorherigen Empfang. iOS kann Hintergrundpushes verzögern oder nach manuellem Beenden unterdrücken. In der erweiterten Weckmitteilung gibt es zusätzlich „Weckruf jetzt einplanen“ ohne Öffnen der Oberfläche. Plane wichtige Wecker möglichst im Voraus.").foregroundStyle(.secondary)
                }.font(.footnote).loveCard()
                if !deliveries.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Meine gesendeten Weckrufe", systemImage: "paperplane.fill").font(.headline)
                        ForEach(deliveries) { delivery in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(delivery.message).font(.subheadline.bold())
                                Label(delivery.title, systemImage: delivery.status == "scheduled" ? "checkmark.circle.fill" : "clock").foregroundStyle(delivery.status == "scheduled" ? LovePalette.cyan : LovePalette.violet)
                                if let date = delivery.dueAt.rjDate { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                                if let reason = delivery.reason { Text(reason).foregroundStyle(.secondary) }
                            }.font(.caption)
                            Divider()
                        }
                    }.loveCard()
                }
                if let readiness, !readiness.attempts.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Letzte Push-Rückmeldungen").font(.headline)
                        ForEach(readiness.attempts) { attempt in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(attempt.kind) · \(attempt.status)").font(.caption.bold())
                                Text(attempt.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.loveCard()
                }
                if let error { Label(error, systemImage: "exclamationmark.bubble").font(.footnote).foregroundStyle(.orange).loveCard() }
                Button("Status aktualisieren", systemImage: "arrow.clockwise") { Task { await load() } }.buttonStyle(.bordered).disabled(loading)
            }.padding(20)
        }.background(LoveBackground()).navigationTitle("Push & Wecker").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    private func detail(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(name).font(.caption.bold()).foregroundStyle(.secondary); Text(value).font(.footnote).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
    private var backgroundStatus: String {
        switch UIApplication.shared.backgroundRefreshStatus { case .available: "Verfügbar · iOS bestimmt den Zeitpunkt"; case .denied: "In den iPhone-Einstellungen ausgeschaltet"; case .restricted: "Durch iOS eingeschränkt"; @unknown default: "Unbekannt" }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return }
        #endif
        do { readiness = try await app.api.pushReadiness(); deliveries = try await app.api.commandDeliveries(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
