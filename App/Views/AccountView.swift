import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var current = ""
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Dein Zugang") {
                TextField("Benutzername", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Aktuelles Passwort", text: $current).textContentType(.password)
                SecureField("Neues Passwort", text: $password).textContentType(.newPassword)
                SecureField("Neues Passwort wiederholen", text: $repeatPassword).textContentType(.newPassword)
            }
            Section {
                Text("Mindestens zehn Zeichen. Nach dem Speichern werden alle bisherigen Sitzungen deines Kontos beendet. Melde dich anschließend mit dem neuen Zugang an. Das Konto deines Lieblingsmenschen bleibt unabhängig.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button(saving ? "Wird gespeichert …" : "Zugang ändern") {
                    saving = true
                    Task {
                        do {
                            try await appState.api.changeCredentials(currentPassword: current, username: username, password: password)
                            await appState.logout()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.disabled(saving || current.isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.count < 10 || password != repeatPassword)
            }
        }.navigationTitle("Mein Zugang")
        .onAppear { username = appState.profile?.username ?? "" }
    }
}

struct CapabilitiesView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var health = HealthService.shared
    @ObservedObject private var notifications = NotificationCoordinator.shared
    private var appGroup: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedStore.suiteName) != nil }
    var body: some View {
        List {
            Section("Auf diesem iPhone") {
                row("Gemeinsame Widget-Daten", appGroup ? "App Group erreichbar" : "App Group nicht erreichbar – Signaturprofil prüfen", "square.stack.3d.up", appGroup)
                row("Push-Registrierung", notifications.deviceTokenAvailable ? "APNs-Gerätetoken empfangen" : "Noch kein APNs-Gerätetoken", "bell.badge", notifications.deviceTokenAvailable)
                row("Push-Server", appState.features?.apnsEnabled == true ? "Auf dem Server aktiviert" : "APNs nicht konfiguriert", "server.rack", appState.features?.apnsEnabled == true)
                row("Apple Health", health.requested ? "Auswahl angefragt; Daten in Health verwalten" : "Noch nicht angefragt", "heart.text.square", health.requested)
                row("Präzise Nahbereichssuche", appState.nearby.supported ? "UWB-Hardware verfügbar" : "Auf diesem Gerät nicht verfügbar", "dot.radiowaves.left.and.right", appState.nearby.supported)
                row("Live-Aktivität", appState.liveActivity.isRunning ? "Aktiv" : "Bereit zum Start auf der Wir-Seite", "livephoto", appState.liveActivity.isRunning)
            }
            Section("Widget-Verbindung im Detail") {
                NavigationLink("App Group & Erweiterung prüfen"){WidgetDiagnosticsView()}
            }
            Section("Signieren mit ArcticSign / Feather") {
                Text("Signiere die Haupt-App und die eingebettete Widget-Extension zusammen. Behalte deren zusammengehörige Bundle-IDs und dieselbe App Group bei. HealthKit und eigene APNs brauchen passende Berechtigungen im Provisioningprofil. Ein Signaturdienst kann diese Apple-Berechtigungen nicht allein durch Hinzufügen von Text freischalten.")
                Text("Bark oder ntfy senden eure vollständigen Hinweise unabhängig von den eigenen RJ-APNs. Dafür installiert ihr zusätzlich die ntfy-App und abonniert den jeweils eigenen privaten Topic. Die RJ-Love-App selbst wird dadurch nicht dauerhaft im Hintergrund ausgeführt.")
                Text("Widgets werden nach iOS-Zeitplan aktualisiert. Live-Aktivitäten zeigen den letzten empfangenen Stand; eine veraltete Anzeige wird als solche markiert. Kritische Hinweise werden nicht angefordert.")
            }.font(.footnote)
        }.navigationTitle("Funktionen & Signatur")
    }
    private func row(_ title: String, _ detail: String, _ symbol: String, _ available: Bool) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
        } icon: { Image(systemName: symbol).foregroundStyle(available ? Color.green : Color.orange) }
    }
}

