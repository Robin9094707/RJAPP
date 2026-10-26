import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DocumentFolder:Codable,Identifiable {
    let id:String
    let parentID:String?
    let name:String
    let ownerID:String
    enum CodingKeys:String,CodingKey {case id,name;case parentID="parent_id",ownerID="owner_id"}
}
struct SharedDocument:Codable,Identifiable {
    let id:String
    let folderID:String?
    let assetID:String
    let ownerID:String
    let filename:String
    let mimeType:String
    let sizeBytes:Int64
    let createdAt:String
    enum CodingKeys:String,CodingKey {case id,filename;case folderID="folder_id",assetID="asset_id",ownerID="owner_id",mimeType="mime_type",sizeBytes="size_bytes",createdAt="created_at"}
}
struct DocumentLibrary:Codable {
    var folders:[DocumentFolder]=[]
    var files:[SharedDocument]=[]
    var favorites:[String]=[]
}
extension APIClient {
    func documents() async throws -> DocumentLibrary {try await execute(try request(path:"/v1/documents",method:"GET"),as:DocumentLibrary.self)}
    func documentAction(_ action:String,body:[String:Any]) async throws -> DocumentLibrary {
        try await execute(try request(path:"/v1/documents/"+action,method:"POST",body:JSONSerialization.data(withJSONObject:body)),as:DocumentLibrary.self)
    }
    func removeDocument(kind:String,id:String) async throws {_ = try await execute(try request(path:"/v1/documents/\(kind)/\(id)",method:"DELETE"),as:EmptyResponse.self)}
    func documentFile(_ document:SharedDocument) async throws -> URL {
        let (file,response)=try await session.download(for:request(path:"/v1/assets/"+document.assetID,method:"GET"))
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {throw APIClientError.transport("Dieses Dokument ist nicht mehr verfügbar.")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("rj-document-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let name=URL(fileURLWithPath:document.filename).lastPathComponent
        let destination=directory.appendingPathComponent(name == "." || name == ".." ? "Dokument" : name)
        try FileManager.default.moveItem(at:file,to:destination)
        try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:destination.path)
        return destination
    }
}

struct DocumentsView:View {
    var folderID:String?=nil
    var highlightID:String?=nil
    @Environment(AppState.self) private var app
    @State private var library=DocumentLibrary()
    @State private var loading=true
    @State private var busy=false
    @State private var progress=0.0
    @State private var error:String?
    @State private var query=""
    @State private var importing=false
    @State private var newFolder=false
    @State private var name=""
    @State private var deleteFile:SharedDocument?
    @State private var deleteFolder:DocumentFolder?
    @State private var preview:DocumentPreviewItem?
    private var title:String {library.folders.first {$0.id == folderID}?.name ?? "Dokumente"}
    private var folders:[DocumentFolder] {library.folders.filter {$0.parentID == folderID && (query.isEmpty || $0.name.localizedStandardContains(query))}}
    private var files:[SharedDocument] {library.files.filter {$0.folderID == folderID && (query.isEmpty || $0.filename.localizedStandardContains(query))}}
    var body:some View {
        ScrollViewReader {reader in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:18) {
                    if folderID == nil {
                        VStack(alignment:.leading,spacing:12) {
                            LoveIcon(symbol:"folder.fill",tint:LovePalette.blue,size:52)
                            Text("Alles für uns.").font(.system(size:30,weight:.medium,design:.serif))
                            Text("Ein gemeinsamer Platz für eure Unterlagen. Neue Uploads kommen per Bark direkt zum passenden Ordner.").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(library.folders.count) Ordner · \(library.files.count) Dateien").font(.caption.bold()).foregroundStyle(LovePalette.blue)
                        }.loveCard()
                    }
                    if busy {VStack(alignment:.leading,spacing:8) {ProgressView(value:progress);Text("Datei wird übertragen …").font(.caption)}.loveCard()}
                    if let error {VStack(alignment:.leading,spacing:8) {Text(error).font(.subheadline).foregroundStyle(.orange);Button("Erneut laden") {Task {await load()}}}.loveCard()}
                    if loading {ProgressView("Eure Dokumente laden …").frame(maxWidth:.infinity)}
                    if folderID == nil,query.isEmpty,!library.favorites.isEmpty {
                        LoveSectionTitle("Deine Favoriten")
                        ForEach(library.folders.filter {library.favorites.contains($0.id)}) {folder in folderRow(folder)}
                    }
                    if !folders.isEmpty {
                        LoveSectionTitle("Ordner")
                        ForEach(folders) {folder in folderRow(folder)}
                    }
                    if !files.isEmpty {
                        LoveSectionTitle("Dateien")
                        ForEach(files) {file in fileRow(file).id(file.id)}
                    }
                    if !loading,files.isEmpty,folders.isEmpty {ContentUnavailableView(query.isEmpty ? "Platz für eure Dokumente" : "Kein Treffer",systemImage:"folder",description:Text(query.isEmpty ? "Lege einen Ordner an oder lade eine Datei hoch." : "Versuche einen anderen Dateinamen."))}
                }.padding(20)
            }.onChange(of:loading) {_,value in if !value,let id=highlightID {withAnimation {reader.scrollTo(id,anchor:.center)}}}
        }.background(LoveBackground()).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"In diesem Ordner suchen")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button("Datei hochladen",systemImage:"square.and.arrow.up") {importing=true}
                    Button("Ordner anlegen",systemImage:"folder.badge.plus") {name="";newFolder=true}
                    Button("Aktualisieren",systemImage:"arrow.clockwise") {Task {await load()}}
                } label:{Image(systemName:"plus.circle.fill").frame(width:44,height:44)}.disabled(busy).accessibilityLabel("Dokumente verwalten")
            }
        }
        .safeAreaInset(edge:.bottom) {
            Button("Datei hochladen",systemImage:"square.and.arrow.up") {importing=true}.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy).frame(maxWidth:.infinity).padding(12).background(.ultraThinMaterial)
        }
        .refreshable {await load()}
        .task(id:folderID) {await load()}
        .sheet(isPresented:$importing) {SharedDocumentPicker {result in importing=false;switch result {case .success(let file):Task {await upload(file)};case .failure(let issue):if !(issue is CancellationError) {error=issue.localizedDescription}}}}
        .sheet(item:$preview,onDismiss:{preview=nil}) {item in DocumentQuickLook(url:item.url)}
        .alert("Neuer Ordner",isPresented:$newFolder) {
            TextField("Ordnername",text:$name)
            Button("Anlegen") {Task {await createFolder()}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Button("Abbrechen",role:.cancel) {}
        }
        .confirmationDialog("Dokument für beide entfernen?",isPresented:Binding(get:{deleteFile != nil},set:{if !$0 {deleteFile=nil}}),titleVisibility:.visible) {
            if let file=deleteFile {Button("Dokument entfernen",role:.destructive) {Task {await remove(kind:"files",id:file.id)};deleteFile=nil}}
            Button("Abbrechen",role:.cancel) {deleteFile=nil}
        }
        .confirmationDialog("Leeren Ordner entfernen?",isPresented:Binding(get:{deleteFolder != nil},set:{if !$0 {deleteFolder=nil}}),titleVisibility:.visible) {
            if let folder=deleteFolder {Button("Ordner entfernen",role:.destructive) {Task {await remove(kind:"folders",id:folder.id)};deleteFolder=nil}}
            Button("Abbrechen",role:.cancel) {deleteFolder=nil}
        }
    }
    private func folderRow(_ folder:DocumentFolder)->some View {
        HStack(spacing:12) {
            NavigationLink {DocumentsView(folderID:folder.id)} label: {
                HStack(spacing:12) {
                    LoveIcon(symbol:"folder.fill",tint:LovePalette.blue)
                    VStack(alignment:.leading,spacing:4) {
                        Text(folder.name).font(.headline).foregroundStyle(.primary)
                        Text("\(library.files.filter {$0.folderID == folder.id}.count) Dateien").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.buttonStyle(.plain)
            Button {Task {await favorite(folder)}} label:{Image(systemName:library.favorites.contains(folder.id) ? "star.fill":"star").foregroundStyle(LovePalette.coral).frame(width:44,height:44)}.disabled(busy).accessibilityLabel("Favorit für "+folder.name+" ändern")
            if folder.ownerID == app.me?.id {Menu {Button("Leeren Ordner entfernen",systemImage:"trash",role:.destructive) {deleteFolder=folder}} label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Ordneroptionen")}
        }.loveCard()
    }
    private func fileRow(_ file:SharedDocument)->some View {
        HStack(spacing:12) {
            Button {Task {await open(file)}} label:{
                HStack(spacing:12) {
                    LoveIcon(symbol:file.mimeType.contains("pdf") ? "doc.richtext":"doc.fill",tint:LovePalette.blue)
                    VStack(alignment:.leading,spacing:5) {
                        Text(file.filename).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount:file.sizeBytes,countStyle:.file)+" · "+(file.ownerID == app.me?.id ? "Von dir":"Von "+(app.partner?.displayName ?? "Schatzi"))).font(.caption).foregroundStyle(.secondary)
                        if let date=file.createdAt.rjDate {Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.tertiary)}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.buttonStyle(.plain).disabled(busy)
            if file.ownerID == app.me?.id {Menu {Button("Für beide entfernen",systemImage:"trash",role:.destructive) {deleteFile=file}} label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Dateioptionen")}
        }.loveCard().overlay {if file.id == highlightID {RoundedRectangle(cornerRadius:26).stroke(LovePalette.blue.opacity(0.5),lineWidth:2).allowsHitTesting(false)}}
    }
    private func load() async {loading=true;defer {loading=false};do {library=try await app.api.documents();error=nil} catch {self.error=error.localizedDescription}}
    private func createFolder() async {
        do {library=try await app.api.documentAction("folders",body:["name":name,"parent_id":folderID as Any? ?? NSNull()]);error=nil} catch {self.error=error.localizedDescription}
    }
    private func favorite(_ folder:DocumentFolder) async {
        busy=true;defer {busy=false}
        do {library=try await app.api.documentAction("favorite",body:["folder_id":folder.id,"favorite":!library.favorites.contains(folder.id)]);error=nil} catch {self.error=error.localizedDescription}
    }
    private func remove(kind:String,id:String) async {busy=true;defer {busy=false};do {try await app.api.removeDocument(kind:kind,id:id);await load()} catch {self.error=error.localizedDescription}}
    private func upload(_ file:URL) async {
        busy=true;progress=0;defer {busy=false;try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        var asset:String?
        do {
            let type=UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let supported:Set<String>=["application/pdf","text/plain","text/csv","application/zip","application/msword","application/vnd.openxmlformats-officedocument.wordprocessingml.document","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","image/jpeg","image/png","image/heic","image/heif","video/mp4","video/quicktime","audio/mp4","audio/m4a"]
            let id=try await app.api.uploadAsset(file:file,mime:supported.contains(type) ? type:"application/octet-stream") {value in Task {@MainActor in progress=value}}
            asset=id
            library=try await app.api.documentAction("files",body:["asset_id":id,"folder_id":folderID as Any? ?? NSNull()]);error=nil;Haptics.success()
        } catch {
            self.error=error.localizedDescription
            // A document reference protects a successfully committed upload even if its response was lost.
            if let asset {_ = try? await app.api.execute(try app.api.request(path:"/v1/assets/"+asset,method:"DELETE"),as:EmptyResponse.self)}
        }
    }
    private func open(_ file:SharedDocument) async {busy=true;defer {busy=false};do {preview=DocumentPreviewItem(url:try await app.api.documentFile(file));error=nil} catch {self.error=error.localizedDescription}}
}
private struct DocumentPreviewItem:Identifiable {let id=UUID();let url:URL}
private struct DocumentQuickLook:UIViewControllerRepresentable {
    let url:URL
    func makeCoordinator()->Coordinator {Coordinator(url)}
    func makeUIViewController(context:Context)->QLPreviewController {let view=QLPreviewController();view.dataSource=context.coordinator;return view}
    func updateUIViewController(_ view:QLPreviewController,context:Context) {}
    static func dismantleUIViewController(_ view:QLPreviewController,coordinator:Coordinator) {try? FileManager.default.removeItem(at:coordinator.url.deletingLastPathComponent())}
    final class Coordinator:NSObject,QLPreviewControllerDataSource {
        let url:URL
        init(_ url:URL) {self.url=url}
        func numberOfPreviewItems(in controller:QLPreviewController)->Int {1}
        func previewController(_ controller:QLPreviewController,previewItemAt index:Int)->QLPreviewItem {url as NSURL}
    }
}
private struct SharedDocumentPicker:UIViewControllerRepresentable {
    let selected:(Result<URL,Error>)->Void
    func makeCoordinator()->Coordinator {Coordinator(selected)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.item],asCopy:true);picker.allowsMultipleSelection=false;picker.delegate=context.coordinator;return picker}
    func updateUIViewController(_ picker:UIDocumentPickerViewController,context:Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let selected:(Result<URL,Error>)->Void
        init(_ selected:@escaping(Result<URL,Error>)->Void) {self.selected=selected}
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {selected(.failure(CancellationError()))}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
            guard let url=urls.first else {selected(.failure(CancellationError()));return}
            let access=url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
            do {
                let directory=FileManager.default.temporaryDirectory.appendingPathComponent("rj-upload-"+UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let target=directory.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at:url,to:target);selected(.success(target))
            } catch {selected(.failure(error))}
        }
    }
}
