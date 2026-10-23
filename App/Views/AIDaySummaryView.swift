import SwiftUI

struct AIDaySummaryView:View {
    @Environment(AppState.self) private var app
    @State private var day:Date
    @State private var status:AIIntegrationStatus?
    @State private var result:AIDaySummary?
    @State private var busy=false
    @State private var error:String?
    @State private var selected:SharedRecord?
    @State private var sources:[SharedRecord]=[]
    init(day:Date = .now){_day=State(initialValue:day)}
    private var ready:Bool{status?.available==true && status?.myConsent==true && status?.partnerConsent==true}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:22){
            VStack(alignment:.leading,spacing:16){LoveEyebrow(text:"Aus kleinen Momenten wird ein Wir");HStack{Text("Ein Tag,\nder bleiben darf.").font(.system(size:33,weight:.medium,design:.serif));Spacer();LoveIcon(symbol:"sparkles",tint:LovePalette.violet,size:62)};Text("Ein liebevoll formulierter Rückblick aus euren gespeicherten Momenten. Mit kleinen Kapiteln und einer Frage für euren Abend.").font(.subheadline).foregroundStyle(.secondary)}.loveCard()
            VStack(alignment:.leading,spacing:16){
                DatePicker("Euer Tag",selection:$day,in:...Date.now,displayedComponents:.date).disabled(busy)
                if let status {
                    Label(status.available ? "KI am Server eingerichtet":"KI am Server noch ausgeschaltet",systemImage:status.available ? "checkmark.circle.fill":"power").font(.caption).foregroundStyle(.secondary)
                    if !ready {NavigationLink{AISettingsView()}label:{Label("KI-Rückblick einrichten",systemImage:"slider.horizontal.3")}.buttonStyle(.bordered)}
                    if status.available,!status.partnerConsent {Text("\(app.partner?.displayName ?? "Dein Lieblingsmensch") hat die Freigabe noch nicht aktiviert.").font(.caption).foregroundStyle(.secondary)}
                }else if error==nil{ProgressView("Freigaben werden geladen …")}
                Button{Task{await generate()}}label:{HStack{if busy{ProgressView().tint(.white)};Label(busy ? "Euer Rückblick entsteht …":"Momente zusammenfassen",systemImage:"sparkles").frame(maxWidth:.infinity)}}.buttonStyle(.borderedProminent).controlSize(.large).disabled(!ready || busy).accessibilityIdentifier("ai-generate")
                Text("Nur auf deinen Tipp: Titel, Beschreibungen, Autorennamen, Medienart und Aufnahmezeiten dieses Tages gehen an OpenAI. Keine Foto-/Video- oder Audiodateien, Chats, Health-Werte oder GPS-Koordinaten. Beiderseitige Freigabe erforderlich.").font(.caption).foregroundStyle(.secondary)
            }.loveCard()
            if let error{Text(error).foregroundStyle(.orange).font(.footnote);if status==nil{Button("Erneut laden"){Task{await loadStatus()}}.buttonStyle(.bordered)}}
            if let result {summary(result)}
            NavigationLink{AISettingsView()}label:{Label("Freigabe & Kostenkontrolle",systemImage:"hand.raised.fill")}.font(.caption).buttonStyle(.bordered)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Euer KI-Rückblick").navigationBarTitleDisplayMode(.inline)
        .task{await loadStatus()}.onChange(of:day){_,_ in result=nil;error=nil;sources=[]}
        .sheet(item:$selected){record in NavigationStack{ScrollView{JournalRecordDetail(record:record).padding(20)}.background(LoveBackground()).navigationTitle("Ein Moment von euch").toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){selected=nil}}}}}
    }
    private func summary(_ value:AIDaySummary)->some View {
        VStack(alignment:.leading,spacing:22){
            HStack{Label("Mit KI formuliert",systemImage:"sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet);Spacer();if value.cached{Text("Schon für euch bewahrt").font(.caption2).foregroundStyle(.secondary)}}
            Text(value.summary.title).font(.system(size:31,weight:.medium,design:.serif))
            Text(value.summary.intro).font(.body).lineSpacing(4)
            ForEach(Array(value.summary.highlights.enumerated()),id:\.offset){_,highlight in
                VStack(alignment:.leading,spacing:10){Label(highlight.title,systemImage:"heart.text.square.fill").font(.headline).foregroundStyle(LovePalette.pink);Text(highlight.detail).font(.subheadline).lineSpacing(4)
                    ForEach(highlight.recordIDs,id:\.self){id in if let record=sources.first(where:{$0.id==id}){Button{selected=record}label:{Label(record.payload.caption?.isEmpty==false ? record.payload.caption!:"Moment ansehen",systemImage:"photo").lineLimit(1)}.font(.caption).buttonStyle(.bordered)}}
                }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(LovePalette.pink.opacity(0.06),in:RoundedRectangle(cornerRadius:20))
            }
            if !value.summary.reflection.isEmpty{VStack(alignment:.leading,spacing:8){LoveEyebrow(text:"Ein Gedanke für euch");Text(value.summary.reflection).font(.body).lineSpacing(4)}}
            if !value.summary.question.isEmpty{VStack(alignment:.leading,spacing:8){Label("Für euer Abendgespräch",systemImage:"bubble.left.and.bubble.right.fill").font(.caption.bold()).foregroundStyle(LovePalette.violet);Text(value.summary.question).font(.system(.title3,design:.serif))}.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(LovePalette.violet.opacity(0.08),in:RoundedRectangle(cornerRadius:22))}
            Text("\(value.sourceCount) von \(value.totalCount) gespeicherten Momenten · "+(value.generatedAt.rjDate?.formatted(date:.abbreviated,time:.shortened) ?? "")).font(.caption2).foregroundStyle(.secondary)
            Text("Der Rückblick kennt nur eure Beschreibungen, sieht keine Bilder und kann sich irren. Er ist keine Bewertung eurer Beziehung und kein vollständiges Tagebuch.").font(.caption2).foregroundStyle(.secondary)
        }.loveCard().textSelection(.enabled).accessibilityIdentifier("ai-summary-card")
    }
    private func loadStatus() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview"){status=AIIntegrationStatus(available:true,model:"gpt-6-luna",myConsent:true,partnerConsent:true,dailyLimit:8)
            if ProcessInfo.processInfo.arguments.contains("--preview-ai-summary") {result=AIDaySummary(summary:.init(title:"Ein kleines Stück für immer.",intro:"Beispielansicht: Drei beschriebene Momente erzählen von einem Spaziergang und einem gemütlichen Abend.",highlights:[.init(title:"Draußen zusammen",detail:"Euer Moment trägt die Beschreibung „Ein Spaziergang nur für uns“. Eine kleine Erinnerung an gemeinsame Zeit.",recordIDs:[]),.init(title:"Zeit für Gemütlichkeit",detail:"„Unser Abend auf dem Sofa“ habt ihr zu einem weiteren Moment geschrieben.",recordIDs:[])],reflection:"Auch kurze Beschreibungen können einen Tag bewahren, ohne alles davon festhalten zu müssen.",question:"Welchen kleinen Augenblick möchtet ihr euch für morgen merken?"),model:"gpt-6-luna",generatedAt:Date.now.rjISO8601,sourceCount:3,totalCount:3,cached:true)}
            return}
        #endif
        do{status=try await app.api.aiStatus();if !ready{result=nil;sources=[]}}catch{self.error=error.localizedDescription}
    }
    private func generate() async {
        busy=true;error=nil;defer{busy=false}
        do{let value=try await app.api.aiSummary(day:day);try Task.checkCancellation();let page=try? await app.api.journal(day:day);result=value;sources=page?.records ?? []}catch{self.error=error.localizedDescription}
    }
}
struct AISettingsView:View {
    @Environment(AppState.self) private var app
    @State private var status:AIIntegrationStatus?
    @State private var busy=false
    @State private var error:String?
    var body:some View {
        Form{
            Section{
                Label("Euer Tag in liebevollen Worten",systemImage:"sparkles").font(.headline)
                Text("Die optionale OpenAI-Integration formuliert aus den Beschreibungen eurer Momente einen Tagesrückblick. Es wird nichts automatisch an OpenAI gesendet.")
            }
            if let status {
                Section("Deine Freigabe"){
                    Toggle("Meine Momenttexte für KI erlauben",isOn:Binding(get:{status.myConsent},set:{enabled in Task{await setConsent(enabled)}})).disabled(busy).accessibilityIdentifier("ai-consent")
                    Label(status.partnerConsent ? "Dein Lieblingsmensch hat zugestimmt":"Freigabe deines Lieblingsmenschen fehlt",systemImage:status.partnerConsent ? "checkmark.circle":"person.crop.circle.badge.clock")
                    Text("Erst wenn ihr beide zustimmt, kann ein Rückblick erstellt werden. Ausschalten löscht die gespeicherten KI-Rückblicke am eigenen Server; eure Originalmomente bleiben erhalten.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Server & Kosten"){
                    LabeledContent("Integration",value:status.available ? "Bereit":"Nicht eingerichtet")
                    LabeledContent("Modell",value:status.model)
                    LabeledContent("Neue Rückblicke",value:"Max. \(status.dailyLimit) / Tag für euch beide")
                    Text("Unveränderte Tage werden aus dem gespeicherten Rückblick geladen. Auch fehlgeschlagene neue API-Versuche zählen zum Tageslimit. Die tatsächlichen Kosten werden über euren OpenAI-API-Zugang abgerechnet.").font(.footnote).foregroundStyle(.secondary)
                }
                if status.available {NavigationLink{AIDaySummaryView()}label:{Label("Euren Tag zusammenfassen",systemImage:"sparkles")}}
            }else{ProgressView("Freigabe laden …")}
            Section("Welche Daten gehen an OpenAI?"){
                Text("Nur bis zu 60 Momente des gewählten Tages: Titel, Beschreibungen, Autorennamen, Medienart und Aufnahmezeiten. Keine Bilddateien, Videos, Audiodateien, Chats, Health-Werte oder GPS-Koordinaten. Ohne Beschreibung werden keine Bildinhalte erraten.").font(.footnote)
                Text("Die API-Anfrage verwendet store: false. Dies deaktiviert die Speicherung als abrufbare API-Antwort; weitere Verarbeitung richtet sich nach den Einstellungen und Bedingungen eures OpenAI-API-Kontos.").font(.footnote).foregroundStyle(.secondary)
            }
            if status?.available==false {Section("Einmal am Server einrichten") {Text("Im openai-Abschnitt von rjapp_config.json enabled aktivieren und den API-Schlüssel dort oder als OPENAI_API_KEY hinterlegen. Standardmodell: gpt-6-luna. Der Schlüssel wird nie in der App gespeichert. Anleitung im Updatepaket.").font(.footnote).textSelection(.enabled)}}
            if let error{Section{Text(error).foregroundStyle(.orange);Button("Erneut laden"){Task{await load()}}}}
        }.navigationTitle("KI-Rückblick").navigationBarTitleDisplayMode(.inline).task{await load()}
    }
    private func load() async {do{status=try await app.api.aiStatus();error=nil}catch{self.error=error.localizedDescription}}
    private func setConsent(_ enabled:Bool) async {busy=true;defer{busy=false};do{status=try await app.api.setAIConsent(enabled);error=nil}catch{self.error=error.localizedDescription}}
}
