import SwiftUI

struct PlannerView:View {
    @Environment(AppState.self) private var app
    @State private var creating=false
    @State private var editing:SharedRecord?
    @State private var deleting:SharedRecord?
    @State private var day=Date.now
    @State private var all=true
    private var entries:[SharedRecord]{app.records.filter{[RecordKind.calendar,.milestone,.reminder].contains($0.kind)}.sorted{next($0)<next($1)}}
    private func next(_ record:SharedRecord)->Date {guard let date=(record.payload.dueAt ?? record.payload.startAt)?.rjDate else{return .distantFuture};return PlannerService.occurrences(date,yearly:record.payload.recurrence=="yearly").first ?? date}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:20){
            VStack(alignment:.leading,spacing:12){LoveEyebrow(text:"Zeit füreinander");Text("Was wir vorhaben.").font(.system(size:32,weight:.medium,design:.serif));Text("Ein Date, ein wichtiger Termin oder jedes Jahr wieder unser Tag.").foregroundStyle(.secondary)}.loveCard()
            DatePicker("Unser Kalender",selection:$day,displayedComponents:.date).datePickerStyle(.graphical).loveGlass(in:RoundedRectangle(cornerRadius:26))
            Toggle("Alle Termine anzeigen",isOn:$all)
            Button("Gemeinsam etwas planen",systemImage:"calendar.badge.plus"){creating=true}.buttonStyle(.borderedProminent).controlSize(.large)
            ForEach(entries.filter{all || Calendar.current.isDate(next($0),inSameDayAs:day)}){record in
                Button{editing=record}label:{VStack(alignment:.leading,spacing:9){
                    HStack{Image(systemName:record.payload.recurrence=="yearly" ? "heart.circle.fill":"calendar").foregroundStyle(LovePalette.pink);Text(record.payload.title ?? "Unsere Zeit").font(.headline);Spacer();if record.payload.alarmEnabled==true{Image(systemName:"alarm.fill")}}
                    Text(next(record).formatted(date:.complete,time:.shortened)).font(.subheadline)
                    if record.payload.recurrence=="yearly"{Text("Jedes Jahr · unser Tag").font(.caption.bold()).foregroundStyle(LovePalette.pink)}
                    if let notes=record.payload.notes ?? record.payload.text,!notes.isEmpty{Text(notes).font(.caption).foregroundStyle(.secondary)}
                }.frame(maxWidth:.infinity,alignment:.leading).loveCard()}.buttonStyle(.plain)
                .contextMenu{Button("Bearbeiten",systemImage:"pencil"){editing=record};Button("Für beide löschen",systemImage:"trash",role:.destructive){deleting=record}}
            }
            VStack(alignment:.leading,spacing:12){
                Text("Mit Apple verbinden").font(.headline)
                Text(PlannerService.shared.status).font(.caption).foregroundStyle(.secondary)
                Button("Kalender und Erinnerungen verbinden"){Task{_ = await app.calendar.requestAccess();_ = await app.calendar.requestReminderAccess();await PlannerService.shared.reconcile(app:app)}}.buttonStyle(.bordered)
                Text("Nur eure in RJ Love angelegten Einträge werden verbunden. Änderungen an diesen verknüpften Apple-Einträgen werden beim Öffnen abgeglichen. Fällige Hinweise kommen über deinen gewählten Push-Dienst. Deine Ruhezeiten werden auf dem Server berücksichtigt.").font(.footnote).foregroundStyle(.secondary)
            }.loveCard()
        }.padding(20)}.background(LoveBackground()).navigationTitle("Unsere Zeit")
            .sheet(isPresented:$creating){PlannerEditor(initial:nil,initialDate:day)}
            .sheet(item:$editing){PlannerEditor(initial:$0,initialDate:day)}
            .alert("Termin für beide löschen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Löschen",role:.destructive){if let record=deleting{Task{_ = await app.deleteRecord(record);await PlannerService.shared.reconcile(app:app)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}
    }
}
struct PlannerEditor:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let initial:SharedRecord?
    let initialDate:Date
    var onSaved:((SharedRecord)->Void)? = nil
    @State private var title=""
    @State private var notes=""
    @State private var start=Date.now
    @State private var end=Date.now.addingTimeInterval(3600)
    @State private var yearly=false
    @State private var alarm=false
    @State private var reminder=true
    @State private var calendar=true
    @State private var saving=false
    @FocusState private var titleFocused: Bool
    var body:some View {
        NavigationStack {Form{
            Section("Ein schöner Plan"){TextField("Zum Beispiel: Unser Jahrestag",text:$title).focused($titleFocused).submitLabel(.done).onSubmit{titleFocused=false};TextField("Eine Notiz für uns",text:$notes,axis:.vertical);DatePicker("Beginn",selection:$start);DatePicker("Ende",selection:$end,in:start...)}
            Section("Wiedersehen"){Toggle("Jedes Jahr",isOn:$yearly);Toggle("Mit AlarmKit-Wecker",isOn:$alarm);Text("Der Wecker wird auf dem anderen iPhone beim nächsten Öffnen der App synchronisiert. Plant wichtige Termine im Voraus.").font(.caption)}
            Section("Apple-Apps"){Toggle("In Apple Kalender synchronisieren",isOn:$calendar);Toggle("In Apple Erinnerungen synchronisieren",isOn:$reminder)}
        }.scrollDismissesKeyboard(.interactively).navigationTitle(initial == nil ? "Zeit für uns":"Unseren Plan bearbeiten").toolbar{
            ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)}
            ToolbarItem(placement:.confirmationAction){Button(saving ? "Speichere …":"Speichern"){
                saving=true;Task{
                    if calendar{_ = await app.calendar.requestAccess()};if reminder{_ = await app.calendar.requestReminderAccess()}
                    var payload=initial?.payload ?? RecordPayload();payload.title=title;payload.recurrence=yearly ? "yearly":"none";payload.alarmEnabled=alarm;payload.reminderSync=reminder
                    let kind=initial?.kind ?? .calendar
                    if kind == .reminder {payload.dueAt=start.rjISO8601;payload.message=notes}
                    else {payload.startAt=start.rjISO8601;payload.calendarSync=calendar;if kind == .calendar{payload.endAt=max(end,start.addingTimeInterval(60)).rjISO8601;payload.notes=notes}else{payload.text=notes}}
                    if let saved=await app.saveRecord(id:initial?.id,kind:kind,payload:payload){onSaved?(saved);dismiss()};saving=false
                }
            }.disabled(saving || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        }.interactiveDismissDisabled(saving).onAppear{title=initial?.payload.title ?? "";notes=initial?.payload.notes ?? initial?.payload.text ?? initial?.payload.message ?? "";start=(initial?.payload.startAt ?? initial?.payload.dueAt)?.rjDate ?? initialDate;end=max(initial?.payload.endAt?.rjDate ?? start.addingTimeInterval(3600),start);yearly=initial?.payload.recurrence=="yearly";alarm=initial?.payload.alarmEnabled ?? false;reminder=initial?.payload.reminderSync ?? true;calendar=initial?.payload.calendarSync ?? true}
            .onChange(of:start){_,value in if end<value{end=value.addingTimeInterval(3600)}}
        }
    }
}
struct ThoughtHistoryView:View {
    @Environment(AppState.self) private var app
    @State private var history:[ThoughtEvent]=[]
    var body:some View {ScrollView{LazyVStack(alignment:.leading,spacing:15){
        Text("Jeder Tipp ein kleines Ich-liebe-dich.").font(.system(size:30,weight:.medium,design:.serif)).padding(.bottom,10)
        Text("Frühere Tageszähler bleiben erhalten. Einzelne Uhrzeiten werden ab Version 3.0 aufgezeichnet; bei älteren Gedanken sind sie unbekannt.").font(.footnote).foregroundStyle(.secondary)
        ForEach(history){event in HStack(alignment:.top,spacing:14){Image(systemName:"heart.fill").foregroundStyle(event.userID==app.me?.id ? LovePalette.cyan:LovePalette.pink).font(.title2);VStack(alignment:.leading,spacing:7){Text(event.userID==app.me?.id ? "Du denkst an deinen Lieblingsmenschen":"\(app.partner?.displayName ?? "Schatzi") denkt an dich").font(.headline);if let date=event.occurredAt?.rjDate{Text(date.formatted(.dateTime.day().month(.wide).year().hour().minute().second())).font(.subheadline.monospacedDigit())}else{Text("Nachgesendeter Gedanke · ursprüngliche Uhrzeit unbekannt").font(.caption)};if let date=event.receivedAt.rjDate{Text("Am Server angekommen: "+date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.caption2).foregroundStyle(.secondary)}};Spacer()}.loveCard()}
        if history.isEmpty{ContentUnavailableView("Das nächste Herz wartet",systemImage:"heart.fill")}
    }.padding(22)}.background(LoveBackground()).navigationTitle("Herzgedanken").onChange(of:app.thoughtHistory){_,events in var merged=Dictionary(uniqueKeysWithValues:history.map{($0.id,$0)});for event in events{merged[event.id]=event};history=merged.values.sorted{$0.receivedAt>$1.receivedAt}}.task{history=app.thoughtHistory;do{history=try await app.api.thoughtArchive()}catch{app.alert=AppAlert(title:"Herzarchiv",message:error.localizedDescription)}}}
}

