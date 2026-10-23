import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct MomentCameraView:View {
    let selected:(Result<SelectedMedia,Error>)->Void
    @State private var permitted=false
    @State private var error:String?
    var body:some View {
        Group {
            if permitted { NativeMomentCamera(selected:selected).ignoresSafeArea() }
            else {
                VStack(spacing:20) {
                    Label(error ?? "Kamera wird vorbereitet …",systemImage:"camera.fill")
                    if error != nil { Button("Schließen") { selected(.failure(CancellationError())) } }
                }
            }
        }.task {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error="Auf diesem Gerät ist keine Kamera verfügbar.";return }
            permitted=await AVCaptureDevice.requestAccess(for:.video)
            if permitted { LocationService.shared.requestPhotoLocation() }
            else { error="Bitte erlaube die Kamera in den iPhone-Einstellungen." }
        }
    }
}
private struct NativeMomentCamera:UIViewControllerRepresentable {
    let selected:(Result<SelectedMedia,Error>)->Void
    func makeCoordinator()->Coordinator { Coordinator(selected) }
    func makeUIViewController(context:Context)->UIImagePickerController {
        let picker=UIImagePickerController();picker.sourceType = .camera;picker.cameraCaptureMode = .photo;picker.delegate=context.coordinator;return picker
    }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let selected:(Result<SelectedMedia,Error>)->Void
        init(_ selected:@escaping(Result<SelectedMedia,Error>)->Void) {self.selected=selected}
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) {selected(.failure(CancellationError()))}
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {
            guard let image=info[.originalImage] as? UIImage,let original=image.jpegData(compressionQuality:0.95) else {selected(.failure(MediaError.unreadable));return}
            do {
                let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
                try original.write(to:file,options:.completeFileProtection)
                let point=LocationService.shared.freshPhotoCoordinate
                selected(.success(SelectedMedia(files:[file],mimeTypes:["image/jpeg"],kind:"image",capturedAt:.now,poster:MediaPicker.Coordinator.poster(original),latitude:point?.latitude,longitude:point?.longitude)))
            } catch {selected(.failure(error))}
        }
    }
}
