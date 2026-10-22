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
        guard !Task.isCancelled else { return }
        guard await AVCaptureDevice.requestAccess(for:.video) else{await MainActor.run{self.error="Die Kamera ist nicht freigegeben. Du kannst den Fotowunsch später beantworten."};return}
        guard !Task.isCancelled else { return }
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
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        let jpeg = photo.fileDataRepresentation().flatMap { MediaPicker.Coordinator.cameraJPEG($0) }
        DispatchQueue.main.async {
            if let error { self.error = error.localizedDescription }
            else if let jpeg { self.photo = jpeg }
            else { self.error = MediaError.unreadable.localizedDescription }
        }
    }
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
struct InstantCameraView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let request: SharedRecord
    @StateObject private var camera = InstantCamera()
    @State private var cancelled = false
    @State private var captured = false
    @State private var sending = false
    @State private var capturedAt = Date.now
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadedAsset: String?
    @State private var error: String?
    private var prompt: String { request.payload.title?.isEmpty == false ? request.payload.title! : "Bitte lächeln 🥰" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(prompt).font(.system(size: 30, weight: .medium, design: .serif)).multilineTextAlignment(.center).accessibilityIdentifier("instant-prompt")
                Text("Ein Foto nur für deinen Lieblingsmenschen").font(.subheadline).foregroundStyle(.secondary)
                ZStack {
                    if let data = camera.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                    else { InstantCameraPreview(camera: camera) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 28))
                if sending {
                    ProgressView(value: MediaTransfer.shared.progress)
                    Text("Wird gesendet …").font(.caption).accessibilityIdentifier("instant-sending")
                }
                if let error = error ?? camera.error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                    if camera.photo != nil { Button("Foto erneut senden") { beginUpload() }.buttonStyle(.borderedProminent) }
                } else {
                    Text("Sobald die sichtbare Kamera bereit ist, wird ein Foto aufgenommen und direkt geteilt. Du kannst es später unter Unser Jetzt zurückrufen.").font(.footnote).foregroundStyle(.secondary)
                }
                Button(sending ? "Upload abbrechen" : "Jetzt nicht", role: .cancel) { skip() }.buttonStyle(.bordered)
            }.padding(20).background(LoveBackground()).navigationTitle("Bitte lächeln").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-instant-camera") {
                    captured = true; camera.photo = PreviewFixtures.media().poster; return
                }
                #endif
                await camera.start()
            }
            .onChange(of: camera.running) { _, ready in
                guard ready, !cancelled, !captured, phase == .active else { return }
                captured = true; capturedAt = .now; camera.capture()
            }
            .onChange(of: camera.photo) { _, value in
                if value != nil { camera.stop(); beginUpload() }
            }
            .onChange(of: phase) { _, value in
                if value != .active { camera.stop() }
                else if camera.photo == nil, !cancelled { captured = false; Task { await camera.start() } }
            }
            .onDisappear { cancelled = true; uploadTask?.cancel(); camera.stop() }
    }
    private func skip() {
        cancelled = true
        UserDefaults.standard.set(true, forKey: "rjlove.photo-skip." + request.id)
        uploadTask?.cancel(); camera.stop(); dismiss()
    }
    private func beginUpload() {
        guard !cancelled, !sending, phase == .active, let original = camera.photo else { return }
        uploadTask = Task {
            sending = true; error = nil; defer { sending = false }
            do {
                guard let data = MediaPicker.Coordinator.cameraJPEG(original) else { throw MediaError.unreadable }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try data.write(to: file, options: .completeFileProtection)
                defer { try? FileManager.default.removeItem(at: file) }
                let poster = MediaPicker.Coordinator.poster(data)
                if uploadedAsset == nil {
                    uploadedAsset = try await MediaTransfer.shared.upload(SelectedMedia(files: [file], mimeTypes: ["image/jpeg"], kind: "image", capturedAt: capturedAt, poster: poster), api: app.api).first
                }
                try Task.checkCancellation()
                guard !cancelled, let id = uploadedAsset else { return }
                let photo = try await app.api.replyToPhotoRequest(id: request.id, assetID: id, caption: prompt, poster: poster, capturedAt: capturedAt)
                app.receiveInstantPhoto(photo, requestID: request.id)
                dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
struct InstantGalleryView:View {
    @Environment(AppState.self) private var app
    @State private var title="Ein Lächeln nur für mich 🥰"
    @State private var creating=false
    @State private var sendingRequest=false
    @State private var requestID=UUID().uuidString
    @State private var sent=false
    @State private var deleting:SharedRecord?
    @State private var editing:SharedRecord?
    private var photos:[SharedRecord]{app.records.filter{$0.kind == .instant}.sorted{$0.createdAt>$1.createdAt}}
    var body:some View {ScrollView{VStack(alignment:.leading,spacing:20){
        Text("Zeig mir dein Jetzt.").font(.system(size:32,weight:.medium,design:.serif))
        Text("Schick einen Fotowunsch. In der geöffneten App erscheint beim Gegenüber die sichtbare Kamera und nimmt direkt ein Foto auf. Beide können das unter Mehr ausschalten.").font(.subheadline).foregroundStyle(.secondary)
        Button(sendingRequest ? "Wird gewünscht …" : "Ein Foto wünschen",systemImage:"camera.badge.ellipsis"){creating=true}.disabled(sendingRequest).buttonStyle(.borderedProminent)
        if sent { Label("Fotowunsch gesendet", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("photo-request-sent") }
        ForEach(app.records.filter{$0.kind == .photo_request && $0.payload.completed != true}){request in HStack{Text(request.payload.title ?? "Ein Fotowunsch");Spacer();if request.payload.targetID==app.me?.id{Button("Beantworten"){UserDefaults.standard.removeObject(forKey:"rjlove.photo-skip."+request.id);app.pendingPhotoRequest=request}}else{Text("Wartet auf deinen Lieblingsmenschen").font(.caption)}}.loveCard()}
        ForEach(photos){photo in VStack(alignment:.leading,spacing:12){MediaAttachmentView(record:photo);Text(photo.payload.caption ?? "Unser Jetzt").font(.headline).accessibilityIdentifier("instant-photo-caption");if let date=(photo.payload.capturedAt ?? photo.createdAt).rjDate{Text(date.formatted(.dateTime.day().month(.wide).year().hour().minute().second())).font(.caption.monospacedDigit())};if photo.ownerID==app.me?.id{Button("Beschreiben",systemImage:"pencil"){editing=photo};Button("Foto zurückrufen",role:.destructive){deleting=photo}}}.loveCard()}
    }.padding(22)}.background(LoveBackground()).navigationTitle("Unser Jetzt").sheet(item:$editing){MomentMetadataEditor(record:$0)}.alert("Ein Foto für dich",isPresented:$creating){TextField("Fotowunsch",text:$title);Button("Wünschen"){sendingRequest=true;Task{if await app.requestPhoto(title:title,id:requestID){sent=true;requestID=UUID().uuidString};sendingRequest=false}};Button("Abbrechen",role:.cancel){}}.alert("Foto für beide zurückrufen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Zurückrufen",role:.destructive){if let photo=deleting{Task{_ = await app.deleteRecord(photo)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}.task{await app.loadRecordArchive(kind:.instant);await app.loadRecordArchive(kind:.photo_request)}}
}
