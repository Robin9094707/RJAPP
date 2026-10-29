import AVKit
import Photos
import PhotosUI
import SwiftUI

struct MessengerView:View {
    var initialMessageID: String? = nil
    @FocusState private var messageFocused: Bool
    @AppStorage("rjlove.keyboard-dismiss-after-send") private var closeKeyboardAfterSend = false
    @State private var positioned = false
    @State private var urgent=false
    @Environment(AppState.self) private var app
    @AppStorage("rjlove.chat-draft") private var text=""
    @State private var queuedMedia:SelectedMedia?
    @State private var picker=false
    @State private var selected:SelectedMedia?
    @State private var voice=false
    @State private var planning=false
    @State private var sending=false
    @State private var deleting:SharedRecord?
    private var messages:[SharedRecord]{app.records.filter{$0.kind == .chat}.sorted{$0.createdAt<$1.createdAt}}
    var body:some View {
        VStack(spacing:0){
            VStack(spacing:4){Text(app.partner?.displayName ?? "Dein Lieblingsmensch").font(.headline).accessibilityIdentifier("rj-messenger-title");if let date=app.partner.flatMap({app.lastOpened[$0.id]})?.rjDate{Text("App geöffnet: "+date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)}}.padding(9)
            ScrollViewReader{proxy in ScrollView{LazyVStack(spacing:14){
                Text("Ein Gespräch, das bei uns bleibt.").font(.system(.title3,design:.serif)).foregroundStyle(.secondary).padding(.vertical,22)
                ForEach(messages){record in message(record).id(record.id)}
            }.padding(16)}.defaultScrollAnchor(.bottom)
                .task(id:messages.map(\.id)){if !positioned,let id=initialMessageID,messages.contains(where:{$0.id==id}){await Task.yield();proxy.scrollTo(id,anchor:.center);positioned=true}}
                .onChange(of:messages.count){_,_ in if initialMessageID == nil || positioned,let last=messages.last{withAnimation{proxy.scrollTo(last.id,anchor:.bottom)}}}}
            if MediaTransfer.shared.busy{VStack{ProgressView(value:MediaTransfer.shared.progress);Text("\(MediaTransfer.shared.stage) · \(Int(MediaTransfer.shared.progress*100)) %").font(.caption)}.padding(12)}
            if urgent{HStack{Label("Dringend · kurzer Hinweis, kein Weckruf",systemImage:"exclamationmark.bubble.fill").font(.caption).foregroundStyle(.orange);Spacer();Button("Normal"){urgent=false}}.padding(.horizontal,16)}
            HStack(alignment:.bottom,spacing:10){
                Menu{Toggle("Als dringende Nachricht senden",isOn:$urgent);Divider();Toggle("Tastatur nach dem Senden schließen",isOn:$closeKeyboardAfterSend);Divider();Button("Foto, Video oder Live Photo",systemImage:"photo"){picker=true};Button("Sprachnachricht",systemImage:"mic.fill"){voice=true};Button("Termin mit optionalem Wecker",systemImage:"alarm.fill"){planning=true}}label:{Image(systemName:"plus.circle.fill").font(.title2)}.accessibilityLabel("Nachricht hinzufügen")
                TextField("Eine Nachricht nur für dich …",text:$text,axis:.vertical).focused($messageFocused).accessibilityIdentifier("chat-message-input").lineLimit(1...5).padding(12).background(.thinMaterial,in:RoundedRectangle(cornerRadius:22))
                Button{messageFocused=false}label:{Image(systemName:"keyboard.chevron.compact.down").font(.title3)}.accessibilityLabel("Tastatur schließen").accessibilityIdentifier("chat-dismiss-keyboard").disabled(!messageFocused)
                Button{Task{await sendText()}}label:{Image(systemName:"arrow.up.circle.fill").font(.system(size:34)).foregroundStyle(LovePalette.pink)}.disabled(sending || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>4000).accessibilityLabel("Nachricht senden")
            }.padding(.horizontal,16).padding(.vertical,10).background(.ultraThinMaterial)
        }.background(LoveBackground()).scrollDismissesKeyboard(.interactively)
            .task{await app.loadRecordArchive(kind:.chat)}
            .sheet(isPresented:$picker,onDismiss:{selected=queuedMedia;queuedMedia=nil}){MediaPicker{result in picker=false;switch result{case .success(let media):queuedMedia=media;case .failure(let error):if error is CancellationError{return};app.alert=AppAlert(title:"Medium",message:error.localizedDescription)}}}
            .sheet(item:$selected){MediaComposer(media:$0,kind:.chat)}
            .sheet(isPresented:$voice){VoiceComposerView()}
            .sheet(isPresented:$planning){PlannerEditor(initial:nil,initialDate:.now,onSaved:{record in Task{var payload=RecordPayload(text:"Ein gemeinsamer Plan: "+(record.payload.title ?? "Unsere Zeit"));payload.referenceID=record.id;_ = await app.saveRecord(kind:.chat,payload:payload)}})}
            .alert("Nachricht für beide zurückrufen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Zurückrufen",role:.destructive){if let record=deleting{Task{_ = await app.deleteRecord(record)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}
    }
    private func message(_ record:SharedRecord)->some View {
        let mine=record.ownerID==app.me?.id
        return HStack{if mine{Spacer(minLength:35)};VStack(alignment:mine ? .trailing:.leading,spacing:6){
            VStack(alignment:.leading,spacing:10){
                if record.payload.assetIDs?.isEmpty==false{MediaAttachmentView(record:record)}
                if record.payload.notificationPriority=="urgent"{Label("Dringend",systemImage:"exclamationmark.bubble.fill").font(.caption.bold())}
                if let text=record.payload.text,!text.isEmpty{Text(text).textSelection(.enabled)}
                if record.payload.referenceID != nil{NavigationLink{PlannerView()}label:{Label("Gemeinsamen Plan öffnen",systemImage:"alarm.fill")}.tint(mine ? .white:LovePalette.pink)}
                if record.payload.autoplay==true{Label("Süße Nachricht · beim Öffnen",systemImage:"heart.fill").font(.caption2)}
            }.padding(14).foregroundStyle(mine ? .white:.primary).background(mine ? LovePalette.pink:LovePalette.violet.opacity(0.12),in:RoundedRectangle(cornerRadius:23))
            if let date=record.createdAt.rjDate{Text(date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.system(size:10)).foregroundStyle(.secondary)}
            if mine,let opened=app.openedRecords.first(where:{$0.recordID==record.id && $0.userID != app.me?.id})?.openedAt.rjDate{Text("Geöffnet "+opened.formatted(.dateTime.day().month().hour().minute().second())).font(.system(size:10)).foregroundStyle(.secondary)}
        };if !mine{Spacer(minLength:35)}}.contextMenu{if mine{Button("Zurückrufen",systemImage:"trash",role:.destructive){deleting=record}}}.task{if !mine,!UserDefaults.standard.bool(forKey:"rjlove.opened."+record.id){await app.markOpened(record)}}
    }
    private func sendText() async {let submitted=text;sending=true;defer{sending=false};var payload=RecordPayload(text:submitted.trimmingCharacters(in:.whitespacesAndNewlines));payload.notificationPriority=urgent ? "urgent":"normal";if await app.saveRecord(kind:.chat,payload:payload) != nil{if text==submitted{text="";urgent=false};if closeKeyboardAfterSend{messageFocused=false}}}
}
struct MediaComposer:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let media:SelectedMedia
    let kind:RecordKind
    @State private var caption=""
    @State private var capturedAt=Date.now
    @State private var albumID=""
    @State private var saving=false
    @State private var assets:[String]?
    @State private var saved=false
    @State private var sharePlace=true
    @State private var compact=false
    @State private var prepared:SelectedMedia?
    @State private var uploadError:String?
    var body:some View {NavigationStack{Form{
        if let data=media.poster,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:20))}
        if let uploadError{Text(uploadError).font(.footnote).foregroundStyle(.orange)}
        if saved{Text("Moment geteilt").accessibilityIdentifier("media-upload-complete")}
        Label(media.kind=="live" ? "Live Photo · Bild und Bewegung":media.kind=="video" ? "Video":"Foto",systemImage:media.kind=="video" ? "video.fill":"photo.fill")
        TextField("Ein paar Worte dazu",text:$caption,axis:.vertical)
        if kind == .moment {DatePicker("Aufgenommen am",selection:$capturedAt);Picker("Album",selection:$albumID){Text("Alle Momente").tag("");ForEach(app.records.filter{$0.kind == .album}){Text($0.payload.title ?? "Album").tag($0.id)}}}
        if kind == .moment {
            if media.latitude != nil { Toggle("Aufnahmeort mit Schatzi teilen",isOn:$sharePlace) }
            else { Label("Kein Aufnahmeort in diesem Medium verfügbar",systemImage:"location.slash").font(.caption).foregroundStyle(.secondary) }
        }
        if saving{ProgressView(value:MediaTransfer.shared.progress);Text("\(Int(MediaTransfer.shared.progress*100)) % · \(MediaTransfer.shared.stage)")}
        if media.kind != "live" {Toggle("Platzsparend teilen",isOn:$compact).disabled(saving || assets != nil);Text("Optional: Fotos bis 3200 Pixel mit hoher JPEG-Qualität, Videos bis 1080p. Nur wenn die neue Datei kleiner ist. Aufnahmezeit und freigegebener Ort bleiben im Moment erhalten; die Datei in Apple Fotos bleibt unverändert.").font(.caption).foregroundStyle(.secondary)}
        Text("Standardmäßig bleiben die Originaldateien auf eurem Server. Sie können eigene Metadaten enthalten. Standardlimit: 256 MB pro Datei. Ein Live Photo wird mit beiden Originalbestandteilen gespeichert.").font(.footnote).foregroundStyle(.secondary)
    }.navigationTitle(kind == .chat ? "In unserem Gespräch":"Unser Moment").toolbar{
        ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}.disabled(saving)}
        ToolbarItem(placement:.confirmationAction){Button("Teilen"){Task{await save()}}.disabled(saving)}
    }.onAppear{capturedAt=media.capturedAt;sharePlace=LocationService.shared.photoLocationEnabled}.onDisappear{if !saving{for file in Set(media.files+(prepared?.files ?? [])){try? FileManager.default.removeItem(at:file)}}}.interactiveDismissDisabled(saving)}}
    private func save() async {
        saving=true;uploadError=nil;defer{saving=false}
        do {
            if assets==nil{if prepared==nil{prepared=compact ? try await MomentPreparation.compact(media):media};assets=try await MediaTransfer.shared.upload(prepared ?? media,api:app.api)}
            var payload=RecordPayload();payload.assetIDs=assets;payload.mediaKind=media.kind;payload.posterBase64=media.poster?.base64EncodedString()
            if kind == .moment{if sharePlace{payload.latitude=media.latitude;payload.longitude=media.longitude};payload.caption=caption;payload.capturedAt=capturedAt.rjISO8601;payload.albumID=albumID.isEmpty ? nil:albumID;payload.comments=[];payload.reactions=[]}else{payload.text=caption}
            if await app.saveRecord(kind:kind,payload:payload) != nil{saved=true;dismiss()}else{uploadError=app.alert?.message ?? "Der Moment konnte nicht gespeichert werden."}
        }catch{uploadError=error.localizedDescription}
    }
}
struct MediaAttachmentView:View {
    @Environment(AppState.self) private var app
    let record:SharedRecord
    @State private var files:[URL]=[]
    @State private var streaming=false
    @State private var showing=false
    @State private var loading=false
    var body:some View {Button{Task{await open()}}label:{VStack(spacing:9){
        if let data=record.payload.posterBase64.flatMap({Data(base64Encoded:$0)}),let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:240).clipShape(RoundedRectangle(cornerRadius:16))}
        if loading{ProgressView()}else{Label(record.payload.mediaKind=="audio" ? "Sprachnachricht anhören":record.payload.mediaKind=="video" ? "Video öffnen":record.payload.mediaKind=="live" ? "Live Photo öffnen":"Foto öffnen",systemImage:record.payload.mediaKind=="audio" ? "play.circle.fill":record.payload.mediaKind=="video" ? "play.rectangle.fill":"photo.fill").font(.subheadline.bold())}
    }}.buttonStyle(.lovePress).fullScreenCover(isPresented:$streaming){MomentGalleryViewer(records:[record],initialID:record.id)}.sheet(isPresented:$showing,onDismiss:{for url in files{try? FileManager.default.removeItem(at:url)};files=[]}){MediaViewer(files:files,kind:record.payload.mediaKind ?? "image")}}
    private func open() async {
        if !["audio","live"].contains(record.payload.mediaKind ?? "image"){streaming=true;return}
        loading=true;defer{loading=false}
        do {var loaded:[URL]=[];for (index,id) in (record.payload.assetIDs ?? []).enumerated(){loaded.append(try await app.api.assetFile(id:id,mime:index>0 || record.payload.mediaKind=="video" ? "video/quicktime":record.payload.mediaKind=="audio" ? "audio/mp4":"image/jpeg"))};files=loaded;showing=true;await app.markOpened(record)}catch{app.alert=AppAlert(title:"Medium",message:error.localizedDescription)}
    }
}
struct MediaViewer:View {
    @Environment(\.dismiss) private var dismiss
    let files:[URL]
    let kind:String
    @State private var share=false
    @State private var player:AVPlayer?
    @State private var videoAudioOwner=UUID()
    @State private var saveMessage:String?
    var body:some View {NavigationStack{VStack(spacing:16){
        if kind=="live",files.count==2{LivePhotoDisplay(files:files).frame(maxHeight:.infinity)}
        else if kind=="video"{VideoPlayer(player:player).onAppear{startVideo()}}
        else if kind=="audio"{Image(systemName:"waveform.circle.fill").font(.system(size:80)).foregroundStyle(LovePalette.pink);Button(VoiceNoteService.shared.playing ? "Stoppen":"Abspielen"){if VoiceNoteService.shared.playing{VoiceNoteService.shared.stop()}else if let file=files.first{try? VoiceNoteService.shared.play(file)}}.buttonStyle(.glassProminent)}
        else if let file=files.first,let image=MediaPicker.Coordinator.displayImage(file:file){Image(uiImage:image).resizable().scaledToFit()}
        if kind != "audio"{Button("In Apple Fotos sichern",systemImage:"square.and.arrow.down"){Task{await saveToPhotos()}}.buttonStyle(.glass)}
        if let saveMessage{Text(saveMessage).font(.footnote)}
    }.padding(18).background(LoveBackground()).navigationTitle(kind=="audio" ? "Für dich":"Unser Moment").toolbar{ToolbarItem(placement:.cancellationAction){Button("Fertig"){dismiss()}};ToolbarItem(placement:.topBarTrailing){Button("Teilen",systemImage:"square.and.arrow.up"){share=true}}}.sheet(isPresented:$share){FileShareView(urls:files)}.onDisappear{player?.pause();MomentVideoAudio.shared.release(owner:videoAudioOwner);player=nil;VoiceNoteService.shared.stop()}}}
    private func startVideo(){
        guard let file=files.first else{return}
        do{let video=AVPlayer(url:file);try MomentVideoAudio.shared.activate(video,owner:videoAudioOwner);player=video;video.play()}
        catch{saveMessage=error.localizedDescription}
    }
    private func saveToPhotos() async {
        let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly);guard status == .authorized || status == .limited else{saveMessage="Speichern in Fotos wurde nicht erlaubt.";return}
        do {try await PHPhotoLibrary.shared().performChanges{
            if kind=="live",files.count==2{let request=PHAssetCreationRequest.forAsset();request.addResource(with:.photo,fileURL:files[0],options:nil);request.addResource(with:.pairedVideo,fileURL:files[1],options:nil)}else if let file=files.first{if kind=="video"{PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:file)}else{PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:file)}}
        };saveMessage="In Fotos gesichert."}catch{saveMessage=error.localizedDescription}
    }
}
struct LivePhotoDisplay:UIViewRepresentable {
    let files:[URL]
    func makeUIView(context:Context)->PHLivePhotoView {let view=PHLivePhotoView();view.contentMode = .scaleAspectFit;PHLivePhoto.request(withResourceFileURLs:files,placeholderImage:nil,targetSize:.zero,contentMode:.aspectFit){photo,_ in DispatchQueue.main.async{view.livePhoto=photo;view.startPlayback(with:.full)}};return view}
    func updateUIView(_ uiView:PHLivePhotoView,context:Context){}
}
struct VoiceComposerView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sweet=true
    @State private var urgency=0.7
    @State private var text=""
    @State private var saving=false
    @State private var asset:String?
    private var voice:VoiceNoteService{.shared}
    var body:some View {NavigationStack{ScrollView{VStack(spacing:24){
        Image(systemName:"waveform.and.heart").font(.system(size:70)).foregroundStyle(LovePalette.pink.gradient)
        Text("Deine Stimme. Ihr Lächeln.").font(.system(size:30,weight:.medium,design:.serif)).multilineTextAlignment(.center)
        Text(String(format:"%.1f s",voice.duration)).font(.system(size:40,weight:.light,design:.rounded)).monospacedDigit()
        ProgressView(value:voice.level).tint(LovePalette.pink)
        Button(voice.recording ? "Aufnahme stoppen":"Aufnehmen",systemImage:voice.recording ? "stop.circle.fill":"mic.fill"){if voice.recording{voice.stopRecording()}else{asset=nil;Task{await voice.record()}}}.buttonStyle(.glassProminent).controlSize(.large)
        if let file=voice.file,!voice.recording{Button("Vorschau anhören",systemImage:"play.fill"){try? voice.play(file,volume:0.15+0.85*urgency)}}
        TextField("Eine kleine Botschaft dazu",text:$text,axis:.vertical).textFieldStyle(.roundedBorder)
        Toggle("Beim nächsten Öffnen süß begrüßen",isOn:$sweet)
        VStack(alignment:.leading){Text("Leise bis deutlich").font(.headline);Slider(value:$urgency,in:0...1);Text("Abspielpegel innerhalb der aktuellen Medienlautstärke. Die iPhone-Lautstärke wird nicht verändert.").font(.caption).foregroundStyle(.secondary)}.loveCard()
        if let error=voice.error{Text(error).foregroundStyle(.orange)}
        if saving{ProgressView(value:MediaTransfer.shared.progress)}
        Button("Süße Nachricht senden",systemImage:"heart.fill"){Task{await send()}}.buttonStyle(.glassProminent).controlSize(.large).disabled(voice.recording || voice.file==nil || voice.duration<0.2 || saving)
    }.padding(24)}.background(LoveBackground()).navigationTitle("Eine Stimme für dich").toolbar{ToolbarItem(placement:.cancellationAction){Button("Schließen"){dismiss()}.disabled(saving)}}.onDisappear{voice.stop()}}
    }
    private func send() async {guard let file=voice.file else{return};saving=true;defer{saving=false};voice.stop();do{if asset==nil{asset=try await MediaTransfer.shared.upload(SelectedMedia(files:[file],mimeTypes:["audio/mp4"],kind:"audio",capturedAt:.now,poster:nil),api:app.api).first};var payload=RecordPayload(text:text);payload.assetIDs=asset.map{[$0]};payload.mediaKind="audio";payload.autoplay=sweet;payload.urgency=urgency;if await app.saveRecord(kind:.chat,payload:payload) != nil{dismiss()}}catch{app.alert=AppAlert(title:"Sprachnachricht",message:error.localizedDescription)}}
}
struct SweetPlaybackView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record:SharedRecord
    @State private var file:URL?
    @State private var error:String?
    var body:some View {VStack(spacing:24){Image(systemName:"heart.circle.fill").font(.system(size:85)).foregroundStyle(LovePalette.pink.gradient);Text("Eine Stimme nur für dich.").font(.system(size:31,weight:.medium,design:.serif));Text(record.payload.text ?? "Dein Lieblingsmensch hat dir etwas dagelassen.").multilineTextAlignment(.center);if let date=record.createdAt.rjDate{Text(date.formatted(.dateTime.day().month().year().hour().minute().second())).font(.caption)};if let error{Text(error).foregroundStyle(.orange)}else{Label("Wiedergabe mit deiner Medienlautstärke",systemImage:"speaker.wave.2.fill").font(.caption)};Button("Stoppen & schließen"){VoiceNoteService.shared.stop();dismiss()}.buttonStyle(.glassProminent)}.padding(28).background(LoveBackground()).task{await app.markOpened(record);do{if let id=record.payload.assetIDs?.first{let url=try await app.api.assetFile(id:id,mime:"audio/mp4");guard !Task.isCancelled else{return};file=url;try VoiceNoteService.shared.play(url,volume:0.15+0.85*(record.payload.urgency ?? 1)){dismiss()}}else{VoiceNoteService.shared.speak(record.payload.text ?? "",volume:record.payload.urgency ?? 1)}}catch{self.error=error.localizedDescription}}.onDisappear{VoiceNoteService.shared.stop();if let file{try? FileManager.default.removeItem(at:file)}}}
}

