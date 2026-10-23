import AVKit
import SwiftUI

private enum EveningOwner:String,CaseIterable {case both="Wir beide",mine="Nur meine",partner="Nur deine"}
struct EveningPlaylistView:View {
    @Environment(AppState.self) private var app
    @State private var video=false
    @State private var owner:EveningOwner = .both
    @State private var shuffle=false
    @State private var loading=false
    @State private var error:String?
    @State private var available:[EveningTrack]=[]
    @State private var scrollRequest=UUID()
    private var playback:EveningPlaylistService{.shared}
    init(initialVideo:Bool=false){_video=State(initialValue:initialVideo)}
    private var filtered:[EveningTrack]{available.filter{track in track.isVideo==video && (owner == .both || (owner == .mine ? track.ownerID==app.me?.id:track.ownerID==app.partner?.id))}.sorted{$0.date == $1.date ? $0.id<$1.id:$0.date<$1.date}}
    var body:some View {
        ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:22){
            VStack(alignment:.leading,spacing:14){LoveEyebrow(text:"Ein Abend. Unser Soundtrack.");HStack{Text("Bleib noch\nein bisschen.").font(.system(size:34,weight:.medium,design:.serif));Spacer();LoveIcon(symbol:"moon.stars.fill",tint:LovePalette.violet,size:64)};Text("Eure Aufnahmen und Filme vom Server, einer nach dem anderen. Macht es euch gemütlich.").font(.subheadline).foregroundStyle(.secondary)}.loveCard()
            if playback.active{EveningNowPlayingView().id("evening-player")}
            VStack(alignment:.leading,spacing:16){
                Picker("Abendprogramm",selection:$video){Text("Duftkonzert").tag(false);Text("Unsere Filme").tag(true)}.pickerStyle(.segmented).accessibilityIdentifier("evening-content")
                Picker("Von wem?",selection:$owner){Text("Wir beide gemixt").tag(EveningOwner.both);Text("Nur meine").tag(EveningOwner.mine);Text("Nur von "+(app.partner?.displayName ?? "Schatzi")).tag(EveningOwner.partner)}
                Toggle("Zufällige Reihenfolge",isOn:$shuffle)
                HStack{Label("\(filtered.count) Beiträge",systemImage:video ? "film.stack":"waveform").font(.caption);Spacer();if loading{ProgressView()}}
                Button{playback.start(shuffle ? filtered.shuffled():filtered,api:app.api);scrollRequest=UUID()}label:{Label(playback.active ? "Neue Auswahl starten":"Abend starten",systemImage:"play.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).controlSize(.large).disabled(loading || filtered.isEmpty || app.studio.hasRecording).accessibilityIdentifier("evening-start")
                Text("Geladen wird das vollständige Serverarchiv, auch ohne lokale Kopien. Die nächsten Beiträge werden vorab gepuffert. Internet bleibt nötig; die Wiedergabe läuft beim Verlassen der Ansicht weiter.").font(.caption).foregroundStyle(.secondary)
            }.loveCard()
            if let error{Text(error).font(.footnote).foregroundStyle(.orange);Button("Archiv erneut laden"){Task{await load()}}.buttonStyle(.bordered)}
            if !loading,filtered.isEmpty,error==nil {ContentUnavailableView("Euer Abend wartet noch",systemImage:video ? "film":"waveform",description:Text(video ? "Teilt ein Video unter Momente oder wählt eine andere Person.":"Teilt eine Duftaufnahme oder wählt eine andere Person."))}
            ForEach(Array(filtered.enumerated()),id:\.element.id){i,track in HStack(spacing:12){Text("\(i+1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:26);Image(systemName:track.isVideo ? "film.fill":"waveform").foregroundStyle(LovePalette.violet);VStack(alignment:.leading,spacing:4){Text(track.title).font(.subheadline.bold()).lineLimit(2);Text((track.ownerID==app.me?.id ? "Du":app.partner?.displayName ?? "Schatzi")+" · "+track.date.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)};Spacer();Button{playback.start(filtered,api:app.api,from:i);scrollRequest=UUID()}label:{Image(systemName:"play.circle.fill").font(.title2)}.accessibilityLabel("Abspielen ab "+track.title)}.loveCard()}
        }.padding(20)}.background(LoveBackground()).navigationTitle("Euer Abend").navigationBarTitleDisplayMode(.inline).task{await load()}.refreshable{await load()}
        .onChange(of:scrollRequest){_,_ in Task{try? await Task.sleep(for:.milliseconds(120));withAnimation(.smooth){proxy.scrollTo("evening-player",anchor:.top)}}}
        }
    }
    private func load() async {
        loading=true;error=nil;defer{loading=false}
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview"),!ProcessInfo.processInfo.arguments.contains("--ui-test-server"){available=app.farts.map(EveningTrack.init)+app.records.compactMap(EveningTrack.init);return}
        #endif
        do {let clips=try await app.api.loadFartArchive();let moments=try await app.api.recordArchive(kind:.moment);try Task.checkCancellation();available=clips.map(EveningTrack.init)+moments.compactMap(EveningTrack.init)}catch{if !Task.isCancelled{self.error=error.localizedDescription}}
    }
}
private struct EveningNowPlayingView:View {
    @Environment(AppState.self) private var app
    @State private var playback=EveningPlaylistService.shared
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Label("Jetzt für euch",systemImage:"headphones").font(.caption.bold()).foregroundStyle(LovePalette.pink);Spacer();Text("\(playback.index+1) / \(playback.tracks.count)").font(.caption.monospacedDigit())}
            if let current=playback.current {
                Text(current.title).font(.title2.bold()).lineLimit(3).accessibilityIdentifier("evening-current-title")
                Text(current.ownerID==app.me?.id ? "Von dir":"Von "+(app.partner?.displayName ?? "Schatzi")).font(.caption).foregroundStyle(.secondary)
                if current.isVideo,let player=playback.player {VideoPlayer(player:player).frame(height:220).clipShape(RoundedRectangle(cornerRadius:20))}
                else {Image(systemName:"waveform").font(.system(size:70)).foregroundStyle(LovePalette.violet.gradient).frame(maxWidth:.infinity).frame(height:100)}
            }
            if playback.duration>0 {Slider(value:Binding(get:{playback.elapsed},set:{playback.seek($0)}),in:0...max(1,playback.duration)).accessibilityLabel("Wiedergabeposition");HStack{Text(clock(playback.elapsed));Spacer();Text(clock(playback.duration))}.font(.caption.monospacedDigit()).foregroundStyle(.secondary)}
            HStack(spacing:28){Spacer();Button{playback.previous()}label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Vorheriger Beitrag");Button{playback.toggle()}label:{Image(systemName:playback.playing ? "pause.circle.fill":"play.circle.fill").font(.system(size:50))}.accessibilityLabel(playback.playing ? "Pausieren":"Fortsetzen");Button{playback.next()}label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("Nächster Beitrag");Spacer()}.font(.title2)
            if playback.preparing{ProgressView("Der nächste Beitrag wird vorbereitet …").font(.caption)}
            if let error=playback.error {Text(error).font(.caption).foregroundStyle(.orange);HStack{Button("Erneut laden"){playback.retry()};Button("Überspringen"){playback.next()}}.buttonStyle(.bordered)}
            HStack{Menu{Button("Aus"){playback.setSleep(minutes:0)};ForEach([15,30,45,60],id:\.self){minutes in Button("\(minutes) Minuten"){playback.setSleep(minutes:minutes)}}}label:{Label(playback.sleepUntil.map{"Pause um "+$0.formatted(date:.omitted,time:.shortened)} ?? "Einschlaftimer",systemImage:"moon.zzz")};Spacer();Button("Beenden",role:.destructive){playback.stop()}}.font(.caption)
            Text("Originalton · Mit Steuerung auf dem Sperrbildschirm. Bei Anrufen oder getrennten Kopfhörern pausiert der Player.").font(.caption2).foregroundStyle(.secondary)
        }.loveCard()
    }
    private func clock(_ seconds:Double)->String {let value=Int(max(0,seconds));return String(format:"%d:%02d",value/60,value%60)}
}
struct EveningPlayerHomeCard:View {
    private var playback:EveningPlaylistService{.shared}
    var body:some View {HStack(spacing:14){NavigationLink{EveningPlaylistView(initialVideo:playback.current?.isVideo ?? false)}label:{HStack{LoveIcon(symbol:"headphones",tint:LovePalette.violet);VStack(alignment:.leading,spacing:5){Text("Euer Abend läuft").font(.caption.bold()).foregroundStyle(.secondary);Text(playback.current?.title ?? "Wird vorbereitet …").font(.subheadline.bold()).lineLimit(1)}}}.buttonStyle(.plain);Spacer();Button{playback.toggle()}label:{Image(systemName:playback.playing ? "pause.fill":"play.fill").font(.title2)}.accessibilityLabel(playback.playing ? "Abend pausieren":"Abend fortsetzen")}.loveCard()}
}
