import Charts
import CoreMotion
import SwiftUI

struct HealthDashboardView:View {
    @Environment(AppState.self) private var app
    @ObservedObject private var health=HealthService.shared
    @ObservedObject private var device=DeviceStatusService.shared
    @State private var mine=false
    private var presence:PresencePayload? {app.partner?.presence}
    private var metrics:[String:Double] {mine ? health.metrics:presence?.healthMetrics ?? [:]}
    private var dates:[String:String] {mine ? health.metricDates:presence?.healthMetricDates ?? [:]}
    private var sleep:SleepSummary? {mine ? health.sleepSummary:presence?.sleepSummary}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                LoveEyebrow(text:"Füreinander da sein")
                Text("Euer Wohlgefühl.").font(.system(size:34,weight:.medium,design:.serif))
                Picker("Profil",selection:$mine){Text(app.partner?.displayName ?? "Schatzi").tag(false);Text("Meine Daten").tag(true)}.pickerStyle(.segmented)
                Text(mine ? "Deine Health-Daten bleiben deine Entscheidung. Unten wählst du getrennt aus, welche Zusammenfassungen ihr teilt.":"Nur die bewusst freigegebenen Werte deines Lieblingsmenschen. REM und Tiefschlaf erscheinen nur, wenn die Datenquelle sie aufgezeichnet hat.").font(.subheadline).foregroundStyle(.secondary)
                if let updated=mine ? health.lastUpdated:presence?.healthUpdatedAt?.rjDate {Text("Health zuletzt abgeglichen: \(updated.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)}
                if let sleep {SleepDetailCard(summary:sleep)}else{
                    ContentUnavailableView("Noch kein Schlafabschnitt verfügbar",systemImage:"moon.stars",description:Text(mine ? "Health verbinden, Schlafdaten freigeben und nach einer erfassten Nacht aktualisieren.":"Dein Lieblingsmensch kann Schlafdaten auf dem eigenen iPhone freigeben und aktualisieren."))
                }
                motionCard
                activitySection
                vitalsSection
                if mine {sharingControls}
                Text("Ein Strich bedeutet: kein verfügbarer oder freigegebener Wert. iOS verrät Apps nicht, ob einzelne Health-Leserechte abgelehnt wurden. Angezeigt werden vorhandene Messungen mit ihrem jeweiligen Datum, keine Live-Messung. Die Ansicht stellt keine Diagnose.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(LoveBackground()).navigationTitle("Health & Schlaf").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button{Task{await refresh()}}label:{Image(systemName:"arrow.clockwise")}.disabled(health.refreshing)}}
            .task{await health.refresh()}
            .refreshable{await refresh()}
            .onChange(of:health.sharingEnabled){_,_ in app.queuePresenceUpload(force:true)}
            .onChange(of:health.shareActivity){_,_ in app.queuePresenceUpload(force:true)}
            .onChange(of:health.shareSleep){_,_ in app.queuePresenceUpload(force:true)}
            .onChange(of:health.shareVitals){_,_ in app.queuePresenceUpload(force:true)}
    }
    private var motionCard:some View {
        let value=mine ? device.motion:presence?.motion ?? "Unbekannt"
        return HStack(spacing:16) {
            Image(systemName:MotionPresentation.symbol(value)).font(.system(size:34)).foregroundStyle(LovePalette.cyan).frame(width:62,height:62).background(LovePalette.cyan.opacity(0.12),in:RoundedRectangle(cornerRadius:20))
            VStack(alignment:.leading,spacing:5) {
                Text("Bewegung & Fitness").font(.caption.bold()).foregroundStyle(.secondary)
                Text(MotionPresentation.title(value)).font(.title3.bold())
                if let confidence=mine ? device.motionConfidence:presence?.motionConfidence {Text("Erkennung: \(confidence)").font(.caption).foregroundStyle(.secondary)}
                if mine,device.motionAuthorization != .authorized {Button("Bewegung erlauben"){Task{await device.requestMotionAccess()}}.font(.subheadline.bold())}
            };Spacer(minLength:0)
        }.loveCard()
    }
    private var activitySection:some View {
        VStack(alignment:.leading,spacing:14) {
            LoveSectionTitle("Dein Tag in Bewegung",subtitle:"Heutige Summen und zuletzt erfasste Bewegungswerte")
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                LoveMetric(title:"Schritte heute",value:(mine ? health.steps:presence?.steps)?.formatted() ?? "–",symbol:"figure.walk",tint:LovePalette.cyan)
                metric("distance_km","Zu Fuß heute","km","figure.walk.motion",.cyan)
                metric("cycling_km","Radstrecke heute","km","figure.outdoor.cycle",.cyan)
                metric("active_kcal","Aktivenergie heute","kcal","flame.fill",.orange)
                metric("resting_kcal","Ruheenergie heute","kcal","bed.double.fill",.purple)
                metric("exercise_minutes","Training heute","min","figure.run",.pink)
                metric("stand_minutes","Stehzeit heute","min","figure.stand",.cyan)
                metric("flights","Etagen heute","","stairs",.cyan)
                metric("walking_speed_kmh","Gehgeschwindigkeit","km/h","figure.walk",.cyan)
                metric("step_length_cm","Schrittlänge","cm","shoeprints.fill",.cyan)
            }
        }
    }
    private var vitalsSection:some View {
        VStack(alignment:.leading,spacing:14) {
            LoveSectionTitle("Was dein Körper teilt",subtitle:"Letzte Messungen aus bis zu 30 Tagen · Datum je Wert")
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                metric("heart_rate","Puls","bpm","heart.fill",.pink)
                metric("resting_heart_rate","Ruhepuls","bpm","heart",.pink)
                metric("walking_heart_rate","Gehpuls","bpm","figure.walk.heart.fill",.pink)
                metric("hrv_ms","HRV (SDNN)","ms","waveform.path.ecg",.purple)
                metric("oxygen_percent","Blutsauerstoff","%","lungs.fill",.cyan)
                metric("respiratory_rate","Atemfrequenz","/min","wind",.cyan)
                metric("wrist_temperature_c","Handgelenk nachts","°C","thermometer.medium",.orange)
                metric("body_temperature_c","Körpertemperatur","°C","thermometer.medium",.orange)
                metric("vo2_max","Cardiofitness","ml/kg/min","figure.run",.pink)
                metric("body_mass_kg","Körpergewicht","kg","scalemass.fill",.purple)
                metric("systolic_mmhg","Blutdruck systolisch","mmHg","heart.text.square",.pink)
                metric("diastolic_mmhg","Blutdruck diastolisch","mmHg","heart.text.square",.pink)
            }
        }
    }
    private func metric(_ key:String,_ title:String,_ unit:String,_ symbol:String,_ tint:Color)->some View {
        VStack(alignment:.leading,spacing:6) {
            LoveMetric(title:title,value:metrics[key].map{"\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"} ?? "–",symbol:symbol,tint:tint)
            if let date=dates[key]?.rjDate {Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary).padding(.horizontal,8)}
        }
    }
    private var sharingControls:some View {
        VStack(alignment:.leading,spacing:16) {
            LoveSectionTitle("Du entscheidest.",subtitle:"Zusätzliche Werte benötigen deine iOS-Freigabe auf diesem iPhone.")
            Button("Health-Freigabe erweitern",systemImage:"heart.text.square"){Task{await health.requestAuthorization();app.queuePresenceUpload(force:true)}}.buttonStyle(.glassProminent)
            Button("Bewegung & Fitness prüfen",systemImage:"figure.walk.motion"){Task{await device.requestMotionAccess()}}.buttonStyle(.glass)
            Toggle("Health-Zusammenfassungen teilen",isOn:$health.sharingEnabled)
            Toggle("Aktivität & Schritte",isOn:$health.shareActivity).disabled(!health.sharingEnabled)
            Toggle("Schlafphasen, Verlauf & RJ-Schlafindex",isOn:$health.shareSleep).disabled(!health.sharingEnabled)
            Toggle("Vitalwerte & Körpermessungen",isOn:$health.shareVitals).disabled(!health.sharingEnabled)
            Stepper(value:$health.sleepGoalHours,in:4...12,step:0.5){Text("Mein Schlafziel: \(health.sleepGoalHours.formatted(.number.precision(.fractionLength(0...1)))) h")}
                .onChange(of:health.sleepGoalHours){_,_ in Task{await health.refresh(force:true);app.queuePresenceUpload(force:true)}}
            if health.refreshing {ProgressView("Health wird gelesen …")}
            if let error=health.errorMessage {Text(error).font(.caption).foregroundStyle(.orange)}
        }.loveCard()
    }
    private func refresh() async {await health.refresh(force:true);_ = await app.syncNow(showErrors:false)}
}
struct SleepDetailCard:View {
    let summary:SleepSummary
    private var night:SleepNight {summary.night}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Label("Dein letzter Schlaf",systemImage:"moon.stars.fill").font(.headline).foregroundStyle(LovePalette.violet)
                    if let end=night.end {Text(end.formatted(date:.long,time:.omitted)).font(.subheadline).foregroundStyle(.secondary)}
                    Text(duration(night.totalMinutes)).font(.system(size:38,weight:.light,design:.rounded))
                };Spacer()
                VStack(spacing:4){Text(summary.score.map(String.init) ?? "–").font(.system(size:38,weight:.semibold,design:.rounded));Text("RJ-Schlafindex").font(.caption2)}.foregroundStyle(LovePalette.violet)
            }
            if let start=night.start,let end=night.end {
                Text("\(start.formatted(date:.abbreviated,time:.shortened)) – \(end.formatted(date:.abbreviated,time:.shortened))").font(.caption.monospacedDigit())
                Chart(summary.segments.filter{$0.stage != .bed}) {segment in
                    if let a=segment.start,let b=segment.end {BarMark(xStart:.value("Beginn",a),xEnd:.value("Ende",b),y:.value("Phase",segment.stage.title)).foregroundStyle(segment.stage.color).cornerRadius(3)}
                }.chartXScale(domain:start...end).chartLegend(.hidden).frame(height:190)
                    .accessibilityLabel("Aufgezeichnete Schlafphasen von \(start.formatted()) bis \(end.formatted())")
            }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                phase(.rem,night.remMinutes);phase(.core,night.coreMinutes);phase(.deep,night.deepMinutes);phase(.awake,night.awakeMinutes)
                if night.unspecifiedMinutes>0 {phase(.unspecified,night.unspecifiedMinutes)}
            }
            HStack{Label(night.wakeCount.map{"\($0) Wachabschnitte"} ?? "Keine Wachphasen verfügbar",systemImage:"eye.fill");Spacer();if let efficiency=night.efficiency {Text("\(Int(efficiency.rounded())) % Schlafanteil")}}.font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("So entsteht euer RJ-Schlafindex") {
                VStack(alignment:.leading,spacing:10) {
                    scorePart("Dauer",summary.durationPoints,50)
                    scorePart("Regelmäßigkeit",summary.consistencyPoints,30)
                    scorePart("Aufgezeichnete Unterbrechungen",summary.interruptionPoints,20)
                    Text("Vergleich: \(summary.baselineNights) vorherige Nächte, maximal 13. Schlafziel: \(duration(summary.targetMinutes)). Für den Gesamtwert sind mindestens drei Vergleichsnächte und detaillierte Phasen nötig.")
                    Text("Eigenständige RJ-Schätzung mit 50/30/20-Gewichtung für Dauer, Regelmäßigkeit und Unterbrechungen. Apples exakte Formel und Originalscore werden hier nicht ausgelesen. REM und Tiefschlaf sind Messwerte aus Health und werden nicht künstlich ergänzt.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top,8)
            }
            Text("Datenquelle: \(night.source)").font(.caption2).foregroundStyle(.secondary)
            if !summary.history.isEmpty {history}
        }.loveCard()
    }
    private var history:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Eure letzten Nächte").font(.headline)
            Chart(([night]+summary.history).reversed()) {value in
                if let date=value.end {BarMark(x:.value("Nacht",date,unit:.day),y:.value("Stunden",Double(value.totalMinutes)/60)).foregroundStyle(value.id==night.id ? LovePalette.pink:LovePalette.violet.opacity(0.6))}
            }.frame(height:135)
            Text("Kurze Nickerchen werden nicht als neue Hauptnacht gewertet. Überlappende Daten mehrerer Quellen werden nicht doppelt addiert.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func phase(_ stage:SleepStage,_ minutes:Int?)->some View {
        HStack{Circle().fill(stage.color).frame(width:8,height:8);VStack(alignment:.leading){Text(stage.title).font(.caption);Text(minutes.map(duration) ?? "Nicht erfasst").font(.subheadline.bold())};Spacer(minLength:0)}.padding(10).background(stage.color.opacity(0.09),in:RoundedRectangle(cornerRadius:14))
    }
    private func scorePart(_ title:String,_ points:Double?,_ max:Int)->some View {HStack{Text(title);Spacer();Text(points.map{"\(Int($0.rounded())) / \(max)"} ?? "Noch nicht berechenbar")}}
    private func duration(_ value:Int)->String {"\(value/60) h \(value%60) min"}
}
extension SleepStage {
    var color:Color {switch self{case .awake:.orange;case .rem:.cyan;case .core:.blue;case .deep:.indigo;case .unspecified:.purple;case .bed:.gray}}
}
struct HealthPermissionsUpgradeView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var working=false
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:22) {
                Image(systemName:"heart.text.square.fill").font(.system(size:54)).foregroundStyle(LovePalette.pink)
                Text("Noch besser füreinander da.").font(.system(size:32,weight:.medium,design:.serif))
                Text("RJ Love kann jetzt Schlafphasen, Nächte im Verlauf und mehr Aktivitäts- und Vitalwerte anzeigen. Jedes iPhone muss die zusätzlichen Leserechte selbst freigeben.")
                Label("REM, Kern-, Tiefschlaf und aufgezeichnete Wachphasen",systemImage:"moon.stars.fill")
                Label("Bewegung & Fitness mit passenden Symbolen",systemImage:"figure.walk.motion")
                Label("Weitere Vital- und Körpermesswerte mit Messdatum",systemImage:"waveform.path.ecg")
                Text("Die bisherigen Freigabeschalter bleiben unverändert. Unter Health → Meine Daten entscheidest du, was dein Lieblingsmensch sehen darf. Ohne passende Datenquelle erscheinen keine erfundenen Werte.").font(.subheadline).foregroundStyle(.secondary)
                Button(working ? "Freigaben werden geöffnet …":"Health & Bewegung freigeben") {working=true;Task{await app.health.requestAuthorization();await app.deviceStatus.requestMotionAccess();app.queuePresenceUpload(force:true);working=false;dismiss()}}.buttonStyle(.glassProminent).controlSize(.large).disabled(working)
                Button("Später selbst einrichten"){app.health.deferExpandedAccess();dismiss()}.disabled(working)
                if let error=app.health.errorMessage {Text(error).font(.caption).foregroundStyle(.orange)}
            }.padding(24)}.navigationTitle("Health erweitern").navigationBarTitleDisplayMode(.inline).background(LoveBackground())
        }.interactiveDismissDisabled(working)
    }
}
