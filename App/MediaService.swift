import AVFoundation
import CryptoKit
import Foundation
import Observation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SelectedMedia: Identifiable {
    let id = UUID()
    var files: [URL]
    var mimeTypes: [String]
    var kind: String
    var capturedAt: Date
    var poster: Data?
}
final class MediaUploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(_ update: @escaping @Sendable (Double)->Void) { self.update = update }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { update(Double(totalBytesSent)/Double(totalBytesExpectedToSend)) }
    }
}
@MainActor @Observable final class MediaTransfer {
    static let shared = MediaTransfer()
    var progress = 0.0
    var busy = false
    var stage = ""
    func upload(_ media: SelectedMedia, api: APIClient) async throws -> [String] {
        guard !busy else { throw APIClientError.transport("Ein Upload läuft bereits.") }
        busy = true; progress = 0; defer { busy = false }
        var result: [String] = []
        for (index,file) in media.files.enumerated() {
            stage = "Datei \(index+1) von \(media.files.count)"
            let count = media.files.count
            let asset = try await api.uploadAsset(file:file,mime:media.mimeTypes[index]) { fraction in
                Task { @MainActor in self.progress = (Double(index)+fraction)/Double(count) }
            }
            result.append(asset)
        }
        progress = 1
        return result
    }
}
extension APIClient {
    func recordAppOpen() async throws { _ = try await execute(try request(path:"/v1/open",method:"POST",body:Data("{}".utf8)),as:EmptyResponse.self) }
    func markOpened(id:String) async throws { _ = try await execute(try request(path:"/v1/records/\(id)/opened",method:"POST",body:Data("{}".utf8)),as:EmptyResponse.self) }
    func thoughtArchive() async throws -> [ThoughtEvent] {
        struct Page:Decodable { let events:[ThoughtEvent] }
        var all:[ThoughtEvent] = []; var offset = 0
        while true {
            try Task.checkCancellation()
            var req=try request(path:"/v1/thoughts/history",method:"GET")
            var url=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!;url.queryItems=[URLQueryItem(name:"offset",value:String(offset))];req.url=url.url
            let page=try await execute(req,as:Page.self);all += page.events
            if page.events.count < 200 { return all };offset += page.events.count
        }
    }
    func recordArchive(kind:RecordKind) async throws -> [SharedRecord] {
        struct Page:Decodable { let records:[SharedRecord] }
        var all:[SharedRecord] = [];var offset=0
        while true {
            try Task.checkCancellation()
            var req=try request(path:"/v1/records/archive",method:"GET")
            var url=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!;url.queryItems=[URLQueryItem(name:"kind",value:kind.rawValue),URLQueryItem(name:"offset",value:String(offset))];req.url=url.url
            let page=try await execute(req,as:Page.self);all += page.records
            if page.records.count < 200 { return all };offset += page.records.count
        }
    }
    func uploadAsset(file:URL,mime:String,progress:@escaping @Sendable (Double)->Void) async throws -> String {
        struct ID:Decodable {let id:String}
        let hashAndSize = try await Task.detached(priority:.userInitiated) { () throws -> (String,Int) in
            let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()};var hash=SHA256();var size=0
            while let data=try handle.read(upToCount:1024*1024),!data.isEmpty {hash.update(data:data);size += data.count}
            return (hash.finalize().map{String(format:"%02x",$0)}.joined(),size)
        }.value
        let body:[String:Any]=["filename":file.lastPathComponent,"mime_type":mime,"size_bytes":hashAndSize.1,"sha256":hashAndSize.0]
        let asset=try await execute(try request(path:"/v1/assets",method:"POST",body:JSONSerialization.data(withJSONObject:body)),as:ID.self)
        do {
            var req=try request(path:"/v1/assets/\(asset.id)",method:"PUT");req.timeoutInterval=300;req.setValue(mime,forHTTPHeaderField:"Content-Type")
            let config=URLSessionConfiguration.default;config.timeoutIntervalForResource=900
            let uploadSession=URLSession(configuration:config);defer{uploadSession.finishTasksAndInvalidate()}
            let delegate=MediaUploadProgress(progress)
            let (data,response)=try await uploadSession.upload(for:req,fromFile:file,delegate:delegate)
            guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
                let issue=try? JSONDecoder().decode(APIErrorEnvelope.self,from:data)
                throw APIClientError.transport(issue?.message ?? "Upload fehlgeschlagen.")
            }
            progress(1);return asset.id
        } catch {
            _ = try? await execute(try request(path:"/v1/assets/\(asset.id)",method:"DELETE"),as:EmptyResponse.self)
            throw error
        }
    }
    func assetFile(id:String,mime:String) async throws -> URL {
        let req=try request(path:"/v1/assets/\(id)",method:"GET")
        let config=URLSessionConfiguration.default;config.timeoutIntervalForResource=900
        let download=URLSession(configuration:config);defer{download.finishTasksAndInvalidate()}
        let (temporary,response)=try await download.download(for:req)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {throw APIClientError.transport("Medium wurde zurückgerufen oder ist nicht erreichbar.")}
        let actual=http.mimeType ?? mime
        let ext=actual.contains("video") ? "mov" : actual.contains("audio") ? "m4a" : actual.contains("heic") || actual.contains("heif") ? "heic" : actual.contains("png") ? "png":"jpg"
        let target=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
        try FileManager.default.moveItem(at:temporary,to:target)
        try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:target.path)
        return target
    }
    func publishIPA(assetID:String) async throws -> AppRelease? {
        struct Response:Decodable {let release:AppRelease?}
        return try await execute(try request(path:"/v1/app-release",method:"POST",body:encoder.encode(["asset_id":assetID])),as:Response.self).release
    }
    func latestIPA() async throws -> URL {
        let config=URLSessionConfiguration.default;config.timeoutIntervalForResource=900
        let transfer=URLSession(configuration:config);defer{transfer.finishTasksAndInvalidate()}
        let (file,response)=try await transfer.download(for:request(path:"/v1/app-release/ipa",method:"GET"))
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else{throw APIClientError.transport("Update konnte nicht geladen werden.")}
        let result=FileManager.default.temporaryDirectory.appendingPathComponent("RJ-Love-"+UUID().uuidString+".ipa");try FileManager.default.moveItem(at:file,to:result);return result
    }
    func latestRelease() async throws -> AppRelease? {
        struct Response:Decodable {let release:AppRelease?}
        return try await execute(try request(path:"/v1/app-release",method:"GET"),as:Response.self).release
    }
    func updateFeedToken(baseURL:String) async throws -> String {
        struct Response:Decodable {let token:String}
        return try await execute(try request(path:"/v1/update-feed",method:"POST",body:encoder.encode(["base_url":baseURL])),as:Response.self).token
    }
    func replyToPhotoRequest(id:String,assetID:String,caption:String,poster:Data?,capturedAt:Date = .now) async throws -> SharedRecord {
        try await execute(try request(path:"/v1/photo-requests/\(id)/reply",method:"POST",body:encoder.encode(["asset_id":assetID,"caption":caption,"captured_at":capturedAt.rjISO8601,"poster_base64":poster?.base64EncodedString() ?? ""])),as:SharedRecord.self)
    }
}

