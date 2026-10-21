import AVFoundation
import CoreLocation
import CoreMotion
import SwiftUI

@MainActor @Observable final class SetupJourney {
    var presented = false
    private(set) var running = false
    private(set) var step = 0
    private(set) var finished = false
    let steps = ["Mitteilungen", "Mikrofon", "Standort", "Bewegung & Fitness", "Apple Health", "Kalender", "Weckrufe", "App-Schutz", "Walkie-Talkie"]
    var accountKey: String?
    func check(profile: ServerProfile?, userID: String?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return }
        #endif
        guard let profile, let userID else { return }
        let key = "rjlove.setup-2.2." + profile.baseURL + "." + userID
        accountKey = key
        if UserDefaults.standard.bool(forKey: key) { finished = true; step = steps.count }
        if !UserDefaults.standard.bool(forKey: key), !presented { step = 0; finished = false; presented = true }
    }
    func run(app: AppState) async {
        guard !running else { return }; running = true
        // The OS remains the authority for consent. Sharing preferences are enabled once,
        // never overwritten on later launches or when returning to this checklist.
        app.health.sharingEnabled = true
        app.health.shareActivity = true; app.health.shareSleep = true; app.health.shareVitals = true
        app.shareWiFiName = true
        step = 0; _ = await app.notifications.requestAuthorization()
        step = 1; _ = await AVAudioApplication.requestRecordPermission()
        step = 2; await app.location.requestSetupAccess(); app.location.sharingEnabled = true
        step = 3; await app.deviceStatus.requestMotionAccess()
        step = 4; await app.health.requestAuthorization()
        step = 5; _ = await app.calendar.requestAccess()
        step = 6; _ = await app.alarms.requestAuthorization()
        step = 7; _ = await app.privacyLock.enableAfterAuthentication()
        step = 8; await app.radio.enable(api: app.api)
        app.queuePresenceUpload(force: true)
        if let accountKey { UserDefaults.standard.set(true, forKey: accountKey) }
        step = steps.count; finished = true; running = false
    }
}
struct SetupJourneyView: View {
    @Environment(AppState.self) private var app
    private var journey: SetupJourney { app.setupJourney }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: journey.finished ? "checkmark.seal.fill" : "heart.text.clipboard.fill")
                        .font(.system(size: 56)).foregroundStyle(LovePalette.pink.gradient)
                        .symbolEffect(.bounce, value: journey.finished)
                    LoveEyebrow(text: "Euer Raum. Einmal richtig einrichten.")
                    Text(journey.finished ? "Bereit für euer Wir." : "Alles, was euch verbindet.")
                        .font(.system(size: 34, weight: .medium, design: .serif))
                    Text("RJ Love fragt die benötigten iPhone-Berechtigungen nacheinander ab und schaltet eure Freigaben ein: Standort, Aktivität, Schlaf, Vitalwerte und WLAN-Name. Walkie-Talkie-Empfang und Vorlesen sind zunächst eingeschaltet. Unter „Mehr“ kannst du alles einzeln ausschalten.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 16) {
                        ForEach(Array(journey.steps.enumerated()), id: \.offset) { index, name in
                            HStack {
                                Image(systemName: index < journey.step ? "checkmark.circle.fill" : index == journey.step && journey.running ? "circle.dotted" : "circle")
                                    .foregroundStyle(index < journey.step ? LovePalette.cyan : LovePalette.violet)
                                    .symbolEffect(.pulse, isActive: index == journey.step && journey.running)
                                Text(name).font(.subheadline.weight(.medium)); Spacer()
                                if index == journey.step && journey.running { ProgressView() }
                            }
                        }
                    }.loveCard()
                    Text("Ein Häkchen bedeutet: Schritt bearbeitet. Deine iOS-Entscheidung gilt; abgelehnte Zugriffe bleiben gesperrt. „Standort immer“ kann iOS später nochmals bestätigen lassen. Nahbereichssuche fragt erst, wenn beide Geräte die Suche starten; die Fotoauswahl erfolgt über Apples geschützten Bildwähler.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if journey.finished {
                        Button("Los geht’s", systemImage: "heart.fill") { journey.presented = false }.buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Freigaben überprüfen") { journey.presented = false; app.selectedTab = .settings }.buttonStyle(.bordered)
                    } else {
                        Button {
                            Task { await journey.run(app: app) }
                        } label: { Label(journey.running ? journey.steps[min(journey.step, journey.steps.count - 1)] + " …" : "Alles einrichten", systemImage: "sparkles").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(journey.running)
                    }
                }.padding(26)
            }.background(LoveBackground()).navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
}
