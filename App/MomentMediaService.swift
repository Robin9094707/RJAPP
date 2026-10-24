import AVFoundation
import Foundation
import ImageIO
import UIKit

extension APIClient {
    func playbackURL(assetID:String) async throws -> URL {
        struct Grant:Decodable {let path:String;let ticket:String}
        let grant=try await execute(try request(path:"/v1/assets/\(assetID)/playback",method:"POST",body:Data("{}".utf8)),as:Grant.self)
        guard grant.path=="/media/assets/"+assetID else{throw APIClientError.invalidResponse}
        let req=try request(path:grant.path,method:"GET")
        guard var parts=URLComponents(url:req.url!,resolvingAgainstBaseURL:false) else{throw APIClientError.invalidResponse}
        parts.queryItems=[URLQueryItem(name:"ticket",value:grant.ticket)]
        guard let url=parts.url else{throw APIClientError.invalidResponse};return url
    }
    func momentImageFile(_ record:SharedRecord) async throws -> URL {
        if let id=record.payload.assetIDs?.first {return try await assetFile(id:id,mime:record.payload.mimeType ?? "image/jpeg")}
        if let encoded=record.payload.imageBase64,let data=Data(base64Encoded:encoded) {
            let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg");try data.write(to:file,options:[.atomic,.completeFileProtection]);return file
        }
        let req=try request(path:"/v1/moments/\(record.id)/image",method:"GET")
        let (temporary,response)=try await session.download(for:req)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else{throw MediaError.unreadable}
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg");try FileManager.default.moveItem(at:temporary,to:file);return file
    }
}

/// Small decoded previews only, never full-resolution photos or video files.
final class MomentPreviewCache:@unchecked Sendable {
    static let shared=MomentPreviewCache()
    private let images=NSCache<NSString,UIImage>()
    init(){images.totalCostLimit=24*1024*1024;images.countLimit=100}
    func image(for key:String)->UIImage?{images.object(forKey:key as NSString)}
    func save(_ image:UIImage,key:String){images.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.scale*image.size.height*image.scale*4))}
    func decode(_ encoded:String,key:String) async -> UIImage? {
        if let cached=image(for:key){return cached}
        let result=await Task.detached(priority:.utility){()->UIImage? in
            guard let bytes=Data(base64Encoded:encoded),let source=CGImageSourceCreateWithData(bytes as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:500] as CFDictionary) else{return nil};return UIImage(cgImage:image)
        }.value
        if let result{save(result,key:key)};return result
    }
}

enum MomentPreparation {
    static func videoPoster(file:URL) async -> Data? {
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:file));generator.appliesPreferredTrackTransform=true;generator.maximumSize=CGSize(width:600,height:600)
        guard let image=try? await generator.image(at:CMTime(seconds:0,preferredTimescale:600)) else{return nil}
        return UIImage(cgImage:image.image).jpegData(compressionQuality:0.7)
    }
    static func enrichVideo(_ media:SelectedMedia) async -> SelectedMedia {
        guard media.kind=="video",let file=media.files.first else{return media}
        var result=media;result.poster=await videoPoster(file:file)
        let asset=AVURLAsset(url:file)
        if let metadata=try? await asset.load(.metadata) {
            for item in metadata {
                if result.latitude==nil,item.identifier == .quickTimeMetadataLocationISO6709,let text=try? await item.load(.stringValue) {
                    let pattern="([+-][0-9]+(?:\\.[0-9]+)?)([+-][0-9]+(?:\\.[0-9]+)?)(?:[+-][0-9.]+)?/"
                    if let regex=try? NSRegularExpression(pattern:pattern),let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let a=Range(match.range(at:1),in:text),let b=Range(match.range(at:2),in:text),let lat=Double(text[a]),let lon=Double(text[b]),abs(lat)<=90,abs(lon)<=180{result.latitude=lat;result.longitude=lon}
                }
            }
        }
        return result
    }
    static func compact(_ media:SelectedMedia) async throws -> SelectedMedia {
        guard let original=media.files.first,media.kind != "live" else{return media}
        var result=media
        let destination=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+(media.kind=="video" ? ".mp4":".jpg"))
        do {
            if media.kind=="video" {
                guard let exporter=AVAssetExportSession(asset:AVURLAsset(url:original),presetName:AVAssetExportPreset1920x1080) else{throw MediaError.unreadable}
                exporter.shouldOptimizeForNetworkUse=true
                try await exporter.export(to:destination,as:.mp4)
            }else{
                let data=try await Task.detached(priority:.userInitiated){()->Data in
                    guard let source=CGImageSourceCreateWithURL(original as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:3200] as CFDictionary),let jpeg=UIImage(cgImage:image).jpegData(compressionQuality:0.88) else{throw MediaError.unreadable};return jpeg
                }.value
                try data.write(to:destination,options:.atomic)
            }
            try Task.checkCancellation()
            let before=(try original.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0,after=(try destination.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
            guard after>0,after<before else{try? FileManager.default.removeItem(at:destination);return media}
            result.files=[destination];result.mimeTypes=[media.kind=="video" ? "video/mp4":"image/jpeg"];return result
        }catch{try? FileManager.default.removeItem(at:destination);throw error}
    }
}
