import SwiftUI

struct EveningRitualView:View {
    @Environment(AppState.self) private var app
    let day:Date
    @State private var composing=false
    @State private var deleting:SharedRecord?
    init(day:Date = .now){self.day=day}
    private var contributions:[SharedRecord]{app.records.filter{$0.kind == .ritual && $0.payload.day==JournalDates.key(day)}.sorted{$0.ownerID<$1.ownerID}}
    private var mine:SharedRecord?{contributions.first{$0.ownerID==app.me?.id}}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:20) {
                HStack(spacing:12){Image(systemName:"moon.stars.fill").font(.system(size:38)).foregroundStyle(LovePalette.violet);Image(systemName:"heart.fill").font(.system(size:24)).foregroundStyle(LovePalette.pink);Spacer();Text(day.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)}
                LoveEyebrow(text:"Zwei Minuten. Nur für euch.")
                Text("Drei kleine Dinge.\nEin großes Wir.").font(.system(size:34,weight:.medium,design:.serif))
                Text("Was war schön? Wofür bist du dankbar? Worauf freust du dich mit deinem Lieblingsmenschen? Ein kleines Ritual, das eure guten Momente bewahrt.").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing:14){ForEach(0..<2){index in Image(systemName:index<contributions.count ? "heart.fill":"heart").font(.system(size:30)).foregroundStyle(index<contributions.count ? LovePalette.pink:LovePalette.violet.opacity(0.35))};Text("\(contributions.count) von 2 Beiträgen").font(.caption.bold()).foregroundStyle(.secondary)}
                Text("Keine Pflicht, kein Punktestand. Eure Beiträge sind sofort füreinander sichtbar und nur innerhalb eures Paars gespeichert.").font(.caption).foregroundStyle(.secondary)
                Button(mine==nil ? "Meinen Abendmoment teilen":"Meinen Beitrag bearbeiten",systemImage:"square.and.pencil"){composing=true}.buttonStyle(.glassProminent).controlSize(.large)
            }.loveCard()
            if contributions.isEmpty {ContentUnavailableView("Euer erster kleiner Abendmoment",systemImage:"sparkles",description:Text("Ein Satz pro Feld reicht. Ein kleines Danke kann einen ganzen Tag wärmer machen."))}
            ForEach(contributions){record in
                VStack(alignment:.leading,spacing:16){HStack{Text(record.ownerID==app.me?.id ? "Dein Abendmoment":app.partner?.displayName ?? "Dein Lieblingsmensch").font(.headline);Spacer();if record.ownerID==app.me?.id{Menu{Button("Bearbeiten",systemImage:"pencil"){composing=true};Button("Meinen Beitrag löschen",systemImage:"trash",role:.destructive){deleting=record}}label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Abendmoment verwalten")}};JournalRecordDetail(record:record)}.loveCard()
            }
            Text("Im Tagesrückblick bleiben eure Antworten beim jeweiligen Tag. Ihr könnt jederzeit zurückblättern.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Unser Abendritual").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$composing){RitualComposer(day:day,existing:mine)}
        .alert("Deinen Abendmoment löschen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Löschen",role:.destructive){if let record=deleting{Task{_ = await app.deleteRecord(record)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}
        .task{await app.loadRecordArchive(kind:.ritual)}
        .refreshable{await app.loadRecordArchive(kind:.ritual)}
    }
}
private struct RitualComposer:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let day:Date
    let existing:SharedRecord?
    @State private var beautiful=""
    @State private var thanks=""
    @State private var tomorrow=""
    @State private var saving=false
    @State private var saved=false
    @State private var loaded=false
    @State private var recordID=UUID().uuidString
    private var draftKey:String{"rjlove.ritual-draft."+(app.profile?.baseURL ?? "")+"."+(app.me?.id ?? "")+"."+JournalDates.key(day)}
    private var fields:[String]{[beautiful,thanks,tomorrow]}
    private var valid:Bool{fields.allSatisfy{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=1200}}
    var body:some View {
        NavigationStack {
            Form {
                Section {Text("Ein paar ehrliche Worte sind genug.").font(.system(.title2,design:.serif));Text(day.formatted(date:.long,time:.omitted)).font(.caption).foregroundStyle(.secondary)}
                Section("Ein schöner Moment heute"){TextField("Das möchte ich behalten …",text:$beautiful,axis:.vertical).lineLimit(3...6)}
                Section("Ein kleines Danke an dich"){TextField("Heute danke ich dir für …",text:$thanks,axis:.vertical).lineLimit(3...6)}
                Section("Darauf freue ich mich mit dir"){TextField("Morgen oder irgendwann …",text:$tomorrow,axis:.vertical).lineLimit(3...6)}
                Section {Text("Dein Lieblingsmensch kann deinen gespeicherten Beitrag direkt lesen. Du kannst deinen eigenen Beitrag später ändern oder löschen.").font(.caption).foregroundStyle(.secondary)}
            }.navigationTitle("Mein Abendmoment").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Später"){dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction){Button("Teilen"){Task{await save()}}.disabled(!valid || saving)}}
            .onAppear {
                guard !loaded else{return};loaded=true
                if let draft=UserDefaults.standard.stringArray(forKey:draftKey),draft.count==3 {beautiful=draft[0];thanks=draft[1];tomorrow=draft[2]}
                else if let existing{beautiful=existing.payload.text ?? "";thanks=existing.payload.message ?? "";tomorrow=existing.payload.notes ?? ""}
                if let existing{recordID=existing.id}
            }
            .onChange(of:fields){_,value in if loaded,!saved {UserDefaults.standard.set(value,forKey:draftKey)}}
        }.interactiveDismissDisabled(saving)
    }
    private func save() async {
        saving=true;defer{saving=false}
        var payload=RecordPayload(title:"Drei kleine Dinge für uns",text:beautiful.trimmingCharacters(in:.whitespacesAndNewlines),message:thanks.trimmingCharacters(in:.whitespacesAndNewlines),startAt:Calendar.current.startOfDay(for:day).rjISO8601,notes:tomorrow.trimmingCharacters(in:.whitespacesAndNewlines));payload.day=JournalDates.key(day)
        if await app.saveRecord(id:recordID,kind:.ritual,payload:payload) != nil {saved=true;UserDefaults.standard.removeObject(forKey:draftKey);dismiss()}
    }
}
