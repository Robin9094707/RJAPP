import SwiftUI

struct CountdownHubView:View {
    @Environment(AppState.self) private var app
    @State private var adding=false
    @State private var anniversary=false
    @State private var editing:SharedRecord?
    @State private var deleting:SharedRecord?
    private var entries:[SharedRecord] {app.records.filter{$0.kind == .milestone}.sorted{ (LoveCountdown(record:$0)?.nextDate() ?? .distantFuture)<(LoveCountdown(record:$1)?.nextDate() ?? .distantFuture) }}
    private var ourDay:SharedRecord? {entries.first{$0.payload.countdownType=="anniversary"}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:10) {
                    LoveEyebrow(text:"Jeder Tag ein bisschen mehr wir")
                    Text("Unsere kleinen Ewigkeiten.").font(.system(size:32,weight:.medium,design:.serif))
                    Text("Euer Jahrestag und alles, worauf ihr euch gemeinsam freut.").foregroundStyle(.secondary)
                }
                if let ourDay,let item=LoveCountdown(record:ourDay) {
                    Button{editing=ourDay}label:{CountdownCard(item:item,featured:true)}.buttonStyle(.lovePress)
                }else{
                    Button {anniversary=true;adding=true} label: {
                        VStack(spacing:12){Image(systemName:"heart.circle.fill").font(.system(size:52));Text("Unseren Jahrestag eintragen").font(.title3.bold());Text("Ab dann zählt hier eure gemeinsame Zeit.").font(.subheadline)}.frame(maxWidth:.infinity).padding(26).loveCard()
                    }.buttonStyle(.lovePress).tint(LovePalette.pink)
                }
                Button("Eigenen Countdown hinzufügen",systemImage:"plus.circle.fill"){anniversary=false;adding=true}.buttonStyle(.borderedProminent).controlSize(.large)
                ForEach(entries.filter{$0.id != ourDay?.id}) {record in
                    if let item=LoveCountdown(record:record) {
                        Button{editing=record}label:{CountdownCard(item:item,featured:false)}.buttonStyle(.lovePress)
                            .contextMenu{Button("Bearbeiten",systemImage:"pencil"){editing=record};Button("Löschen",systemImage:"trash",role:.destructive){deleting=record}}
                    }
                }
                Label("Widget hinzufügen → RJ Love → Mein Countdown. Im Widget lange drücken und euren gewünschten Countdown auswählen.",systemImage:"rectangle.on.rectangle").font(.footnote).foregroundStyle(.secondary).loveCard()
                NavigationLink{PlannerView()}label:{Label("Zum gemeinsamen Kalender",systemImage:"calendar")}.buttonStyle(.bordered)
            }.padding(20)
        }.background(LoveBackground()).navigationTitle("Jahrestag & Countdowns").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$adding){CountdownEditor(initial:nil,anniversary:anniversary)}
            .sheet(item:$editing){CountdownEditor(initial:$0,anniversary:$0.payload.countdownType=="anniversary")}
            .alert("Für euch beide löschen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
                Button("Löschen",role:.destructive){if let deleting{Task{_ = await app.deleteRecord(deleting)}};deleting=nil}
                Button("Behalten",role:.cancel){deleting=nil}
            }.task{await app.loadRecordArchive(kind:.milestone)}
    }
}
struct CountdownCard:View {
    let item:LoveCountdown
    var featured:Bool
    var body:some View {
        TimelineView(.periodic(from:.now,by:60)) {context in
            VStack(alignment:.leading,spacing:14) {
                HStack {Label(item.anniversary ? "Unser Jahrestag":item.yearly ? "Jedes Jahr wieder":"Vorfreude",systemImage:item.anniversary ? "heart.fill":"sparkles").font(.caption.bold()).foregroundStyle(LovePalette.pink);Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)}
                Text(item.title).font(featured ? .title2.bold():.headline)
                if let days=item.days(at:context.date) {
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Text(days==0 ? "Heute":abs(days).formatted()).font(.system(size:featured ? 58:40,weight:.light,design:.rounded)).contentTransition(.numericText())
                        if days != 0 {Text(days<0 ? "Tage voller Erinnerungen":"Tage Vorfreude").font(.subheadline).foregroundStyle(.secondary)}
                    }
                }
                if let next=item.nextDate(at:context.date) {Text(next.formatted(date:.long,time:item.anniversary ? .omitted:.shortened)).font(.subheadline).foregroundStyle(.secondary)}
                if item.anniversary,let origin=item.origin {
                    let together=max(0,Calendar.current.dateComponents([.day],from:Calendar.current.startOfDay(for:origin),to:Calendar.current.startOfDay(for:context.date)).day ?? 0)
                    let time=RelationshipMilestones(start:origin,now:context.date)
                    Text(time.startsInFuture ? "Euer Anfang liegt noch vor euch":"\(time.completedMonths) volle Monate · im \(time.currentMonth). Beziehungsmonat").font(.subheadline.bold()).foregroundStyle(LovePalette.pink)
                    Text("Seit \(origin.formatted(date:.long,time:.omitted)) · \(together) gemeinsame Tage").font(.caption).foregroundStyle(LovePalette.pink)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).loveCard()
        }
    }
}
struct CountdownEditor:View {
    let initial:SharedRecord?
    let anniversary:Bool
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var date=Date.now
    @State private var yearly=false
    @State private var saving=false
    @State private var error:String?
    @State private var confirmDelete=false
    var body:some View {
        NavigationStack {
            Form {
                Section(anniversary ? "Der Anfang von uns":"Darauf freuen wir uns") {
                    TextField("Titel",text:$title)
                    DatePicker(anniversary ? "Zusammen seit":"Unser Ziel",selection:$date,displayedComponents:anniversary ? [.date]:[.date,.hourAndMinute])
                    if !anniversary {Toggle("Jedes Jahr wieder",isOn:$yearly)}
                    Text(anniversary ? "Euer nächster Jahrestag wird jedes Jahr automatisch berechnet. Ein 29. Februar wird in anderen Jahren am 28. Februar angezeigt.":"Eure Countdowns werden auf dem Server gespeichert und können einzeln als Widget angezeigt werden.").font(.caption).foregroundStyle(.secondary)
                }
                if let error {Text(error).foregroundStyle(.orange)}
                if initial != nil {Section{Button("Countdown löschen",role:.destructive){confirmDelete=true}.disabled(saving)}}
            }.navigationTitle(anniversary ? "Unser Jahrestag":"Unser Countdown").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)}
                    ToolbarItem(placement:.confirmationAction){Button(saving ? "Speichert …":"Speichern"){Task{await save()}}.disabled(saving || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || title.count>120)}
                }.interactiveDismissDisabled(saving)
                .confirmationDialog("Countdown für euch beide löschen?",isPresented:$confirmDelete,titleVisibility:.visible){Button("Löschen",role:.destructive){if let initial{Task{if await app.deleteRecord(initial){dismiss()}}}};Button("Behalten",role:.cancel){}}
                .onAppear{title=initial?.payload.title ?? (anniversary ? "Unser Jahrestag":"");date=initial?.payload.startAt?.rjDate ?? .now;yearly=initial?.payload.recurrence=="yearly"}
        }
    }
    private func save() async {
        saving=true;defer{saving=false}
        var payload=initial?.payload ?? RecordPayload()
        payload.title=title.trimmingCharacters(in:.whitespacesAndNewlines)
        payload.startAt=(anniversary ? Calendar.current.startOfDay(for:date):date).rjISO8601
        payload.countdownType=anniversary ? "anniversary":"countdown"
        payload.recurrence=(anniversary || yearly) ? "yearly":"none"
        payload.calendarSync=payload.calendarSync ?? false;payload.reminderSync=payload.reminderSync ?? false
        let id=initial?.id ?? (anniversary ? "A3300000-0000-4000-8000-000000000001":UUID().uuidString)
        if await app.saveRecord(id:id,kind:.milestone,payload:payload) != nil {dismiss()}else{error=app.alert?.message ?? "Bitte erneut versuchen."}
    }
}
