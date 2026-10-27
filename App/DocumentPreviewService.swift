import CryptoKit
import QuickLookThumbnailing
import UIKit
import SwiftUI
import UniformTypeIdentifiers

extension SharedDocument {
    var symbol: String {
        if mimeType.hasPrefix("image/") { return "photo.fill" }
        if mimeType.hasPrefix("video/") { return "video.fill" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("spreadsheet") || filename.lowercased().hasSuffix(".csv") { return "tablecells" }
        if mimeType.contains("zip") { return "doc.zipper" }
        if mimeType.hasPrefix("text/") { return "doc.text" }
        return "doc.fill"
    }
    var supportsAutomaticThumbnail: Bool {
        sizeBytes > 0 && sizeBytes <= 15 * 1024 * 1024 &&
        (mimeType.hasPrefix("image/") || mimeType.contains("pdf"))
    }
}

/// Download once per account/asset/name, with at most two simultaneous transfers.
/// Preview copies have their own lifetime, so eviction cannot break Quick Look.
actor DocumentFileCache {
    static let shared = DocumentFileCache()
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("RJDocumentCache", isDirectory:true)
    private var inFlight: [String: Task<URL,Error>] = [:]
    private var activeDownloads = 0
    private var generation = UUID()
    private func digest(_ value:String) -> String { SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",$0) }.joined() }
    func file(_ document:SharedDocument, api:APIClient) async throws -> URL {
        let request = try api.request(path:"/v1/assets/"+document.assetID, method:"GET")
        let key = digest((request.url?.absoluteString ?? "") + (request.value(forHTTPHeaderField:"Authorization") ?? "") + document.filename)
        let directory = root.appendingPathComponent(key,isDirectory:true)
        let rawName = URL(fileURLWithPath:document.filename).lastPathComponent
        var name = rawName.isEmpty || rawName == "." || rawName == ".." ? "Dokument" : rawName
        if URL(fileURLWithPath:name).pathExtension.isEmpty, let ext=UTType(mimeType:document.mimeType)?.preferredFilenameExtension { name += "."+ext }
        let destination=directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath:destination.path) { return destination }
        if let task=inFlight[key] { return try await task.value }
        let current=generation
        let task=Task { try await self.download(request, api:api, destination:destination, generation:current) }
        inFlight[key]=task
        defer { if generation == current { inFlight[key]=nil } }
        return try await task.value
    }
    private func download(_ request:URLRequest, api:APIClient, destination:URL, generation expected:UUID) async throws -> URL {
        while activeDownloads >= 2 { try await Task.sleep(for:.milliseconds(100)) }
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        activeDownloads += 1
        defer { activeDownloads -= 1 }
        let (temporary,response)=try await api.session.download(for:request)
        defer { try? FileManager.default.removeItem(at:temporary) }
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        guard let http=response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard http.statusCode == 200 else {
            throw APIClientError.server(status:http.statusCode,message:http.statusCode == 404 ? "Die Datei wurde entfernt. Bitte den Ordner aktualisieren." : http.statusCode == 401 ? "Deine Anmeldung ist abgelaufen. Bitte in der App erneut anmelden." : "Die Datei konnte nicht geladen werden (HTTP \(http.statusCode)).")
        }
        prune()
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.moveItem(at:temporary,to:destination)
        try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:destination.path)
        return destination
    }
    func previewCopy(_ document:SharedDocument, api:APIClient) async throws -> URL {
        let cached=try await file(document,api:api)
        try Task.checkCancellation()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("rj-document-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let copy=directory.appendingPathComponent(cached.lastPathComponent)
        do { try FileManager.default.copyItem(at:cached,to:copy); return copy }
        catch { try? FileManager.default.removeItem(at:directory); throw error }
    }
    private func prune() {
        let keys:Set<URLResourceKey>=[.fileSizeKey,.contentModificationDateKey]
        let files=(FileManager.default.enumerator(at:root,includingPropertiesForKeys:Array(keys))?.allObjects as? [URL] ?? []).compactMap { url -> (URL,Int,Date)? in
            guard let values=try? url.resourceValues(forKeys:keys),let size=values.fileSize else { return nil }
            return (url,size,values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes=files.reduce(0) { $0+$1.1 }
        for (url,size,date) in files where bytes > 150*1024*1024 || Date.now.timeIntervalSince(date)>86400 {
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent()); bytes -= size
        }
    }
    func clear() {
        generation=UUID()
        inFlight.values.forEach { $0.cancel() }; inFlight.removeAll()
        try? FileManager.default.removeItem(at:root)
    }
}

struct DocumentThumbnail: View {
    let file:SharedDocument
    let api:APIClient
    @State private var image:UIImage?
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:12).fill(LovePalette.blue.opacity(0.09))
            if let image { Image(uiImage:image).resizable().scaledToFit().padding(3) }
            else { Image(systemName:file.symbol).font(.title2).foregroundStyle(LovePalette.blue) }
        }.accessibilityHidden(true)
        .task(id:file.id+file.filename) {
            image=nil
            guard file.supportsAutomaticThumbnail else { return }
            do {
                let url=try await DocumentFileCache.shared.file(file,api:api)
                try Task.checkCancellation()
                let request=QLThumbnailGenerator.Request(fileAt:url,size:CGSize(width:180,height:180),scale:2,representationTypes:.thumbnail)
                let result:UIImage?=await withCheckedContinuation { continuation in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { representation,_ in continuation.resume(returning:representation?.uiImage) }
                }
                guard !Task.isCancelled else { return }
                image=result
            } catch { /* An unsupported thumbnail never blocks opening the original. */ }
        }
    }
}
