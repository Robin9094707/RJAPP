import SwiftUI

struct HealthDashboardView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var health = HealthService.shared
    @State private var mine = false
    private var metrics: [String: Double] { mine ? health.metrics : appState.partner?.presence?.healthMetrics ?? [:] }
    private var steps: Int? { mine ? health.steps : appState.partner?.presence?.steps }
    private var sleep: Int? { mine ? health.sleepMinutes : appState.partner?.presence?.sleepMinutes }
    private var sleepScore: Int? { mine ? health.sleepScore : appState.partner?.presence?.sleepScore }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LoveEyebrow(text: "Füreinander da sein")
                Text("Euer Wohlgefühl.").font(.system(size: 34, weight: .medium, design: .serif))
                Picker("Profil", selection: $mine) {
                    Text(appState.partner?.displayName ?? "Schatzi").tag(false)
                    Text("Meine Daten").tag(true)
                }.pickerStyle(.segmented)
                Text(mine ? "Diese Werte liest du auf deinem iPhone. Mit den Schaltern unten bestimmst du, was du teilst." : "Hier erscheinen ausschließlich die bewusst freigegebenen Zusammenfassungen deines Lieblingsmenschen.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let updated = mine ? health.lastUpdated : appState.partner?.presence?.healthUpdatedAt?.rjDate {
                    Text("Health-Abgleich \(updated.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    LoveMetric(title: "Schritte heute", value: steps?.formatted() ?? "–", symbol: "figure.walk", tint: LovePalette.cyan)
                    LoveMetric(title: "Schlaf · letzte 24 Std.", value: sleep.map { "\($0 / 60) h \($0 % 60) min" } ?? "–", symbol: "moon.zzz.fill", tint: LovePalette.violet)
                    LoveMetric(title: "RJ-Schlafbalance", value: sleepScore.map { "\($0) / 100" } ?? "–", symbol: "moon.stars.fill", tint: LovePalette.violet)
                    metric("distance_km", "Weg heute", "km", "figure.walk.motion", LovePalette.cyan)
                    metric("active_kcal", "Aktivenergie heute", "kcal", "flame.fill", LovePalette.coral)
                    metric("exercise_minutes", "Training heute", "min", "figure.run", LovePalette.pink)
                    metric("flights", "Etagen heute", "", "stairs", LovePalette.cyan)
                    metric("heart_rate", "Letzter Puls · 24 Std.", "bpm", "heart.fill", LovePalette.pink)
                    metric("resting_heart_rate", "Ruhepuls · 24 Std.", "bpm", "heart", LovePalette.pink)
                    metric("hrv_ms", "Letzte HRV · 24 Std.", "ms", "waveform.path.ecg", LovePalette.violet)
                    metric("oxygen_percent", "Letztes SpO₂ · 24 Std.", "%", "lungs.fill", LovePalette.cyan)
                    metric("respiratory_rate", "Atemfrequenz · 24 Std.", "/min", "wind", LovePalette.cyan)
                }
                if mine { sharingControls }
                Text("Ein Strich bedeutet: kein freigegebener oder verfügbarer Messwert. Apple verrät Apps nicht, ob einzelne Leserechte abgelehnt wurden. Vitalwerte sind die jeweils letzten vorhandenen Messungen aus 24 Stunden, keine Live-Messung. Für viele Werte brauchst du eine Apple Watch oder andere Health-Datenquellen.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Die RJ-Schlafbalance vergleicht die erfasste Schlafdauer mit acht Stunden. Sie ist kein offizieller Apple-Schlafscore und keine medizinische Bewertung.").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.background(LoveBackground()).navigationTitle("Health").navigationBarTitleDisplayMode(.inline)
        .task { await health.refresh() }
        .onChange(of: health.sharingEnabled) { _, _ in appState.queuePresenceUpload(force: true) }
        .onChange(of: health.shareActivity) { _, _ in appState.queuePresenceUpload(force: true) }
        .onChange(of: health.shareSleep) { _, _ in appState.queuePresenceUpload(force: true) }
        .onChange(of: health.shareVitals) { _, _ in appState.queuePresenceUpload(force: true) }
    }
    private func metric(_ key: String, _ title: String, _ unit: String, _ symbol: String, _ tint: Color) -> some View {
        LoveMetric(title: title, value: metrics[key].map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" } ?? "–", symbol: symbol, tint: tint)
    }
    private var sharingControls: some View {
        VStack(alignment: .leading, spacing: 17) {
            LoveSectionTitle("Du entscheidest.", subtitle: "Nur mit deiner Apple-Health-Freigabe werden Werte geteilt.")
            Button(health.requested ? "Apple-Health-Auswahl öffnen" : "Apple Health verbinden", systemImage: "heart.text.square") { Task { await health.requestAuthorization() } }.buttonStyle(.bordered)
            Toggle("Zusammenfassungen teilen", isOn: $health.sharingEnabled)
            Toggle("Aktivität & Schritte", isOn: $health.shareActivity).disabled(!health.sharingEnabled)
            Toggle("Schlaf & RJ-Schlafbalance", isOn: $health.shareSleep).disabled(!health.sharingEnabled)
            Toggle("Puls, HRV, SpO₂ & Atmung", isOn: $health.shareVitals).disabled(!health.sharingEnabled)
            if let error = health.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }.loveCard()
    }
}
