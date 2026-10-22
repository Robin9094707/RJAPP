import AVFoundation
import SwiftUI
import UIKit

final class InstantCamera:NSObject,ObservableObject,AVCapturePhotoCaptureDelegate,@unchecked Sendable {
    let session=AVCaptureSession()
    private let output=AVCapturePhotoOutput()
    private let queue=DispatchQueue(label:"eu.rjlove.instant-camera")
    @Published var photo:Data?
    @Published var error:String?
    @Published var running=false
    func start() async {
        guard await AVCaptureDevice.requestAccess(for:.video) else{await MainActor.run{self.error="Die Kamera ist nicht freigegeben. Du kannst den Fotowunsch später beantworten."};return}
        queue.async{
            do {
                if self.session.inputs.isEmpty {
                    self.session.beginConfiguration();defer{self.session.commitConfiguration()};self.session.sessionPreset = .photo
                    guard let camera=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.front) else{throw MediaError.unreadable}
                    let input=try AVCaptureDeviceInput(device:camera)
                    guard self.session.canAddInput(input),self.session.canAddOutput(self.output) else{throw MediaError.unreadable}
                    self.session.addInput(input);self.session.addOutput(self.output)
                }
                self.session.startRunning();DispatchQueue.main.async{self.running=self.session.isRunning}
            }catch{DispatchQueue.main.async{self.error=error.localizedDescription}}
        }
    }
    func capture(){queue.async{guard self.session.isRunning else{return};self.output.capturePhoto(with:AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.jpeg]),delegate:self)}}
    func stop(){queue.async{if self.session.isRunning{self.session.stopRunning()};DispatchQueue.main.async{self.running=false}}}
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?){DispatchQueue.main.async{if let error{self.error=error.localizedDescription}else{self.photo=photo.fileDataRepresentation()}}}
}
private final class CameraPreviewHost:UIView {
    override class var layerClass:AnyClass {AVCaptureVideoPreviewLayer.self}
    var preview:AVCaptureVideoPreviewLayer{layer as! AVCaptureVideoPreviewLayer}
}
private struct InstantCameraPreview:UIViewRepresentable {
    let camera:InstantCamera
    func makeUIView(context:Context)->CameraPreviewHost {let view=CameraPreviewHost();view.preview.session=camera.session;view.preview.videoGravity = .resizeAspectFill;return view}
    func updateUIView(_ uiView:CameraPreviewHost,context:Context){}
}
struct InstantCameraView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let request:SharedRecord
    @StateObject private var camera=InstantCamera()
    @State private var countdown=3
    @State private var cancelled=false
    @State private var caption=""
    @State private var sending=false
    @State private var capturedAt=Date.now
    @State private var captureTask:Task<Void,Never>?
    @State private var uploadTask:Task<Void,Never>?
    @State private var error:String?
    var body:some View {NavigationStack{VStack(spacing:16){
        Text("Ein Augenblick nur für uns.").font(.system(size:29,weight:.medium,design:.serif)).multilineTextAlignment(.center)
        Text(request.payload.title ?? "Dein Lieblingsmensch wünscht sich ein Foto.").font(.subheadline)
        ZStack{if let data=camera.photo,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit()}else{InstantCameraPreview(camera:camera);if camera.running{Text(String(countdown)).font(.system(size:90,weight:.bold,design:.rounded)).foregroundStyle(.white).shadow(radius:12)}}}.frame(maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:30))
        TextField("Zum Beispiel: Süßefresse 🥰",text:$caption).textFieldStyle(.roundedBorder).disabled(sending)
        if sending{ProgressView(value:MediaTransfer.shared.progress);Text("Wird geteilt · \(Int(MediaTransfer.shared.progress*100)) %").font(.caption)}else if let error=error ?? camera.error{Text(error).font(.footnote).foregroundStyle(.orange);if camera.photo != nil{Button("Erneut senden"){beginUpload()}.buttonStyle(.borderedProminent)}}else{Text("Die sichtbare Kamera nimmt nach 3 Sekunden ein Foto auf und teilt es. Du kannst jetzt abbrechen und später das Foto zurückrufen.").font(.footnote).foregroundStyle(.secondary)}
        Button(sending ? "Upload abbrechen":"Jetzt nicht",role:.cancel){skip()}.buttonStyle(.bordered)
    }.padding(20).background(LoveBackground()).navigationTitle("Ein Foto für dich")}.interactiveDismissDisabled()
        .task{caption=request.payload.title ?? "";await camera.start();startCountdown()}
        .onChange(of:camera.photo){_,value in if value != nil{capturedAt = .now;camera.stop();beginUpload()}}
        .onChange(of:phase){_,value in if value != .active{captureTask?.cancel();camera.stop()}else if camera.photo==nil{Task{await camera.start();startCountdown()}}else if !sending{beginUpload()}}
        .onDisappear{cancelled=true;captureTask?.cancel();uploadTask?.cancel();camera.stop()}
    }
    private func startCountdown(){captureTask?.cancel();captureTask=Task{for _ in 0..<150 where !camera.running{try? await Task.sleep(for:.milliseconds(100));if Task.isCancelled{return}};guard camera.running else{return};for value in stride(from:3,through:1,by:-1){countdown=value;try? await Task.sleep(for:.seconds(1));guard !Task.isCancelled,phase == .active else{return}};guard phase == .active else{return};camera.capture()}}
    private func skip(){cancelled=true;UserDefaults.standard.set(true,forKey:"rjlove.photo-skip."+request.id);captureTask?.cancel();uploadTask?.cancel();camera.stop();dismiss()}
    private func beginUpload(){guard !cancelled,phase == .active else{return};uploadTask?.cancel();uploadTask=Task{guard let data=camera.photo else{return};sending=true;defer{sending=false};do{let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg");try data.write(to:file,options:.completeFileProtection);defer{try? FileManager.default.removeItem(at:file)};let poster=MediaPicker.Coordinator.poster(data);let media=SelectedMedia(files:[file],mimeTypes:["image/jpeg"],kind:"image",capturedAt:capturedAt,poster:poster);let ids=try await MediaTransfer.shared.upload(media,api:app.api);guard let id=ids.first,!Task.isCancelled else{return};_ = try await app.api.replyToPhotoRequest(id:request.id,assetID:id,caption:caption,poster:poster,capturedAt:capturedAt);_ = await app.syncNow(showErrors:false);dismiss()}catch{if !Task.isCancelled{self.error=error.localizedDescription}}}}
}
struct InstantGalleryView:View {
    @Environment(AppState.self) private var app
    @State private var title="Ein Lächeln nur für mich 🥰"
    @State private var creating=false
    @State private var deleting:SharedRecord?
    @State private var editing:SharedRecord?
    private var photos:[SharedRecord]{app.records.filter{$0.kind == .instant}.sorted{$0.createdAt>$1.createdAt}}
    var body:some View {ScrollView{VStack(alignment:.leading,spacing:20){
        Text("Zeig mir dein Jetzt.").font(.system(size:32,weight:.medium,design:.serif))
        Text("Schick einen Fotowunsch. Beim nächsten Öffnen erscheint beim Gegenüber eine sichtbare Kamera mit abbrechbarem Countdown. Beide können das unter Mehr ausschalten.").font(.subheadline).foregroundStyle(.secondary)
        Button("Ein Foto wünschen",systemImage:"camera.badge.ellipsis"){creating=true}.buttonStyle(.borderedProminent)
        ForEach(app.records.filter{$0.kind == .photo_request && $0.payload.completed != true}){request in HStack{Text(request.payload.title ?? "Ein Fotowunsch");Spacer();if request.payload.targetID==app.me?.id{Button("Beantworten"){UserDefaults.standard.removeObject(forKey:"rjlove.photo-skip."+request.id);app.pendingPhotoRequest=request}}else{Text("Wartet auf deinen Lieblingsmenschen").font(.caption)}}.loveCard()}
        ForEach(photos){photo in VStack(alignment:.leading,spacing:12){MediaAttachmentView(record:photo);Text(photo.payload.caption ?? "Unser Jetzt").font(.headline);if let date=(photo.payload.capturedAt ?? photo.createdAt).rjDate{Text(date.formatted(.dateTime.day().month(.wide).year().hour().minute().second())).font(.caption.monospacedDigit())};if photo.ownerID==app.me?.id{Button("Beschreiben",systemImage:"pencil"){editing=photo};Button("Foto zurückrufen",role:.destructive){deleting=photo}}}.loveCard()}
    }.padding(22)}.background(LoveBackground()).navigationTitle("Unser Jetzt").sheet(item:$editing){MomentMetadataEditor(record:$0)}.alert("Ein Foto für dich",isPresented:$creating){TextField("Fotowunsch",text:$title);Button("Wünschen"){Task{guard let partner=app.partner else{return};_ = await app.saveRecord(kind:.photo_request,payload:RecordPayload(title:title,targetID:partner.id,completed:false))}};Button("Abbrechen",role:.cancel){}}.alert("Foto für beide zurückrufen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Zurückrufen",role:.destructive){if let photo=deleting{Task{_ = await app.deleteRecord(photo)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}.task{await app.loadRecordArchive(kind:.instant);await app.loadRecordArchive(kind:.photo_request)}}
}
