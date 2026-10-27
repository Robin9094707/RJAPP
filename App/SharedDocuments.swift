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
        try await DocumentFileCache.shared.previewCopy(document,api:self)
    }
}

enum DocumentSort: String, CaseIterable {
    case name="Name", newest="Neueste zuerst", size="Größe", type="Dateityp"
}
struct DocumentEditTarget:Identifiable {
    let id:String
    let kind:String
    let name:String
    let parentID:String?
}
struct DocumentsView:View {
    var folderID:String?=nil
    var highlightID:String?=nil
    @Environment(AppState.self) private var app
    @State private var library=DocumentLibrary()
    @State private var loading=true
    @State private var busy=false
    @State private var progress:Double?=nil
    @State private var transferLabel:String?
    @State private var error:String?
    @State private var query=""
    @State private var importing=false
    @State private var newFolder=false
    @State private var name=""
    @State private var deleteFile:SharedDocument?
    @State private var deleteFolder:DocumentFolder?
    @State private var preview:DocumentPreviewItem?
    @State private var renameTarget:DocumentEditTarget?
    @State private var moveTarget:DocumentEditTarget?
    @State private var information:SharedDocument?
    @State private var sort:DocumentSort = .name
    @State private var searchEverywhere=false
    @AppStorage("rjlove.documents-grid") private var grid=false
    private var title:String {library.folders.first {$0.id == folderID}?.name ?? "Dokumente"}
    private var folders:[DocumentFolder] {
        library.folders.filter { ($0.parentID == folderID || searchEverywhere && !query.isEmpty) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var files:[SharedDocument] {
        library.files.filter { ($0.folderID == folderID || searchEverywhere && !query.isEmpty) && (query.isEmpty || $0.filename.localizedStandardContains(query)) }
            .sorted { a,b in
                switch sort {
                case .name: return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
                case .newest: return a.createdAt == b.createdAt ? a.id < b.id : a.createdAt > b.createdAt
                case .size: return a.sizeBytes == b.sizeBytes ? a.id < b.id : a.sizeBytes > b.sizeBytes
                case .type: return a.mimeType == b.mimeType ? a.filename.localizedStandardCompare(b.filename) == .orderedAscending : a.mimeType < b.mimeType
                }
            }
    }
    var body:some View {
        ScrollViewReader {reader in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:18) {
                    if folderID == nil {
                        VStack(alignment:.leading,spacing:12) {
                            LoveIcon(symbol:"folder.fill",tint:LovePalette.blue,size:52)
                            Text("Alles für uns.").font(.system(size:30,weight:.medium,design:.serif))
                            Text("Eure Dateien, übersichtlich an einem Ort. Mit Bild- und PDF-Vorschauen, Ordnern und direktem Teilen.").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(library.folders.count) Ordner · \(library.files.count) Dateien").font(.caption.bold()).foregroundStyle(LovePalette.blue)
                        }.loveCard()
                    }
                    HStack {
                        Menu { Picker("Sortierung",selection:$sort) { ForEach(DocumentSort.allCases,id:\.self) { Text($0.rawValue).tag($0) } } } label:{Label(sort.rawValue,systemImage:"arrow.up.arrow.down")}
                        Spacer()
                        Button {grid.toggle()} label:{Image(systemName:grid ? "list.bullet":"square.grid.2x2").frame(width:44,height:44)}.accessibilityLabel(grid ? "Listenansicht":"Rasteransicht")
                    }.font(.subheadline)
                    if !query.isEmpty {Toggle("Alle Ordner durchsuchen",isOn:$searchEverywhere).font(.subheadline)}
                    if let transferLabel {VStack(alignment:.leading,spacing:8) {ProgressView(value:progress);Text(transferLabel).font(.caption)}.loveCard()}
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
                        if grid {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                                ForEach(files) {file in fileTile(file).id(file.id)}
                            }
                        } else { ForEach(files) {file in fileRow(file).id(file.id)} }
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
        .sheet(item:$preview) {item in DocumentPreviewScreen(item:item)}
        .sheet(item:$moveTarget) {target in DocumentMovePicker(library:library,target:target) { destination in
            moveTarget=nil;Task {await change("move",target:target,values:["folder_id":destination as Any? ?? NSNull()])}
        }}
        .alert("Umbenennen",isPresented:Binding(get:{renameTarget != nil},set:{if !$0 {renameTarget=nil}})) {
            TextField("Name",text:$name)
            Button("Speichern") {if let target=renameTarget {let value=name;Task {await change("rename",target:target,values:["name":value])}};renameTarget=nil}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Button("Abbrechen",role:.cancel) {renameTarget=nil}
        } message:{Text("Bei Dateien die Dateiendung beibehalten, damit sie weiterhin richtig geöffnet werden.")}
        .alert("Dateiinformationen",isPresented:Binding(get:{information != nil},set:{if !$0 {information=nil}})) {Button("OK") {information=nil}} message:{
            if let file=information {Text(file.filename+"\n"+ByteCountFormatter.string(fromByteCount:file.sizeBytes,countStyle:.file)+"\n"+file.mimeType+"\nOrdner: "+folderPath(file.folderID))}
        }
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
            if folder.ownerID == app.me?.id {Menu {
                Button("Umbenennen",systemImage:"pencil") {beginRename(DocumentEditTarget(id:folder.id,kind:"folders",name:folder.name,parentID:folder.parentID))}
                Button("Verschieben",systemImage:"folder") {moveTarget=DocumentEditTarget(id:folder.id,kind:"folders",name:folder.name,parentID:folder.parentID)}
                Button("Leeren Ordner entfernen",systemImage:"trash",role:.destructive) {deleteFolder=folder}
            } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.accessibilityLabel("Ordneroptionen")}
        }.loveCard()
    }
    private func fileRow(_ file:SharedDocument)->some View {
        HStack(spacing:12) {
            Button {Task {await open(file)}} label:{
                HStack(spacing:12) {
                    DocumentThumbnail(file:file,api:app.api).frame(width:64,height:72)
                    VStack(alignment:.leading,spacing:5) {
                        Text(file.filename).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount:file.sizeBytes,countStyle:.file)+" · "+(file.ownerID == app.me?.id ? "Von dir":"Von "+(app.partner?.displayName ?? "Schatzi"))).font(.caption).foregroundStyle(.secondary)
                        if let date=file.createdAt.rjDate {Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.tertiary)}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.buttonStyle(.plain).disabled(busy)
            fileMenu(file)

        }.loveCard().overlay {if file.id == highlightID {RoundedRectangle(cornerRadius:26).stroke(LovePalette.blue.opacity(0.5),lineWidth:2).allowsHitTesting(false)}}
    }
    private func fileMenu(_ file:SharedDocument)->some View {
        Menu {
            Button("Vorschau & Teilen",systemImage:"eye") {Task {await open(file)}}
            Button("Informationen",systemImage:"info.circle") {information=file}
            if file.ownerID == app.me?.id {
                Button("Umbenennen",systemImage:"pencil") {beginRename(DocumentEditTarget(id:file.id,kind:"files",name:file.filename,parentID:file.folderID))}
                Button("Verschieben",systemImage:"folder") {moveTarget=DocumentEditTarget(id:file.id,kind:"files",name:file.filename,parentID:file.folderID)}
                Divider()
                Button("Für beide entfernen",systemImage:"trash",role:.destructive) {deleteFile=file}
            }
        } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}.disabled(busy).accessibilityLabel("Optionen für "+file.filename)
    }
    private func fileTile(_ file:SharedDocument)->some View {
        VStack(alignment:.leading,spacing:8) {
            Button {Task {await open(file)}} label:{DocumentThumbnail(file:file,api:app.api).frame(height:130)}.buttonStyle(.plain).disabled(busy).accessibilityLabel("Vorschau für "+file.filename)
            Text(file.filename).font(.subheadline.bold()).lineLimit(2).frame(height:40,alignment:.topLeading)
            HStack {Text(ByteCountFormatter.string(fromByteCount:file.sizeBytes,countStyle:.file)).font(.caption).foregroundStyle(.secondary);Spacer(minLength:0);fileMenu(file)}
        }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
    }
    private func folderPath(_ id:String?)->String {
        var parts:[String]=[];var current=id;var visited=Set<String>()
        while let value=current,visited.insert(value).inserted,let folder=library.folders.first(where:{$0.id==value}) {parts.insert(folder.name,at:0);current=folder.parentID}
        return (["Dokumente"]+parts).joined(separator:" / ")
    }
    private func beginRename(_ target:DocumentEditTarget) {name=target.name;renameTarget=target}
    private func change(_ action:String,target:DocumentEditTarget,values:[String:Any]) async {
        guard !busy else {return};busy=true;defer {busy=false}
        do {library=try await app.api.documentAction(action,body:values.merging(["kind":target.kind,"id":target.id]) {$1});error=nil;Haptics.success()}
        catch {self.error=error.localizedDescription}
    }
    private func load() async {
        guard !busy else {return};loading=true;defer {loading=false}
        do {library=try await app.api.documents();error=nil} catch {if !Task.isCancelled {self.error=error.localizedDescription}}
    }
    private func createFolder() async {
        guard !busy else {return};busy=true;defer {busy=false}
        do {library=try await app.api.documentAction("folders",body:["name":name,"parent_id":folderID as Any? ?? NSNull()]);error=nil} catch {self.error=error.localizedDescription}
    }
    private func favorite(_ folder:DocumentFolder) async {
        busy=true;defer {busy=false}
        do {library=try await app.api.documentAction("favorite",body:["folder_id":folder.id,"favorite":!library.favorites.contains(folder.id)]);error=nil} catch {self.error=error.localizedDescription}
    }
    private func remove(kind:String,id:String) async {guard !busy else{return};busy=true;defer {busy=false};do {try await app.api.removeDocument(kind:kind,id:id);library=try await app.api.documents();error=nil} catch {self.error=error.localizedDescription}}
    private func upload(_ file:URL) async {
        busy=true;progress=0;transferLabel="Datei wird hochgeladen …";defer {busy=false;transferLabel=nil;try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
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
    private func open(_ file:SharedDocument) async {guard !busy else{return};busy=true;progress=nil;transferLabel="Dokument wird geladen …";defer {busy=false;transferLabel=nil};do {preview=DocumentPreviewItem(url:try await app.api.documentFile(file),name:file.filename);error=nil} catch {self.error=error.localizedDescription}}
}
private struct DocumentPreviewItem:Identifiable {let id=UUID();let url:URL;let name:String}
private struct DocumentPreviewScreen:View {
    let item:DocumentPreviewItem
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            Group {
                if QLPreviewController.canPreview(item.url as NSURL) {DocumentQuickLook(url:item.url)}
                else {ContentUnavailableView("Keine Vorschau für diesen Dateityp",systemImage:"doc",description:Text("Über Teilen kannst du die Originaldatei sichern oder in einer anderen App öffnen."))}
            }.navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("Fertig") {dismiss()}}
                    ToolbarItem(placement:.primaryAction) {ShareLink(item:item.url).accessibilityLabel("Datei teilen oder sichern")}
                }
        }.onDisappear {try? FileManager.default.removeItem(at:item.url.deletingLastPathComponent())}
    }
}
private struct DocumentMovePicker:View {
    let library:DocumentLibrary
    let target:DocumentEditTarget
    let selected:(String?)->Void
    @Environment(\.dismiss) private var dismiss
    private func path(_ folder:DocumentFolder)->String {
        var parts=[folder.name];var current=folder.parentID;var visited:Set<String>=[folder.id]
        while let id=current,visited.insert(id).inserted,let parent=library.folders.first(where:{$0.id==id}) {parts.insert(parent.name,at:0);current=parent.parentID}
        return parts.joined(separator:" / ")
    }
    private func allowed(_ folder:DocumentFolder)->Bool {
        guard target.kind == "folders" else {return true}
        var current:String?=folder.id;var visited=Set<String>()
        while let id=current,visited.insert(id).inserted {if id==target.id{return false};current=library.folders.first(where:{$0.id==id})?.parentID}
        return true
    }
    var body:some View {
        NavigationStack {
            List {
                Section {Text(target.name).font(.headline)}
                Section("Zielordner auswählen") {
                    Button {selected(nil)} label:{Label("Dokumente (Hauptordner)",systemImage:"folder")}.disabled(target.parentID==nil)
                    ForEach(library.folders.filter(allowed).sorted {path($0).localizedStandardCompare(path($1)) == .orderedAscending}) {folder in
                        Button {selected(folder.id)} label:{Label(path(folder),systemImage:"folder")}.disabled(folder.id==target.parentID)
                    }
                }
            }.navigationTitle("Verschieben").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Abbrechen") {dismiss()}}}
        }
    }
}
private struct DocumentQuickLook:UIViewControllerRepresentable {
    let url:URL
    func makeCoordinator()->Coordinator {Coordinator(url)}
    func makeUIViewController(context:Context)->QLPreviewController {let view=QLPreviewController();view.dataSource=context.coordinator;return view}
    func updateUIViewController(_ view:QLPreviewController,context:Context) {}
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

