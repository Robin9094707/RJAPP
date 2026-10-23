import ActivityKit
import SwiftUI

struct LiveActivitySettingsView:View {
    @Environment(AppState.self) private var app
    var body:some View {
        @Bindable var live=app.liveActivity
        Form {
            Section("Euer Platz auf dem Sperrbildschirm") {
                Label(live.isRunning ? "Live-Aktivität aktiv":"Live-Aktivität ist aus",systemImage:live.isRunning ? "checkmark.circle.fill":"livephoto").foregroundStyle(live.isRunning ? .green:.secondary)
                Button(live.isStarting ? "Startet …":live.isRunning ? "Live-Aktivität beenden":"Jetzt starten") {
                    Task{if live.isRunning{await live.stop()}else{await app.startLiveActivity()}}
                }.disabled(live.isStarting)
                Toggle("Beim nächsten Öffnen erneuern",isOn:$live.automaticallyResume)
                Text("Erneuert eine zuvor eingeschaltete Live-Aktivität, wenn iOS sie beendet hat. Ausdrückliches Beenden in der App schaltet sie vollständig aus.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Das möchten wir sehen") {
                Toggle("Akku",isOn:$live.showBattery)
                Toggle("Status",isOn:$live.showStatus)
                Toggle("Herzgedanken",isOn:$live.showThoughts)
                Toggle("Notfallfurz-Zugang",isOn:$live.showQuickAction)
                Text("Deine Auswahl gilt für die Live-Aktivität, den Sperrbildschirm und die Dynamic Island.").font(.caption).foregroundStyle(.secondary)
                Button("Anzeige übernehmen") {Task{if live.isRunning{await app.startLiveActivity()}}}.disabled(!live.isRunning || live.isStarting)
            }
            Section("So funktioniert es") {
                Text("Startet beim Tippen sofort lokal, auch ohne Push-Verbindung. iOS muss Live-Aktivitäten für RJ Love erlauben; die Signierung muss die Widget-Erweiterung enthalten.")
                Text("Die Dynamic Island zeigt die kompakte Ansicht. Länger gedrückt halten öffnet die große Ansicht. Bei mehreren aktiven Apps entscheidet iOS über die sichtbare Darstellung. Eine App kann das Aufklappen nicht erzwingen.")
                Text("Maximal acht Stunden aktiv. Veraltete Daten werden kenntlich gemacht. Hintergrund-Ortung ist eine separate Freigabe und wird durch die Live-Aktivität nicht eingeschaltet.")
            }.font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Live-Aktivität").navigationBarTitleDisplayMode(.inline)
    }
}
