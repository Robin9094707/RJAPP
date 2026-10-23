import AlarmKit
import AVFoundation
import CoreLocation
import CoreMotion
import EventKit
import SwiftUI
import UserNotifications

struct ProfileSettingsDetailView: View {
    let section:ProfileSettingsSection
    @Environment(AppState.self) private var appState
    @ObservedObject private var location = LocationService.shared
    @ObservedObject private var health = HealthService.shared
    @ObservedObject private var notifications = NotificationCoordinator.shared
    @ObservedObject private var device = DeviceStatusService.shared
    @ObservedObject private var calendar = CalendarService.shared
    @AppStorage("rjlove.evening-auto") private var eveningAuto=true
    @State private var logoutConfirmation = false
    @State private var microphone = AVAudioApplication.shared.recordPermission

    var body:some View {
        @Bindable var state=appState
        Form {
            switch section {
            case .sharing:
            Section {
                Toggle("Live-Standort", isOn: $location.sharingEnabled)
                if location.sharingEnabled {
                    Toggle("Auch im Hintergrund teilen",isOn:$location.backgroundSharingEnabled)
                        .onChange(of:location.backgroundSharingEnabled) {_,value in if value {location.requestAlways()} }
                    Text("iOS zeigt die Standortnutzung an. Bewegung liefert Standort und Akku, solange iOS die App ausführt. Nach erzwungenem Beenden oder ohne Netz sind Updates nicht garantiert.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Aufnahmeort bei neuen Fotos",isOn:$location.photoLocationEnabled)
                Toggle("Health-Zusammenfassung", isOn: $health.sharingEnabled)
                Toggle("WLAN-Name, wenn verfügbar", isOn: $state.shareWiFiName)
            } header: {
                Text("Was ich teile")
            } footer: {
                Text("Wähle unter Health & Freigaben getrennt aus, ob du Aktivität, Schlaf oder Vitalwerte teilst.")
            }

            case .permissions:
            Section("Berechtigungen") {
                PermissionRow(title: "Mikrofon", status: microphone == .granted ? "Erlaubt" : microphone == .denied ? "Abgelehnt" : "Nicht gefragt", symbol: "mic.fill", tint: microphone == .granted ? .green : .orange, actionTitle: microphone == .granted ? nil : microphone == .denied ? "Einstellungen" : "Erlauben") {
                    if microphone == .denied { openSettings() }
                    else { Task { _ = await AVAudioApplication.requestRecordPermission(); microphone = AVAudioApplication.shared.recordPermission } }
                }
                PermissionRow(
                    title: "Standort beim Verwenden",
                    status: locationStatus,
                    symbol: "location.fill",
                    tint: location.authorizationStatus == .denied ? .red : LovePalette.cyan,
                    actionTitle: location.authorizationStatus == .notDetermined ? "Erlauben" : nil
                ) { location.requestWhenInUse() }

                PermissionRow(
                    title: "Standort immer",
                    status: location.authorizationStatus == .authorizedAlways ? "Erlaubt" : "Für Hintergrund & Orte nötig",
                    symbol: "location.circle.fill",
                    tint: location.authorizationStatus == .authorizedAlways ? .green : .orange,
                    actionTitle: location.authorizationStatus == .authorizedAlways ? nil : "Anfragen"
                ) { location.requestAlways() }

                if location.authorizationStatus == .authorizedAlways || location.authorizationStatus == .authorizedWhenInUse {
                    PermissionRow(
                        title: "Genauer Standort",
                        status: location.accuracyAuthorization == .fullAccuracy ? "Genau" : "Reduziert",
                        symbol: "scope",
                        tint: location.accuracyAuthorization == .fullAccuracy ? .green : .orange,
                        actionTitle: location.accuracyAuthorization == .fullAccuracy ? nil : "Temporär genau"
                    ) { location.requestTemporaryPrecision() }
                }

                PermissionRow(
                    title: "Mitteilungen & Push",
                    status: notificationStatus,
                    symbol: "bell.badge.fill",
                    tint: notifications.authorizationStatus == .authorized ? .green : .orange,
                    actionTitle: notifications.authorizationStatus == .authorized ? nil : "Erlauben"
                ) { Task { _ = await notifications.requestAuthorization() } }

                PermissionRow(
                    title: "AlarmKit",
                    status: alarmStatus,
                    symbol: "alarm.waves.left.and.right.fill",
                    tint: alarmStatus == "Erlaubt" ? .green : LovePalette.pink,
                    actionTitle: alarmStatus == "Erlaubt" ? nil : "Erlauben"
                ) { Task { _ = await appState.alarms.requestAuthorization() } }

                PermissionRow(
                    title: "Apple Health",
                    status: health.requested ? "Angefragt · in Health verwalten" : "Nicht eingerichtet",
                    symbol: "heart.text.square.fill",
                    tint: health.requested ? .green : LovePalette.pink,
                    actionTitle: "Freigaben prüfen"
                ) { Task { await health.requestAuthorization() } }

                PermissionRow(
                    title: "Bewegung & Fitness",
                    status: motionStatus,
                    symbol: "figure.walk.motion",
                    tint: device.motionAuthorization == .authorized ? .green : .orange,
                    actionTitle: device.motionAuthorization == .notDetermined ? "Anfragen" : nil
                ) { Task{await device.requestMotionAccess()} }

                PermissionRow(
                    title: "iOS-Kalender",
                    status: calendarStatus,
                    symbol: "calendar",
                    tint: calendar.authorizationStatus == .fullAccess ? .green : .orange,
                    actionTitle: calendar.authorizationStatus == .fullAccess ? nil : "Erlauben"
                ) { Task { _ = await calendar.requestAccess() } }
                Button("iPhone-Einstellungen öffnen", systemImage: "arrow.up.right.square") { openSettings() }
                Text("Abgelehnte Zugriffe kannst du dort ändern. Die Health-Leseauswahl verwaltest du in Apple Health. Eine Freigabe in der App ersetzt keine iOS-Erlaubnis.").font(.caption).foregroundStyle(.secondary)
            }

            case .privacy:
            Section("Privatsphäre") {
                Toggle("Süße Nachrichten beim Öffnen abspielen",isOn:Binding(get:{UserDefaults.standard.object(forKey:"rjlove.sweet-autoplay") == nil || UserDefaults.standard.bool(forKey:"rjlove.sweet-autoplay")},set:{UserDefaults.standard.set($0,forKey:"rjlove.sweet-autoplay")}))
                Toggle("Aufnahmeorte für neue Furze",isOn:Binding(get:{UserDefaults.standard.object(forKey:"rjlove.fart-locations") == nil || UserDefaults.standard.bool(forKey:"rjlove.fart-locations")},set:{UserDefaults.standard.set($0,forKey:"rjlove.fart-locations")}))
                Toggle("Fotowünsche mit direkter Kamera",isOn:Binding(get:{UserDefaults.standard.object(forKey:"rjlove.instant-enabled") == nil || UserDefaults.standard.bool(forKey:"rjlove.instant-enabled")},set:{UserDefaults.standard.set($0,forKey:"rjlove.instant-enabled")}))
                Text("Die Kamera ist sichtbar und vor der Aufnahme abbrechbar. Die Medienlautstärke wird nicht automatisch verändert.").font(.footnote).foregroundStyle(.secondary)
                Label("Passwort und Sitzungstoken liegen im iOS-Schlüsselbund. Bilder und gemeinsame Daten bleiben auf deinem eigenen Server.", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Unser Tagesrückblick") {
                Toggle("Abends beim Öffnen anzeigen",isOn:$eveningAuto)
                Text("Ab 19 Uhr erscheint der Tagesrückblick einmal pro Tag, wenn die App geöffnet ist. Ohne Hintergrundausführung wird kein automatischer Bericht erzeugt. Ihr könnt alle Tage jederzeit über die Wir-Seite öffnen.").font(.caption).foregroundStyle(.secondary)
                NavigationLink{SharedJournalView()}label:{Label("Unser Journal",systemImage:"sparkles.rectangle.stack")}
            }
            case .connection:
            Section("Verbindung") {
                LabeledContent("Server", value: appState.profile?.baseURL ?? "–")
                    .lineLimit(1)
                LabeledContent("Benutzer", value: appState.me?.displayName ?? appState.profile?.username ?? "–")
                LabeledContent("Transport") {
                    Label(appState.isUsingHTTPS ? "HTTPS" : "HTTP", systemImage: appState.isUsingHTTPS ? "lock.fill" : "exclamationmark.lock.open.fill")
                        .foregroundStyle(appState.isUsingHTTPS ? .green : .orange)
                }
                LabeledContent("Status", value: appState.connectionMessage)
                Button {
                    Task { await appState.syncNow() }
                } label: {
                    Label("Jetzt synchronisieren", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isSyncing)
            }

            Section("Systemgrenzen – ehrlich erklärt") {
                InfoLine(symbol: "iphone.radiowaves.left.and.right", text: "Push benötigt nach dem Signieren ein Profil mit Push-Entitlement und konfigurierte APNs-Schlüssel auf dem Server. Ohne APNs synchronisiert die App beim Öffnen, bei Standortereignissen und nach von iOS gewährten Hintergrundläufen.")
                InfoLine(symbol: "wifi", text: "Der WLAN-Name ist nur verfügbar, wenn iOS die Access-WiFi-Information-Berechtigung akzeptiert; WLAN/Mobilfunk wird immer erkannt.")
                InfoLine(symbol: "heart.text.square", text: "Der RJ-Schlafindex berücksichtigt Dauer, Regelmäßigkeit und aufgezeichnete Unterbrechungen. Er ist eine eigene Schätzung, kein Originalscore von Apple.")
            }

            Section("Diagnose") {
                NavigationLink {
                    DebugConsoleView()
                } label: {
                    Label("Debug-Konsole", systemImage: "terminal.fill")
                }
                LabeledContent("App-Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Backend", value: appState.features == nil ? "Noch nicht erkannt" : "Verbunden")
            }

            case .storage:
            Section("Speicher") {
                StorageSummaryView()
                LabeledContent("Von dir belegt", value: ByteCountFormatter.string(fromByteCount: Int64(appState.storageUsedBytes), countStyle: .file))
                if let limit = appState.me?.storageLimitMB, limit > 0 {
                    ProgressView(value: Double(appState.storageUsedBytes), total: Double(limit * 1024 * 1024))
                    Text("Limit: \(limit) MB · wird in rjapp_config.json festgelegt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kein Speicherlimit für diesen Benutzer festgelegt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            }
        }.scrollContentBackground(.hidden).background(LoveBackground())
        .navigationTitle(section.rawValue).navigationBarTitleDisplayMode(.inline)
        .onChange(of:health.sharingEnabled){_,_ in appState.queuePresenceUpload(force:true)}
        .onChange(of:location.sharingEnabled){_,_ in appState.queuePresenceUpload(force:true)}
        .onChange(of:appState.shareWiFiName){_,_ in appState.queuePresenceUpload(force:true)}
        .task{await notifications.refreshStatus();microphone=AVAudioApplication.shared.recordPermission}
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
    private var locationStatus: String {
        switch location.authorizationStatus {
        case .authorizedAlways: "Immer erlaubt"
        case .authorizedWhenInUse: "Beim Verwenden"
        case .denied: "Abgelehnt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var notificationStatus: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Erlaubt"
        case .denied: "Abgelehnt"
        case .notDetermined: "Nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var alarmStatus: String {
        switch appState.alarms.authorizationState {
        case .authorized: "Erlaubt"
        case .denied: "Abgelehnt"
        case .notDetermined: "Nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var motionStatus: String {
        switch device.motionAuthorization {
        case .authorized: "Erlaubt · \(device.motion)"
        case .denied: "Abgelehnt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var calendarStatus: String {
        switch calendar.authorizationStatus {
        case .fullAccess: "Voller Zugriff"
        case .writeOnly: "Nur Schreiben"
        case .denied: "Abgelehnt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let symbol: String
    let tint: Color
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InfoLine: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.footnote).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(LovePalette.cyan)
        }
    }
}
