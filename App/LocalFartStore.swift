import AVFoundation
import CryptoKit
import Foundation
import Observation

struct SavedFart:Codable,Identifiable {var id:String{clip.id};let clip:FartClip;let filename:String;let savedAt:String}
@MainActor @Observable final class LocalFartStore {
    static let shared=LocalFartStore()
    var clips:[SavedFart]=[]
    private var folder:URL?
    func configure(server:String,userID:String){let key=SHA256.hash(data:Data((server+userID).utf8)).map{String(format:"%02x",$0)}.joined();let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SavedDuftpost/"+key,isDirectory:true);guard folder != root else{return};folder=root;try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);load()}
    func load(){guard let folder else{return};clips=(try? Data(contentsOf:folder.appendingPathComponent("index.json"))).flatMap{try? JSONDecoder().decode([SavedFart].self,from:$0)} ?? []}
    func audioURL(id:String)->URL?{guard let entry=clips.first(where:{$0.id==id}),let folder else{return nil};let url=folder.appendingPathComponent(entry.filename);return FileManager.default.fileExists(atPath:url.path) ? url:nil}
    func save(_ clip:FartClip,api:APIClient) async throws -> URL {
        guard let folder else{throw MediaError.unreadable}
        let data:Data
        if let local=audioURL(id:clip.id),clips.first(where:{$0.id==clip.id})?.clip.revision==clip.revision{data=try Data(contentsOf:local)}else{data=try await api.fartAudio(id:clip.id)}
        let title=clip.title.map{("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789äöüÄÖÜß-_ ").contains($0) ? $0:"_"}
        let stamp=(clip.recordedAt ?? clip.createdAt).replacingOccurrences(of:":",with:"").replacingOccurrences(of:"/",with:"_")
        let filename=stamp+"-"+String(title.prefix(50))+"-"+String(clip.id.prefix(8))+".m4a"
        let target=folder.appendingPathComponent(filename)
        try data.write(to:target,options:[.atomic,.completeFileProtection])
        try JSONEncoder().encode(clip).write(to:target.appendingPathExtension("json"),options:[.atomic,.completeFileProtection])
        clips.removeAll{$0.id==clip.id};clips.append(SavedFart(clip:clip,filename:filename,savedAt:Date.now.rjISO8601));try persist();return target
    }
    func saveImported(_ clip:FartClip,data:Data)throws {
        guard let folder else{throw MediaError.unreadable};let filename=clip.id+".m4a"
        try data.write(to:folder.appendingPathComponent(filename),options:[.atomic,.completeFileProtection]);try JSONEncoder().encode(clip).write(to:folder.appendingPathComponent(filename+".json"),options:[.atomic,.completeFileProtection]);clips.removeAll{$0.id==clip.id};clips.append(SavedFart(clip:clip,filename:filename,savedAt:Date.now.rjISO8601));try persist()
    }
    func remove(_ clip:SavedFart) throws {guard let folder else{return};try? FileManager.default.removeItem(at:folder.appendingPathComponent(clip.filename));try? FileManager.default.removeItem(at:folder.appendingPathComponent(clip.filename).appendingPathExtension("json"));clips.removeAll{$0.id==clip.id};try persist()}
    private func persist()throws{guard let folder else{return};try JSONEncoder().encode(clips).write(to:folder.appendingPathComponent("index.json"),options:[.atomic,.completeFileProtection])}
}
struct ImportedFartAudio {
    let url:URL
    let duration:Double
    let waveform:[Double]
    static func prepare(_ source:URL) async throws -> ImportedFartAudio {
        let asset=AVURLAsset(url:source);let time=try await asset.load(.duration);let length=min(60,time.seconds)
        guard length.isFinite,length>=0.2,let exporter=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetAppleM4A) else{throw MediaError.unreadable}
        let target=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
        exporter.timeRange=CMTimeRange(start:.zero,duration:CMTime(seconds:length,preferredTimescale:44100))
        try await exporter.export(to:target,as:.m4a)
        let file=try AVAudioFile(forReading:target);var levels:[Double]=[]
        if let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4096){while file.framePosition<file.length{try file.read(into:buffer);guard buffer.frameLength>0 else{break};if let values=buffer.floatChannelData?[0]{var level:Float=0;for index in 0..<Int(buffer.frameLength){level=max(level,abs(values[index]))};levels.append(Double(level))}}}
        let waveform=(0..<min(80,levels.count)).map{index in let start=index*levels.count/min(80,levels.count);let end=max(start+1,(index+1)*levels.count/min(80,levels.count));return levels[start..<min(end,levels.count)].max() ?? 0}
        return ImportedFartAudio(url:target,duration:length,waveform:waveform)
    }
}
