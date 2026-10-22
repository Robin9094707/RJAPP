import SwiftUI
import UniformTypeIdentifiers
struct FartLibraryView:View {
    @Environment(AppState.self) private var app
    @State private var importing=false
    @State private var source:ImportSource?
    @State private var delete:SavedFart?
    @State private var sharing=false
    @State private var exportURL:URL?
    private var library:LocalFartStore{.shared}
    var body:some View {List{
        Section{Button("Vorhandenen Furz importieren",systemImage:"square.and.arrow.down"){importing=true};Text("Lokale Kopien sind unabhängig vom Server. Beim Löschen auf dem Server bleiben sie bewusst hier erhalten. Audio und Metadaten werden zusammen auf deinem iPhone gesichert.").font(.footnote).foregroundStyle(.secondary)}
        Section("Auf diesem iPhone"){ForEach(library.clips){entry in VStack(alignment:.leading,spacing:9){Text(entry.clip.title).font(.headline);if let date=entry.clip.date{Text(date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.caption)};HStack{Button("Abspielen",systemImage:"play.fill"){if let url=library.audioURL(id:entry.id){app.studio.playLocal(url:url,id:entry.id)}};Button("Exportieren",systemImage:"square.and.arrow.up"){exportURL=library.audioURL(id:entry.id);sharing=true};Spacer();Button(role:.destructive){delete=entry}label:{Image(systemName:"trash")}}.font(.caption)}}}
    }.navigationTitle("Meine Duftschatzkiste").fileImporter(isPresented:$importing,allowedContentTypes:[.audio]){result in if case .success(let url)=result{source=ImportSource(url:url)}else if case .failure(let error)=result{app.alert=AppAlert(title:"Import",message:error.localizedDescription)}}.sheet(item:$source){FartImportView(source:$0.url)}.sheet(isPresented:$sharing){if let exportURL{FileShareView(urls:[exportURL])}}.alert("Lokale Kopie löschen?",isPresented:Binding(get:{delete != nil},set:{if !$0{delete=nil}})){Button("Nur lokale Kopie löschen",role:.destructive){if let entry=delete{do{try library.remove(entry)}catch{app.alert=AppAlert(title:"Lokales Löschen",message:error.localizedDescription)}};delete=nil};Button("Abbrechen",role:.cancel){delete=nil}}message:{Text("Die geteilte Aufnahme auf eurem Server bleibt erhalten.")}.onAppear{if let server=app.profile?.baseURL,let user=app.me?.id{library.configure(server:server,userID:user)}}}
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
    }.navigationTitle("Ein Klassiker kehrt zurück").toolbar{ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction){Button("Importieren"){Task{await save()}}.disabled(audio==nil || saving)}}.task{
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}};title=source.deletingPathExtension().lastPathComponent
        date=(try? source.resourceValues(forKeys:[.creationDateKey]))?.creationDate ?? .now
        if date > .now{date = .now}
        do{audio=try await ImportedFartAudio.prepare(source)}catch{self.error=error.localizedDescription}
    }.onDisappear{app.studio.stopPlayback();if let audio{try? FileManager.default.removeItem(at:audio.url)}}}
    }
    private func save() async {guard let audio,let user=app.me?.id else{return};saving=true;defer{saving=false};do{let data=try Data(contentsOf:audio.url);let id=UUID().uuidString;let clip:FartClip
        if localOnly{clip=FartClip(id:id,ownerID:user,title:title.isEmpty ? "Ein Klassiker":title,caption:caption,category:category.rawValue,duration:audio.duration,waveform:audio.waveform,sizeBytes:data.count,createdAt:Date.now.rjISO8601,ratings:[],reactions:[],recordedAt:date.rjISO8601)}else{clip=try await app.api.uploadFart(FartUpload(id:id,title:title.isEmpty ? "Ein Klassiker":title,caption:caption,category:category.rawValue,duration:audio.duration,waveform:audio.waveform,recordedAt:date.rjISO8601,location:nil,situation:"alltag",audioBase64:data.base64EncodedString()))}
        try LocalFartStore.shared.saveImported(clip,data:data)
        if !localOnly{await app.loadFartArchive()};dismiss()
    }catch{self.error=error.localizedDescription}}
}
