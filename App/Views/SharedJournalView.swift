import SwiftUI

struct SharedJournalView:View {
    @Environment(AppState.self) private var app
    @State private var day:Date
    @State private var feed:Bool
    @State private var page:JournalPage?
    @State private var loading=false
    @State private var error:String?
    @State private var selected:SharedActivityItem?
    init(initialDay:Date = .now,showFeed:Bool=false){_day=State(initialValue:initialDay);_feed=State(initialValue:showFeed)}
    private var cal:Calendar {.current}
    private var items:[SharedActivityItem] {feed ? Array(SharedActivityItem.make(records:app.records,farts:app.farts).prefix(100)):SharedActivityItem.make(records:page?.records ?? [],farts:page?.farts ?? [])}
    var body:some View {
        ScrollView {LazyVStack(alignment:.leading,spacing:22) {
            Picker("Unser Journal",selection:$feed){Text("Tagesansicht").tag(false);Text("Neuigkeiten").tag(true)}.pickerStyle(.segmented)
            if !feed {
                dayNavigation
                if loading{ProgressView("Euer Tag wird zusammengestellt …").frame(maxWidth:.infinity).padding(30)}
                else if let error {ContentUnavailableView("Tag gerade nicht geladen",systemImage:"wifi.exclamationmark",description:Text(error));Button("Erneut versuchen"){Task{await load()}}.buttonStyle(.glass)}
                else if let page {summary(page);NavigationLink{AIDaySummaryView(day:day)}label:{Label("Unsere Momente mit KI zusammenfassen",systemImage:"sparkles").frame(maxWidth:.infinity)}.buttonStyle(.glass)}
                if !loading,error==nil {NavigationLink{EveningRitualView(day:day)}label:{Label("Ein kleiner Abendmoment für uns",systemImage:"moon.stars.fill").frame(maxWidth:.infinity)}.buttonStyle(.glassProminent)}
            }else{
                VStack(alignment:.leading,spacing:10){LoveEyebrow(text:"Was bei euch passiert");Text("Unser Leben,\nganz nebenbei.").font(.system(size:32,weight:.medium,design:.serif));Text("Die neuesten synchronisierten Beiträge: Fotos, Worte, Wünsche und kleine Meisterwerke. Tippe einen Moment an, um mehr zu sehen.").font(.subheadline).foregroundStyle(.secondary)}.loveCard()
            }
            if feed || (!loading && error==nil) {
                Text(feed ? "Neu bei euch":"Die kleinen Kapitel dieses Tages").font(.title3.bold())
                if items.isEmpty {ContentUnavailableView("Ein leises Kapitel",systemImage:"heart.text.square",description:Text("Hier ist noch kein geteilter Beitrag gespeichert. Ihr müsst nichts leisten, um einen schönen Tag zu haben."))}
                ForEach(items){item in Button{selected=item}label:{activityRow(item)}.buttonStyle(.lovePress)}
                Text("Nur gespeicherte Inhalte eurer App. Keine vollständige Aufzeichnung eures Tages und keine ausgedachte Stimmung. Aufnahmezeiten richten sich nach der Zeitzone dieses iPhones.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(20)}.background(LoveBackground()).navigationTitle(feed ? "Unser Feed":"Unser Tag").navigationBarTitleDisplayMode(.inline)
        .task(id:cal.startOfDay(for:day)){await load()}
        .refreshable{_ = await app.syncNow(showErrors:false);await load()}
        .sheet(item:$selected){item in NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){if let clip=item.clip{FartClipCard(clip:clip)}else if let record=item.record{JournalRecordDetail(record:record)}}.padding(20)}.background(LoveBackground()).navigationTitle("Ein Moment von euch").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){selected=nil}}}}}
    }
    private var dayNavigation:some View {
        HStack {
            Button{move(-1)}label:{Image(systemName:"chevron.left").frame(width:42,height:42)}.accessibilityLabel("Vorheriger Tag")
            Spacer(minLength:0)
            DatePicker("Tag",selection:$day,in:...Date.now,displayedComponents:.date).labelsHidden()
            Spacer(minLength:0)
            Button{move(1)}label:{Image(systemName:"chevron.right").frame(width:42,height:42)}.disabled(cal.isDateInToday(day)).accessibilityLabel("Nächster Tag")
            Button("Heute"){day = .now}.font(.caption.bold())
        }
    }
    private func move(_ delta:Int){if let date=cal.date(byAdding:.day,value:delta,to:day){day=date}}
    private func load() async {
        let requestedDay=cal.startOfDay(for:day);loading=true;error=nil;page=nil
        do {let result=try await app.api.journal(day:requestedDay);guard !Task.isCancelled,cal.isDate(day,inSameDayAs:requestedDay) else{return};page=result;loading=false}
        catch {guard !Task.isCancelled,cal.isDate(day,inSameDayAs:requestedDay) else{return};self.error=error.localizedDescription;loading=false}
    }
    private func summary(_ value:JournalPage)->some View {
        let photos=(value.counts["instant"] ?? 0)+(value.counts["moment"] ?? 0)
        let hearts=value.hearts.values.reduce(0,+)
        let words=value.counts["chat"] ?? 0
        return VStack(alignment:.leading,spacing:18) {
            LoveEyebrow(text:day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            HStack(alignment:.top){VStack(alignment:.leading,spacing:8){Text(cal.isDateInToday(day) ? "So war unser Tag.":"Ein Tag aus unserem Wir.").font(.system(size:32,weight:.medium,design:.serif));Text(value.counts.values.reduce(0,+)+hearts>0 ? "Kleine Dinge, die zusammen etwas Schönes ergeben.":"Auch ein ruhiger Tag ist ein Teil eurer Geschichte.").font(.subheadline).foregroundStyle(.secondary)};Spacer(minLength:0);Image(systemName:"moon.stars.fill").font(.system(size:38)).foregroundStyle(LovePalette.violet.gradient)}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){stat(photos,"Fotomomente","camera.fill",LovePalette.pink);stat(hearts,"Herzgedanken","heart.fill",LovePalette.coral);stat(words,"Nachrichten","bubble.left.fill",LovePalette.cyan);stat(value.counts["farts"] ?? 0,"Duftpost","cloud.fill",LovePalette.violet)}
            HStack{person(app.me?.id ?? "",app.me?.displayName ?? "Du",value);Spacer();person(app.partner?.id ?? "",app.partner?.displayName ?? "Dein Lieblingsmensch",value)}
            Text("Nachrichten zählen gespeicherte Beiträge; Herzgedanken werden nach ihrem Ereigniszeitpunkt zugeordnet. Ältere tägliche Herzzähler ohne Einzelereignisse lassen sich nicht nachträglich rekonstruieren.").font(.caption2).foregroundStyle(.secondary)
        }.loveCard()
    }
    private func person(_ id:String,_ name:String,_ value:JournalPage)->some View {
        VStack(alignment:.leading,spacing:6){Text(name).font(.subheadline.bold());Text("\(value.hearts[id] ?? 0) Herzen · \(value.records.filter{$0.ownerID==id && [.instant,.moment].contains($0.kind)}.count) Fotos").font(.caption).foregroundStyle(.secondary)}
    }
    private func stat(_ count:Int,_ title:String,_ symbol:String,_ tint:Color)->some View {
        VStack(alignment:.leading,spacing:8){Image(systemName:symbol).font(.title3).foregroundStyle(tint);Text(count.formatted()).font(.system(size:30,weight:.semibold,design:.rounded));Text(title).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(tint.opacity(0.09),in:RoundedRectangle(cornerRadius:20))
    }
    private func activityRow(_ item:SharedActivityItem)->some View {
        HStack(alignment:.top,spacing:14){Image(systemName:item.symbol).font(.title3).foregroundStyle(item.owner==app.me?.id ? LovePalette.pink:LovePalette.violet).frame(width:42,height:42).background(.thinMaterial,in:RoundedRectangle(cornerRadius:14));VStack(alignment:.leading,spacing:6){HStack{Text(item.owner==app.me?.id ? "Du":app.partner?.displayName ?? "Dein Lieblingsmensch").font(.caption.bold()).foregroundStyle(.secondary);Spacer();Text(item.date.formatted(date:feed ? .abbreviated:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary)};Text(item.title).font(.headline);if !item.text.isEmpty{Text(item.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)}};Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)}.loveCard()
    }
}
struct JournalRecordDetail:View {
    let record:SharedRecord
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            if record.kind == .instant || record.kind == .moment || record.payload.assetIDs?.isEmpty == false {MediaAttachmentView(record:record);PhotoPlaceView(payload:record.payload)}
            Text(record.payload.title ?? record.payload.caption ?? "Ein Moment für uns").font(.system(size:28,weight:.medium,design:.serif))
            if record.kind == .ritual {
                part("Mein schöner Moment",record.payload.text);part("Danke an dich",record.payload.message);part("Darauf freue ich mich",record.payload.notes)
            }else if let text=record.payload.text,!text.isEmpty{Text(text).textSelection(.enabled)}
            if let date=JournalDates.date(record){Text(date.formatted(date:.long,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
        }.loveCard()
    }
    private func part(_ title:String,_ value:String?)->some View {VStack(alignment:.leading,spacing:8){Text(title).font(.caption.bold()).foregroundStyle(LovePalette.violet);Text(value ?? "").textSelection(.enabled)}}
}
struct DailyJournalHomeCard:View {
    @Environment(AppState.self) private var app
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            NavigationLink{SharedJournalView()}label:{HStack{Image(systemName:Calendar.current.component(.hour,from:.now)>=19 ? "moon.stars.fill":"sun.max.fill").font(.title2).foregroundStyle(LovePalette.pink);VStack(alignment:.leading,spacing:5){Text(Calendar.current.component(.hour,from:.now)>=19 ? "Euer Abendrückblick ist da":"Heute schreiben wir Geschichte.").font(.headline);Text("Tagesübersicht, kleine Momente und euer Feed").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").font(.caption)}}.buttonStyle(.lovePress)
            HStack {NavigationLink{SharedJournalView(showFeed:true)}label:{Label("Neuigkeiten",systemImage:"sparkles.rectangle.stack")};Spacer();NavigationLink{EveningRitualView()}label:{Label("Unser Ritual",systemImage:"moon.stars")}}.font(.caption.bold()).buttonStyle(.glass)
        }.loveCard()
    }
}
