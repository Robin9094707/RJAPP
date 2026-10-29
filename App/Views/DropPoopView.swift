import CoreLocation
import SwiftUI

struct DropPoopView:View {
    @Environment(AppState.self) private var app
    var openComposer=false
    @State private var adding=false
    @State private var editor:SharedRecord?
    @State private var selected:SharedRecord?
    @State private var map=false
    @State private var owner="all"
    @State private var didOpen=false
    private var entries:[SharedRecord]{app.records.filter{$0.kind == .poop && (owner=="all" || (owner=="mine" ? $0.ownerID==app.me?.id:$0.ownerID==app.partner?.id))}.sorted{($0.payload.capturedAt ?? $0.createdAt)>($1.payload.capturedAt ?? $1.createdAt)}}
    private var pins:[SharedPlacePin]{entries.compactMap{r in guard let a=r.payload.latitude,let b=r.payload.longitude else{return nil};return SharedPlacePin(id:r.id,title:r.payload.title ?? "Thronbesteigung",subtitle:r.payload.location ?? "Ein stilles Örtchen",latitude:a,longitude:b,glyph:r.payload.emoji ?? "💩",mine:r.ownerID==app.me?.id)}}
    var body:some View {
        ScrollView{LazyVStack(alignment:.leading,spacing:20){
            VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading,spacing:8){LoveEyebrow(text:"Ein stilles Örtchen. Große Geschichten.");Text("Drop-Poop.").font(.system(size:38,weight:.medium,design:.serif))};Spacer();Text("💩").font(.system(size:68))};Text("Euer privates Thronarchiv. Für die großen und kleinen Geschäfte des Lebens.").font(.subheadline).foregroundStyle(.secondary);HStack{Label("\(entries.count) Thronbesteigungen",systemImage:"toilet.fill");Spacer();Text("\(entries.compactMap{$0.payload.duration}.reduce(0,+)) Min. Sitzfleisch")}.font(.caption.bold())}.loveCard()
            Button{adding=true}label:{Label("Hier wurde Geschichte geschrieben",systemImage:"plus.circle.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("poop-add")
            Picker("Ansicht",selection:$map){Text("Thronchronik").tag(false);Text("Kack-Karte").tag(true)}.pickerStyle(.segmented).accessibilityIdentifier("poop-mode")
            Picker("Von wem?",selection:$owner){Text("Wir beide").tag("all");Text("Nur meine").tag("mine");Text("Nur von "+(app.partner?.displayName ?? "Schatzi")).tag("partner")}
            if map {
                if pins.isEmpty{ContentUnavailableView("Noch keine Duftmarke auf der Karte",systemImage:"map",description:Text("Nur Einträge mit bewusst geteiltem Ort erscheinen hier."))}
                else {SharedPlacesMap(pins:pins){id in selected=entries.first{$0.id==id}}.frame(height:430).clipShape(RoundedRectangle(cornerRadius:24));Text("Rosa: du · Lila: dein Lieblingsmensch · \(entries.count-pins.count) Einträge ohne geteilten Ort").font(.caption).foregroundStyle(.secondary)}
            }else{
                if entries.isEmpty{ContentUnavailableView("Euer Thron wartet",systemImage:"toilet.fill",description:Text("Kein Wettbewerb. Nur ein bisschen gemeinsamer Quatsch."))}
                ForEach(entries){r in Button{selected=r}label:{row(r)}.buttonStyle(.lovePress)}
            }
            Text("Privat auf eurem Server. Ein Ort wird nur gespeichert, wenn du ihn im Eintrag übernimmst. Keine automatische Erfassung.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Drop-Poop").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$adding){PoopEntryEditor(initial:nil)}
        .sheet(item:$editor){PoopEntryEditor(initial:$0)}
        .sheet(item:$selected){record in PoopEntryDetail(record:record)}
        .task{if openComposer,!didOpen{didOpen=true;adding=true};await app.loadRecordArchive(kind:.poop)}
        .refreshable{await app.loadRecordArchive(kind:.poop)}
    }
    private func row(_ r:SharedRecord)->some View {
        HStack(alignment:.top,spacing:14){Text(r.payload.emoji ?? "💩").font(.system(size:38));VStack(alignment:.leading,spacing:7){Text(r.payload.title ?? "Thronbesteigung").font(.headline);Text((r.ownerID==app.me?.id ? "Du":app.partner?.displayName ?? "Schatzi")+" · "+((r.payload.capturedAt ?? r.createdAt).rjDate?.formatted(date:.abbreviated,time:.shortened) ?? "")).font(.caption).foregroundStyle(.secondary);if let place=r.payload.location,!place.isEmpty{Label(place,systemImage:"mappin.circle").font(.caption)};Text("\(r.payload.duration ?? 0) Min. · Legendenstufe \(r.payload.rating ?? 1)/5").font(.caption).foregroundStyle(LovePalette.violet)};Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)}.loveCard()
    }
}
private struct PoopEntryDetail:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record:SharedRecord
    @State private var editing=false
    @State private var deleting=false
    private var current:SharedRecord{app.records.first{$0.id==record.id} ?? record}
    var body:some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){Text(current.payload.emoji ?? "💩").font(.system(size:80)).frame(maxWidth:.infinity);Text(current.payload.title ?? "Thronbesteigung").font(.largeTitle.bold());Text(current.payload.text ?? "");Text("\(current.payload.duration ?? 0) Minuten · Legendenstufe \(current.payload.rating ?? 1)/5").font(.subheadline);if let date=current.payload.capturedAt?.rjDate{Text(date.formatted(date:.long,time:.shortened)).font(.caption).foregroundStyle(.secondary)};if let place=current.payload.location,!place.isEmpty{Label(place,systemImage:"toilet.fill")};if let a=current.payload.latitude,let b=current.payload.longitude{SharedPlacesMap(pins:[SharedPlacePin(id:current.id,title:current.payload.title ?? "Stilles Örtchen",subtitle:"",latitude:a,longitude:b,glyph:current.payload.emoji ?? "💩",mine:current.ownerID==app.me?.id)]){_ in}.frame(height:270).clipShape(RoundedRectangle(cornerRadius:22))};if current.ownerID==app.me?.id{Button("Eintrag bearbeiten",systemImage:"pencil"){editing=true}.buttonStyle(.bordered);Button("Eintrag löschen",role:.destructive){deleting=true}}}.padding(22)}.background(LoveBackground()).navigationTitle("Ein stilles Kapitel").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){dismiss()}}}.sheet(isPresented:$editing){PoopEntryEditor(initial:current)}.confirmationDialog("Diesen Eintrag für euch beide löschen?",isPresented:$deleting,titleVisibility:.visible){Button("Löschen",role:.destructive){Task{if await app.deleteRecord(current){dismiss()}}};Button("Behalten",role:.cancel){}}}}
}
struct PoopEntryEditor:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let initial:SharedRecord?
    @State private var id=UUID().uuidString
    @State private var title="Kleine Thronbesteigung"
    @State private var text=""
    @State private var place=""
    @State private var date=Date.now
    @State private var minutes=5
    @State private var rating=3
    @State private var emoji="💩"
    @State private var includePlace=false
    @State private var saving=false
    @StateObject private var location=EntryPointCapture()
    var body:some View {NavigationStack{Form{
        Section{HStack{Text(emoji).font(.system(size:52));VStack(alignment:.leading,spacing:6){Text("Ein Geschäft unter Vertrauten").font(.headline);Text("Nur für euch zwei. Versprochen.").font(.caption).foregroundStyle(.secondary)}}}
        Section("Dein Thronbericht"){
            TextField("Titel",text:$title).accessibilityIdentifier("poop-title")
            Picker("Symbol",selection:$emoji){ForEach(["💩","🚽","🧻","👑","🌋"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
            DatePicker("Wann?",selection:$date,in:...Date.now)
            Stepper("\(minutes) Minuten Sitzfleisch",value:$minutes,in:0...180)
            Stepper("Legendenstufe \(rating) von 5",value:$rating,in:1...5)
            TextField("Ein paar legendäre Worte …",text:$text,axis:.vertical).lineLimit(3...6)
        }
        Section("Das stille Örtchen"){
            TextField("Name, z. B. Heimathafen",text:$place)
            Toggle("Ortsmarkierung mit Schatzi teilen",isOn:$includePlace)
            if includePlace {Button("Aktuellen Standort übernehmen",systemImage:"location.fill"){location.request()};if location.busy{ProgressView("Ort wird bestimmt …")};if location.coordinate != nil{Label("Aufnahmeort ist bereit",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}else{Text(location.error ?? "Übernimm deinen Standort bewusst. Ohne gültige Messung wird kein Ort gespeichert.").font(.caption).foregroundStyle(.secondary)}}
            Text("Der Ortsname funktioniert auch ohne Koordinaten. Ausschalten entfernt eine gespeicherte Ortsmarkierung beim Speichern.").font(.caption).foregroundStyle(.secondary)
        }
    }.navigationTitle(initial==nil ? "Drop setzen":"Thronbericht ändern").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction){Button(saving ? "Speichert …":"Eintragen"){Task{await save()}}.disabled(saving || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || title.count>80 || text.count>500 || place.count>80 || (includePlace && location.coordinate==nil)).accessibilityIdentifier("poop-save")}}.interactiveDismissDisabled(saving).onAppear{if let initial{id=initial.id;title=initial.payload.title ?? title;text=initial.payload.text ?? "";place=initial.payload.location ?? "";date=initial.payload.capturedAt?.rjDate ?? .now;minutes=initial.payload.duration ?? 5;rating=initial.payload.rating ?? 3;emoji=initial.payload.emoji ?? "💩";if let a=initial.payload.latitude,let b=initial.payload.longitude{location.coordinate=CLLocationCoordinate2D(latitude:a,longitude:b);includePlace=true}}}}
    }
    private func save() async {saving=true;defer{saving=false};var p=RecordPayload(title:title,text:text);p.location=place;p.capturedAt=date.rjISO8601;p.duration=minutes;p.rating=rating;p.emoji=emoji;if includePlace,let point=location.coordinate{p.latitude=point.latitude;p.longitude=point.longitude};if await app.saveRecord(id:id,kind:.poop,payload:p) != nil{dismiss()}}
}
@MainActor final class EntryPointCapture:NSObject,ObservableObject,CLLocationManagerDelegate {
    @Published var coordinate:CLLocationCoordinate2D?
    @Published var busy=false
    @Published var error:String?
    private let manager=CLLocationManager()
    override init(){super.init();manager.delegate=self;manager.desiredAccuracy=kCLLocationAccuracyBest}
    func request(){busy=true;error=nil;switch manager.authorizationStatus{case .notDetermined:manager.requestWhenInUseAuthorization();case .authorizedAlways,.authorizedWhenInUse:manager.requestLocation();default:busy=false;error="Bitte Standortzugriff in den iPhone-Einstellungen erlauben."}}
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager){if busy{switch manager.authorizationStatus{case .authorizedAlways,.authorizedWhenInUse:manager.requestLocation();case .denied,.restricted:busy=false;error="Standort wurde nicht erlaubt.";default:break}}}
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]){busy=false;guard let value=locations.last,value.horizontalAccuracy>=0,value.horizontalAccuracy<=500,abs(value.timestamp.timeIntervalSinceNow)<60 else{error="Noch kein verlässlicher Ort. Bitte erneut versuchen.";return};coordinate=value.coordinate}
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error){busy=false;self.error="Der Standort konnte nicht bestimmt werden. Bitte erneut versuchen."}
}
