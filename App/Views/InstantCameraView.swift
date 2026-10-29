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
    @State private var latitude:Double?
    @State private var longitude:Double?
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadedAsset: String?
    @State private var requestVerified=false
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
                    else {Button("Fotowunsch erneut prüfen"){Task{await verifyRequestAndStart()}}.buttonStyle(.bordered)}
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
                app.location.requestPhotoLocation()
                await verifyRequestAndStart()
            }
            .onAppear { cancelled = false }
            .onChange(of: camera.running) { _, _ in advanceCamera() }
            .task(id: camera.photo != nil) {
                if camera.photo != nil { camera.stop(); advanceCamera() }
            }
            .onChange(of: phase) { _, value in
                if value != .active { camera.stop() }
                else { resumeVisibleCamera() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in resumeVisibleCamera() }
            .onDisappear { cancelled = true; uploadTask?.cancel(); camera.stop() }
    }
    private func verifyRequestAndStart() async {
        error=nil
        do {
            let state=try await app.refreshPhotoRequests()
            guard state.incoming.contains(where:{$0.id==request.id}),!cancelled else{camera.stop();dismiss();return}
            requestVerified=true;await camera.start()
        }catch{self.error="Fotowunsch konnte nicht geprüft werden: "+error.localizedDescription}
    }
    private func advanceCamera() {
        guard !cancelled, UIApplication.shared.applicationState == .active else { return }
        if camera.photo != nil { beginUpload() }
        else if camera.running, !captured {
            captured = true; capturedAt = .now
            if let coordinate=app.location.freshPhotoCoordinate { latitude=coordinate.latitude;longitude=coordinate.longitude }
            camera.capture()
        }
    }
    private func resumeVisibleCamera() {
        guard !cancelled,requestVerified else { return }
        if camera.photo != nil { beginUpload() }
        else { captured = false; Task { await camera.start(); advanceCamera() } }
    }
    private func skip() {
        cancelled = true
        UserDefaults.standard.set(true, forKey: "rjlove.photo-skip." + request.id)
        uploadTask?.cancel(); camera.stop(); dismiss()
    }
    private func beginUpload() {
        guard !cancelled, !sending, UIApplication.shared.applicationState == .active, let original = camera.photo else { return }
        sending = true; error = nil
        uploadTask = Task {
            defer { sending = false }
            do {
                try Task.checkCancellation()
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
                let photo = try await app.api.replyToPhotoRequest(id: request.id, assetID: id, caption: prompt, poster: poster, capturedAt: capturedAt,latitude:latitude,longitude:longitude)
                app.receiveInstantPhoto(photo, requestID: request.id)
                dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
struct InstantGalleryView:View {
    @Environment(AppState.self) private var app
    @State private var creating=false
    @State private var title="Bitte lächeln, nur für mich 💗"
    @State private var sendingRequest=false
    @State private var sent=false
    @State private var requestID=UUID().uuidString
    @State private var deleting:SharedRecord?
    @State private var editing:SharedRecord?
    @State private var selectedDay=Date.now
    @State private var recalling:SharedRecord?
    private var photos:[SharedRecord]{app.records.filter{$0.kind == .instant}.sorted{(JournalDates.date($0) ?? .distantPast)>(JournalDates.date($1) ?? .distantPast)}}
    private var dayPhotos:[SharedRecord]{photos.filter{Calendar.current.isDate(JournalDates.date($0) ?? .distantPast,inSameDayAs:selectedDay)}}
    private var requests:[SharedRecord]{app.records.filter{$0.kind == .photo_request && $0.payload.targetID==app.me?.id && $0.payload.completed != true}}
    var body:some View {
        ScrollView {LazyVStack(alignment:.leading,spacing:22) {
            introduction
            if let request=app.outgoingPhotoRequest {outgoingCard(request)}
            VStack(alignment:.leading,spacing:10) {
                HStack{Label("Euer Fotokalender",systemImage:"calendar").font(.headline);Spacer();Button("Heute"){selectedDay = .now}}
                PhotoCalendarView(selection:$selectedDay,photos:photos)
                Text("Die rosa Zahl zeigt eure BeReal-Fotos an diesem Tag. Maßgeblich ist die gespeicherte Aufnahmezeit.").font(.caption).foregroundStyle(.secondary)
            }.loveCard()
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:5) {Text(selectedDay.formatted(.dateTime.weekday(.wide))).font(.caption.bold()).foregroundStyle(LovePalette.pink);Text(selectedDay.formatted(date:.long,time:.omitted)).font(.title2.bold())}
                Spacer();Text("\(dayPhotos.count) Fotos").font(.caption.bold()).foregroundStyle(.secondary)
            }
            NavigationLink{SharedJournalView(initialDay:selectedDay)}label:{Label("Diesen Tag gemeinsam ansehen",systemImage:"sparkles.rectangle.stack.fill").frame(maxWidth:.infinity)}.buttonStyle(.bordered)
            if dayPhotos.isEmpty {ContentUnavailableView("Platz für euer echtes Leben",systemImage:"camera.on.rectangle",description:Text("An diesem Tag gibt es noch kein BeReal. Auch die leisen Tage gehören zu euch."))}
            ForEach(dayPhotos){photo in photoCard(photo)}
            if !requests.isEmpty {DisclosureGroup("Offene Fotowünsche · \(requests.count)") {ForEach(requests){request in
                HStack{Text(request.payload.title ?? "Ein Fotowunsch").font(.subheadline);Spacer();if request.payload.targetID==app.me?.id{Button("Beantworten"){UserDefaults.standard.removeObject(forKey:"rjlove.photo-skip."+request.id);app.pendingPhotoRequest=request}}else{Image(systemName:"clock").foregroundStyle(.secondary)}}.padding(.vertical,8)
            }}.loveCard()}
        }.padding(20)}.background(LoveBackground()).navigationTitle("Unser BeReal").navigationBarTitleDisplayMode(.inline)
        .sheet(item:$editing){MomentMetadataEditor(record:$0)}
        .alert("Ein Foto für dich",isPresented:$creating){TextField("Fotowunsch",text:$title);Button("Wünschen"){sendingRequest=true;Task{if await app.requestPhoto(title:title,id:requestID){sent=true;requestID=UUID().uuidString};sendingRequest=false}};Button("Abbrechen",role:.cancel){}}
        .confirmationDialog("Fotowunsch zurückrufen?",isPresented:Binding(get:{recalling != nil},set:{if !$0{recalling=nil}}),titleVisibility:.visible){Button("Fotowunsch zurückrufen",role:.destructive){if let request=recalling{Task{_ = await app.recallPhotoRequest(request)}};recalling=nil};Button("Behalten",role:.cancel){recalling=nil}}message:{Text("Dein Gegenüber kann diesen Wunsch danach nicht mehr beantworten. Ein bereits fertig gesendetes Foto wird nicht gelöscht.")}
        .alert("Foto für beide zurückrufen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Zurückrufen",role:.destructive){if let photo=deleting{Task{_ = await app.deleteRecord(photo)}};deleting=nil};Button("Abbrechen",role:.cancel){deleting=nil}}
        .task{await app.loadRecordArchive(kind:.instant);_ = try? await app.refreshPhotoRequests()}
        .refreshable{_ = await app.syncNow(showErrors:false);await app.loadRecordArchive(kind:.instant)}
    }
    private var introduction:some View {
        VStack(alignment:.leading,spacing:16) {
            LoveEyebrow(text:"Echte Augenblicke. Unser kleines Leben.")
            HStack{Text("Ein Tag. Ein Blick.\nGanz viel wir.").font(.system(size:33,weight:.medium,design:.serif));Spacer(minLength:0);Image(systemName:"camera.on.rectangle.fill").font(.system(size:46)).foregroundStyle(LovePalette.pink.gradient)}
            Text("Blättert durch eure Tage und findet das Lächeln dazwischen. Ein Fotowunsch öffnet beim Gegenüber die sichtbare Kamera, wenn die App geöffnet und die Funktion erlaubt ist.").font(.subheadline).foregroundStyle(.secondary)
            Button(sendingRequest ? "Wird gewünscht …":"Ein Foto wünschen",systemImage:"camera.badge.ellipsis"){creating=true}.disabled(sendingRequest || app.sendingPhotoRequest || app.outgoingPhotoRequest != nil || app.recallingPhotoRequest).buttonStyle(.borderedProminent).controlSize(.large)
            if sent,app.outgoingPhotoRequest != nil {Label("Fotowunsch gesendet",systemImage:"checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("photo-request-sent")}
        }.loveCard()
    }
    private func outgoingCard(_ request:SharedRecord)->some View {
        VStack(alignment:.leading,spacing:16){
            HStack(spacing:12){LoveIcon(symbol:"paperplane.fill",tint:LovePalette.violet);VStack(alignment:.leading,spacing:4){Text("Dein Fotowunsch wartet").font(.headline);Text("Bei "+(app.partner?.displayName ?? "deinem Lieblingsmenschen")).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"clock").foregroundStyle(LovePalette.violet)}
            Text(request.payload.title ?? "Bitte lächeln").font(.system(.title3,design:.serif))
            if let date=request.createdAt.rjDate{Text("Gesendet "+date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
            Text("Ein Wunsch nach dem anderen. Sobald das Foto da ist oder du zurückrufst, kannst du einen neuen senden.").font(.subheadline).foregroundStyle(.secondary)
            Button(app.recallingPhotoRequest ? "Wird zurückgerufen …":"Fotowunsch zurückrufen",systemImage:"arrow.uturn.backward"){recalling=request}.buttonStyle(.bordered).disabled(app.recallingPhotoRequest).accessibilityIdentifier("photo-request-recall")
        }.loveCard().accessibilityIdentifier("outgoing-photo-request")
    }
    private func photoCard(_ photo:SharedRecord)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{PartnerAvatar(name:photo.ownerID==app.me?.id ? app.me?.displayName ?? "Du":app.partner?.displayName ?? "Dein Lieblingsmensch",size:34);VStack(alignment:.leading){Text(photo.ownerID==app.me?.id ? "Dein Jetzt":"Ein Blick von "+(app.partner?.displayName ?? "deinem Lieblingsmenschen")).font(.subheadline.bold());if let date=JournalDates.date(photo){Text(date.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary)}};Spacer();if photo.ownerID==app.me?.id{Menu{Button("Beschreiben",systemImage:"pencil"){editing=photo};Button("Foto zurückrufen",systemImage:"trash",role:.destructive){deleting=photo}}label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("BeReal verwalten")}}
            MediaAttachmentView(record:photo)
            Text(photo.payload.caption?.isEmpty == false ? photo.payload.caption!:"Unser Jetzt").font(.system(.title3,design:.serif)).accessibilityIdentifier("instant-photo-caption")
            PhotoPlaceView(payload:photo.payload)
        }.loveCard()
    }
}
