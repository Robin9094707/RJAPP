import SwiftUI
import UniformTypeIdentifiers
struct FartLibraryView:View {
    @Environment(AppState.self) private var app
    @State private var query=""
    @State private var importing=false
    @State private var source:ImportSource?
    @State private var delete:SavedFart?
    @State private var sharing=false
    @State private var exportURL:URL?
    private var library:LocalFartStore{.shared}
    private var entries:[SavedFart]{library.clips.filter{query.isEmpty || ($0.clip.title+" "+$0.clip.caption+" "+$0.clip.category+" "+(($0.clip.date?.formatted(date:.numeric,time:.omitted)) ?? "")).localizedStandardContains(query)}}
    var body:some View {List{
        Section{Button("Vorhandenen Furz importieren",systemImage:"square.and.arrow.down"){importing=true};Text("Lokale Kopien sind unabhängig vom Server. Beim Löschen auf dem Server bleiben sie bewusst hier erhalten. Audio und Metadaten werden zusammen auf deinem iPhone gesichert.").font(.footnote).foregroundStyle(.secondary)}
        Section("Dein privates Konzert") {
            Picker("Soundart",selection:Binding(get:{app.studio.soundEffect},set:{app.studio.soundEffect=$0})){ForEach(FartSoundEffect.allCases){Text($0.rawValue).tag($0)}}
            HStack{Slider(value:Binding(get:{app.studio.playbackRate},set:{app.studio.playbackRate=$0}),in:0.25...3);Text(String(format:"%.2f×",app.studio.playbackRate)).font(.caption.monospacedDigit())}
            Menu("Playlist starten",systemImage:"play.square.stack") {
                Button("Alle gespeicherten"){app.studio.startPlaylist(entries.map(\.clip),api:app.api)}
                Button("Alle durcheinander"){app.studio.startPlaylist(entries.map(\.clip),api:app.api,shuffle:true)}
                Button("Nur meine"){app.studio.startPlaylist(entries.map(\.clip).filter{$0.ownerID==app.me?.id},api:app.api)}
                Button("Nur von meinem Lieblingsmenschen"){app.studio.startPlaylist(entries.map(\.clip).filter{$0.ownerID != app.me?.id},api:app.api)}
            }
            if app.studio.queueCount>0{HStack{Text("\(app.studio.queueIndex+1) / \(app.studio.queueCount)");Button("Weiter"){app.studio.nextInPlaylist()};Button("Stoppen"){app.studio.stopPlayback()}}}
        }
        Section("Auf diesem iPhone"){ForEach(entries){entry in VStack(alignment:.leading,spacing:9){Text(entry.clip.title).font(.headline);if let date=entry.clip.date{Text(date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.caption)};if entry.localOnly == true{Button("Gemeinsam teilen",systemImage:"paperplane.fill"){Task{await publish(entry)}}};HStack{Button(app.studio.playingID==entry.id ? "Stoppen":"Abspielen",systemImage:app.studio.playingID==entry.id ? "stop.fill":"play.fill"){if app.studio.playingID==entry.id{app.studio.stopPlayback()}else if let url=library.audioURL(id:entry.id){app.studio.playLocal(url:url,id:entry.id)}};Button{exportURL=library.audioURL(id:entry.id);sharing=true}label:{Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Exportieren");Spacer();Button(role:.destructive){delete=entry}label:{Image(systemName:"trash")}}.font(.caption)}}}
    }.searchable(text:$query,prompt:"Titel, Datum oder Duftnote").navigationTitle("Meine Duftschatzkiste").fileImporter(isPresented:$importing,allowedContentTypes:[.audio]){result in if case .success(let url)=result{source=ImportSource(url:url)}else if case .failure(let error)=result{app.alert=AppAlert(title:"Import",message:error.localizedDescription)}}.sheet(item:$source){FartImportView(source:$0.url)}.sheet(isPresented:$sharing){if let exportURL{FileShareView(urls:[exportURL])}}.alert("Lokale Kopie löschen?",isPresented:Binding(get:{delete != nil},set:{if !$0{delete=nil}})){Button("Nur lokale Kopie löschen",role:.destructive){if let entry=delete{do{app.studio.stopPlayback();try library.remove(entry)}catch{app.alert=AppAlert(title:"Lokales Löschen",message:error.localizedDescription)}};delete=nil};Button("Abbrechen",role:.cancel){delete=nil}}message:{Text("Die geteilte Aufnahme auf eurem Server bleibt erhalten.")}.onAppear{if let server=app.profile?.baseURL,let user=app.me?.id{library.configure(server:server,userID:user)}}}
    private func publish(_ entry:SavedFart) async {
        guard let file=library.audioURL(id:entry.id) else{return}
        do {let data=try Data(contentsOf:file);let clip=entry.clip
            let body=FartUpload(id:clip.id,title:clip.title,caption:clip.caption,category:clip.category,duration:clip.duration,waveform:clip.waveform,recordedAt:clip.recordedAt,location:clip.location,situation:clip.situation ?? "alltag",audioBase64:data.base64EncodedString())
            let saved=try await app.api.uploadFart(body);try library.saveImported(saved,data:data);await app.loadFartArchive()
        }catch{app.alert=AppAlert(title:"Duftpost teilen",message:error.localizedDescription)}
    }
}
private struct ImportSource:Identifiable {let id=UUID();let url:URL}
struct FartImportView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let source:URL
    @State private var audio:ImportedFartAudio?
    @State private var title=""
    @State private var caption=""
    @State private var date=Date.now
    @State private var category=FartCategory.allCases[0]
    @State private var saving=false
    @State private var error:String?
    @State private var localOnly=false
    var body:some View {NavigationStack{Form{
        TextField("Titel",text:$title);TextField("Notiz",text:$caption);DatePicker("Ursprünglich aufgenommen",selection:$date,in:...Date.now)
        Picker("Duftnote",selection:$category){ForEach(FartCategory.allCases){Text($0.emoji+" "+$0.rawValue).tag($0)}}
        Toggle("Nur auf diesem iPhone behalten",isOn:$localOnly)
        if let audio{Label(String(format:"%.1f Sekunden",audio.duration),systemImage:"waveform");Button("Vorschau"){app.studio.playLocal(url:audio.url,id:"import-preview")}}else if error==nil{ProgressView("Audio wird vorbereitet …")}
        Text("Audiodateien werden in M4A umgewandelt. Es werden höchstens die ersten 60 Sekunden übernommen. Das Datum kannst du vor dem Import anpassen. Ein unbekannter historischer Aufnahmeort wird nicht durch deinen heutigen Standort ersetzt.").font(.footnote).foregroundStyle(.secondary)
        if let error{Text(error).foregroundStyle(.orange)}
    }.navigationTitle("Ein Klassiker kehrt zurück").toolbar{ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction){Button("Importieren"){Task{await save()}}.disabled(audio==nil || saving || title.count>100 || caption.count>500)}}.task{
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}};title=source.deletingPathExtension().lastPathComponent
        date=(try? source.resourceValues(forKeys:[.creationDateKey]))?.creationDate ?? .now
        let name=source.deletingPathExtension().lastPathComponent
        if let regex=try? NSRegularExpression(pattern:"^(\\d{4}-\\d{2}-\\d{2})T(\\d{2})(\\d{2})(\\d{2})(\\.\\d+)?Z-"),let match=regex.firstMatch(in:name,range:NSRange(name.startIndex...,in:name)) {
            func group(_ index:Int)->String{guard let range=Range(match.range(at:index),in:name) else{return ""};return String(name[range])}
            if let original=(group(1)+"T"+group(2)+":"+group(3)+":"+group(4)+group(5)+"Z").rjDate{date=original}
        }
        if date > .now{date = .now}
        do{audio=try await ImportedFartAudio.prepare(source)}catch{self.error=error.localizedDescription}
    }.onDisappear{app.studio.stopPlayback();if let audio{try? FileManager.default.removeItem(at:audio.url)}}}
    }
    private func save() async {guard let audio,let user=app.me?.id else{return};saving=true;defer{saving=false};do{let data=try Data(contentsOf:audio.url);let id=UUID().uuidString;let clip:FartClip
        if localOnly{clip=FartClip(id:id,ownerID:user,title:title.isEmpty ? "Ein Klassiker":title,caption:caption,category:category.rawValue,duration:audio.duration,waveform:audio.waveform,sizeBytes:data.count,createdAt:Date.now.rjISO8601,ratings:[],reactions:[],recordedAt:date.rjISO8601)}else{clip=try await app.api.uploadFart(FartUpload(id:id,title:title.isEmpty ? "Ein Klassiker":title,caption:caption,category:category.rawValue,duration:audio.duration,waveform:audio.waveform,recordedAt:date.rjISO8601,location:nil,situation:"alltag",audioBase64:data.base64EncodedString()))}
        try LocalFartStore.shared.saveImported(clip,data:data,localOnly:localOnly)
        if !localOnly{await app.loadFartArchive()};dismiss()
    }catch{self.error=error.localizedDescription}}
}