struct MediaPicker: UIViewControllerRepresentable {
    var selected: (Result<SelectedMedia,Error>)->Void
    func makeUIViewController(context:Context)->PHPickerViewController {
        var config=PHPickerConfiguration(photoLibrary:.shared());config.filter = .any(of:[.images,.videos]);config.selectionLimit=1;config.preferredAssetRepresentationMode = .current
        let picker=PHPickerViewController(configuration:config);picker.delegate=context.coordinator;return picker
    }
    func updateUIViewController(_ uiViewController:PHPickerViewController,context:Context){}
    func makeCoordinator()->Coordinator {Coordinator(selected)}
    final class Coordinator:NSObject,PHPickerViewControllerDelegate {
        let selected:(Result<SelectedMedia,Error>)->Void
        init(_ selected:@escaping(Result<SelectedMedia,Error>)->Void){self.selected=selected}
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            guard let result=results.first else{finish(.failure(CancellationError()));return}
            let provider=result.itemProvider
            if provider.canLoadObject(ofClass:PHLivePhoto.self) {
                provider.loadObject(ofClass:PHLivePhoto.self) { object,error in
                    guard let live=object as? PHLivePhoto else {self.finish(.failure(error ?? MediaError.unreadable));return}
                    Task {
                        do {
                            let resources=PHAssetResource.assetResources(for:live).filter{[PHAssetResourceType.photo,.pairedVideo,.fullSizePhoto,.fullSizePairedVideo].contains($0.type)}
                            let photo=resources.first{$0.type == .photo || $0.type == .fullSizePhoto}
                            let video=resources.first{$0.type == .pairedVideo || $0.type == .fullSizePairedVideo}
                            guard let photo,let video else{throw MediaError.unreadable}
                            var files:[URL]=[]
                            for resource in [photo,video] {
                                let ext=URL(fileURLWithPath:resource.originalFilename).pathExtension
                                let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
                                let options=PHAssetResourceRequestOptions();options.isNetworkAccessAllowed=true
                                try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                                    PHAssetResourceManager.default().writeData(for:resource,toFile:file,options:options){error in if let error{continuation.resume(throwing:error)}else{continuation.resume()}}
                                };files.append(file)
                            }
                            let bytes=try Data(contentsOf:files[0]);let poster=Self.poster(bytes)
                            self.finish(.success(SelectedMedia(files:files,mimeTypes:[photo.uniformTypeIdentifier.contains("heic") ? "image/heic":"image/jpeg","video/quicktime"],kind:"live",capturedAt:Self.captureDate(result),poster:poster)))
                        } catch {self.finish(.failure(error))}
                    }
                }
            } else {
                let video=provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                let type=video ? UTType.movie.identifier:UTType.image.identifier
                provider.loadFileRepresentation(forTypeIdentifier:type) { file,error in
                    guard let file else{self.finish(.failure(error ?? MediaError.unreadable));return}
                    do {
                        let ext=file.pathExtension.lowercased();let destination=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
                        try FileManager.default.copyItem(at:file,to:destination)
                        let mime=video ? (ext=="mp4" ? "video/mp4":"video/quicktime") : ["png":"image/png","heic":"image/heic","heif":"image/heif"].first{$0.key==ext}?.value ?? "image/jpeg"
                        let poster=video ? nil:Self.poster(try Data(contentsOf:destination))
                        self.finish(.success(SelectedMedia(files:[destination],mimeTypes:[mime],kind:video ? "video":"image",capturedAt:Self.captureDate(result),poster:poster)))
                    } catch{self.finish(.failure(error))}
                }
            }
        }
        static func captureDate(_ result:PHPickerResult)->Date {
            guard let identifier=result.assetIdentifier else{return .now}
            return PHAsset.fetchAssets(withLocalIdentifiers:[identifier],options:nil).firstObject?.creationDate ?? .now
        }
        static func poster(_ data:Data)->Data? {
            guard let image=UIImage(data:data) else{return nil};let scale=min(1,600/max(image.size.width,image.size.height))
            return UIGraphicsImageRenderer(size:CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))).image{_ in image.draw(in:CGRect(origin:.zero,size:CGSize(width:image.size.width*scale,height:image.size.height*scale)))}.jpegData(compressionQuality:0.55)
        }
        func finish(_ result:Result<SelectedMedia,Error>){DispatchQueue.main.async{self.selected(result)}}
    }
}
enum MediaError:LocalizedError {case unreadable;var errorDescription:String?{"Das ausgewählte Medium konnte nicht gelesen werden. Bitte erneut aus Fotos oder Dateien auswählen."}}
struct FileShareView:UIViewControllerRepresentable {
    let urls:[URL]
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:urls,applicationActivities:nil)}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}
