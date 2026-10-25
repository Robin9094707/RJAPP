import PhotosUI
import SwiftUI
import UIKit

struct MomentsView:View {
    var captureOnOpen=false
    var mapOnOpen=false
    @Environment(AppState.self) private var app
    @State private var gallery:[SharedRecord]=[]
    @State private var deletion = MomentDeletion()
    @State private var cursor:String?
    @State private var hasMore=true
    @State private var loading=false
    @State private var galleryError:String?
    @State private var pageGeneration=UUID()
    @State private var mapMode=false
    @State private var didOpenCamera=false
    @State private var query=""
    @State private var owner="all"
    @State private var queuedMedia:SelectedMedia?
    @State private var picker=false
    @State private var camera=false
    @State private var pending:SelectedMedia?
    @State private var selected:SharedRecord?
    @State private var albumID=""
    @State private var albumName=""
    @State private var newAlbum=false
    @State private var renameAlbum:SharedRecord?
    @State private var deleteAlbum:SharedRecord?
    private var albums:[SharedRecord]{app.records.filter{$0.kind == .album}.sorted{($0.payload.title ?? "")<($1.payload.title ?? "")}}
    private var currentAlbum:SharedRecord?{albums.first{$0.id==albumID}}
    private var filters:String{[query,owner,albumID].joined(separator:"|")}
    private var selectedOwnerID:String?{if owner=="mine"{return app.me?.id};if owner=="partner"{return app.partner?.id};return nil}

    var body:some View {
        galleryRoot
            .sheet(isPresented:$picker,onDismiss:{pending=queuedMedia;queuedMedia=nil}){MediaPicker{receive($0)}}
            .fullScreenCover(isPresented:$camera,onDismiss:{pending=queuedMedia;queuedMedia=nil}){MomentCameraView{receive($0)}}
            .sheet(item:$pending){MediaComposer(media:$0,kind:.moment)}
            .fullScreenCover(item:$selected){MomentGalleryViewer(records:gallery,initialID:$0.id)}
            .momentDeletionPrompt(deletion) { record in gallery.removeAll { $0.id == record.id } }
            .onChange(of:app.deletedRecordIDs) { _, ids in gallery.removeAll { ids.contains($0.id) } }
            .alert("Unser neues Album",isPresented:$newAlbum){
                TextField("Albumname",text:$albumName)
                Button("Anlegen"){Task{if let album=await app.saveRecord(kind:.album,payload:RecordPayload(title:albumName)){albumID=album.id}}}.disabled(albumName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button("Abbrechen",role:.cancel){}
            }
            .alert("Album umbenennen",isPresented:Binding(get:{renameAlbum != nil},set:{if !$0{renameAlbum=nil}})){
                TextField("Albumname",text:$albumName)
                Button("Speichern"){renameCurrentAlbum()}.disabled(albumName.isEmpty)
                Button("Abbrechen",role:.cancel){renameAlbum=nil}
            }
            .alert("Album entfernen?",isPresented:Binding(get:{deleteAlbum != nil},set:{if !$0{deleteAlbum=nil}})){
                Button("Album entfernen",role:.destructive){removeCurrentAlbum()}
                Button("Abbrechen",role:.cancel){deleteAlbum=nil}
            } message:{Text("Die Fotos und Videos bleiben unter Alle Momente erhalten.")}
            .task{if !didOpenCamera{mapMode=mapOnOpen};if captureOnOpen && !didOpenCamera{didOpenCamera=true;camera=true};await app.loadRecordArchive(kind:.album)}
            .task(id:filters){try? await Task.sleep(for:.milliseconds(250));guard !Task.isCancelled else{return};await loadPage(reset:true)}
            .onChange(of:app.moments.map{$0.id+$0.updatedAt}){_,_ in Task{await loadPage(reset:true)}}
    }
    private var galleryRoot:some View {
        GeometryReader{geometry in
            ScrollView{
                LazyVStack(alignment:.leading,spacing:16){
                    introduction
                    Picker("Ansicht",selection:$mapMode){Text("Galerie").tag(false);Text("Karte").tag(true)}.pickerStyle(.segmented).accessibilityIdentifier("moments-mode")
                    captureControls
                    transferStatus
                    if gallery.isEmpty && !loading {ContentUnavailableView("Unser nächster Lieblingsmoment",systemImage:"photo.stack.fill",description:Text("Teilt ein Foto, Video oder Live Photo miteinander."))}
                    if mapMode {MomentsAtlasView(records:gallery)}
                    else {ForEach(monthGroups,id:\.key){group in
                        MomentMonthGrid(date:group.date,records:group.values,side:CGFloat(GalleryMetrics.tileSide(width:Double(geometry.size.width))),onSelect:{selected=$0},onDelete:{deletion.request($0)})
                    }}
                    paginationStatus
                }.padding(18)
            }.refreshable{await loadPage(reset:true)}
        }.background(LoveBackground()).navigationTitle("Unsere Momente").searchable(text:$query,prompt:"Eure Beschreibungen").toolbar{galleryToolbar}
    }
    private var introduction:some View {
        VStack(alignment:.leading,spacing:6){Text("Unser Leben in Bildern.").font(.system(size:29,weight:.medium,design:.serif));Text("\(gallery.count) Erinnerungen · für immer wir").font(.caption).foregroundStyle(.secondary)}
    }
    private var captureControls:some View {
        HStack{
            Button("Aufnehmen",systemImage:"camera.fill"){camera=true}.buttonStyle(.borderedProminent).accessibilityIdentifier("moments-capture")
            Button("Hinzufügen",systemImage:"plus"){picker=true}.buttonStyle(.bordered)
            Spacer()
            filtersMenu
        }
    }
    private var filtersMenu:some View {
        Menu{
            Picker("Von wem?",selection:$owner){Text("Wir beide").tag("all");Text("Nur meine").tag("mine");Text("Nur von \(app.partner?.displayName ?? "Schatzi")").tag("partner")}
            Picker("Album",selection:$albumID){Text("Alle Momente").tag("");ForEach(albums){Text($0.payload.title ?? "Album").tag($0.id)}}
        }label:{Image(systemName:"line.3.horizontal.decrease.circle")}.accessibilityLabel("Momente filtern")
    }
    @ViewBuilder private var transferStatus:some View {
        if MediaTransfer.shared.busy {ProgressView(value:MediaTransfer.shared.progress);Text("Upload \(Int(MediaTransfer.shared.progress*100)) %").font(.caption)}
    }
    @ViewBuilder private var paginationStatus:some View {
        if let galleryError {Text(galleryError).font(.caption).foregroundStyle(.orange);Button("Erneut laden"){Task{await loadPage(reset:gallery.isEmpty)}}}
        if hasMore && !loading {ProgressView().frame(maxWidth:.infinity).task{await loadPage()}}
        if loading {ProgressView("Momente laden …").frame(maxWidth:.infinity)}
    }
    @ToolbarContentBuilder private var galleryToolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing){
            Menu{
                Button("Album hinzufügen",systemImage:"folder.badge.plus"){albumName="";newAlbum=true}
                NavigationLink{InstantGalleryView()}label:{Label("Unser BeReal",systemImage:"camera.on.rectangle")}
                NavigationLink{EveningPlaylistView(initialVideo:true)}label:{Label("Unsere Filme",systemImage:"play.rectangle")}
                if let album=currentAlbum {
                    Button("Album umbenennen"){albumName=album.payload.title ?? "";renameAlbum=album}
                    Button("Album entfernen",role:.destructive){deleteAlbum=album}
                }
            }label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Alben und weitere Momente")
        }
    }
    private func receive(_ result:Result<SelectedMedia,Error>){
        picker=false;camera=false
        switch result{case .success(let media):queuedMedia=media;case .failure(let error):if !(error is CancellationError){app.alert=AppAlert(title:"Medium",message:error.localizedDescription)}}
    }
    private func renameCurrentAlbum(){
        if let album=renameAlbum {Task{_ = await app.saveRecord(id:album.id,kind:.album,payload:RecordPayload(title:albumName))}}
        renameAlbum=nil
    }
    private func removeCurrentAlbum(){
        if let album=deleteAlbum {Task{_ = await app.deleteRecord(album)}}
        albumID="";deleteAlbum=nil
    }
    private func loadPage(reset:Bool=false) async {
        if !reset && (loading || !hasMore){return}
        if reset {pageGeneration=UUID();cursor=nil;hasMore=true}
        let generation=pageGeneration;loading=true;galleryError=nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview"),!ProcessInfo.processInfo.arguments.contains("--ui-test-server") {gallery=app.moments;hasMore=false;loading=false;return}
        #endif
        do {
            let page=try await app.api.galleryPage(cursor:reset ? nil:cursor,query:query,owner:selectedOwnerID,album:albumID)
            guard generation==pageGeneration,!Task.isCancelled else{return}
            let visible = page.records.filter { !app.deletedRecordIDs.contains($0.id) }
            if reset {gallery=visible}else{let ids=Set(gallery.map(\.id));gallery += visible.filter{!ids.contains($0.id)}}
            cursor=page.nextCursor;hasMore=page.hasMore;loading=false
        }catch{if generation==pageGeneration{galleryError=error.localizedDescription;loading=false;hasMore=false}}
    }
    private var monthGroups:[(key:String,date:Date,values:[SharedRecord])]{
        let calendar=Calendar.current
        let groups=Dictionary(grouping:gallery){record in let date=JournalDates.date(record) ?? .distantPast;let c=calendar.dateComponents([.year,.month],from:date);return calendar.date(from:c) ?? date}
        return groups.keys.sorted(by:>).map{date in (key:date.rjISO8601,date:date,values:groups[date] ?? [])}
    }
}
private struct MomentMonthGrid:View {
    let date:Date
    let records:[SharedRecord]
    let side:CGFloat
    let onSelect:(SharedRecord)->Void
    let onDelete:(SharedRecord)->Void
    private var columns:[GridItem]{Array(repeating:GridItem(.fixed(side),spacing:3),count:3)}
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text(date.formatted(.dateTime.month(.wide).year())).font(.title3.bold()).frame(maxWidth:.infinity,alignment:.leading).padding(.top,12)
            LazyVGrid(columns:columns,spacing:3){ForEach(records){record in MomentGridTile(record:record,side:side){onSelect(record)}
                .contextMenu { Button("Moment öffnen",systemImage:"arrow.up.left.and.arrow.down.right") { onSelect(record) }; Button("Moment löschen",systemImage:"trash",role:.destructive) { onDelete(record) } }
                .accessibilityAction(named: Text("Moment löschen")) { onDelete(record) }}}
        }
    }
}
private struct MomentGridTile:View {
    let record:SharedRecord
    let side:CGFloat
    let action:()->Void
    private var title:String{(record.payload.mediaKind=="video" ? "Video: ":"Foto: ")+(record.payload.caption ?? "Unser Moment")}
    var body:some View {
        Button(action:action){MomentPreview(record:record).frame(width:side,height:side).clipped().contentShape(Rectangle())}
            .buttonStyle(.plain).accessibilityIdentifier("gallery-tile-"+record.id).accessibilityLabel(title)
    }
}
struct StorageSummaryView:View {
    @Environment(AppState.self) private var app
    var body:some View{VStack(alignment:.leading,spacing:6){Text("Gemeinsam belegt: "+ByteCountFormatter.string(fromByteCount:Int64(app.storageByUser.values.reduce(0,+)),countStyle:.file)).font(.subheadline.bold());ForEach(app.storageByUser.keys.sorted(),id:\.self){id in Text((id==app.me?.id ? "Du":app.partner?.displayName ?? id)+": "+ByteCountFormatter.string(fromByteCount:Int64(app.storageByUser[id] ?? 0),countStyle:.file)).font(.caption).foregroundStyle(.secondary)}}}
}
struct MomentDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var editingMetadata=false
    @State private var moment: SharedRecord
    @State private var comment = ""
    @State private var deletion = MomentDeletion()
    @State private var commentToDelete: MomentComment?
    @State private var saving = false

    init(initialMoment: SharedRecord) {
        _moment = State(initialValue: initialMoment)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let encoded = moment.payload.imageBase64,
                       let data = Data(base64Encoded: encoded),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    if moment.payload.assetIDs?.isEmpty == false || moment.payload.legacyImage==true {MediaAttachmentView(record:moment)}
                    Text(moment.payload.caption?.isEmpty == false ? moment.payload.caption! : "Unser Moment")
                        .font(.title2.bold())

                    Button("Beschreibung, Datum & Album",systemImage:"pencil"){editingMetadata=true}
                    PhotoPlaceView(payload:moment.payload)
                    reactionRow
                    commentsSection
                }
                .padding(18)
            }
            .background(LoveBackground())
            .navigationTitle("Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Moment löschen",systemImage:"trash",role: .destructive) { deletion.request(moment) }.labelStyle(.iconOnly).disabled(deletion.busy)
                }
            }
            .sheet(isPresented:$editingMetadata){MomentMetadataEditor(record:moment)}
            .onChange(of:appState.records){_,records in if let current=records.first(where:{$0.id==moment.id}){moment=current}}
            .momentDeletionPrompt(deletion) { _ in dismiss() }
            .confirmationDialog(
                "Kommentar wirklich löschen?",
                isPresented: Binding(
                    get: { commentToDelete != nil },
                    set: { if !$0 { commentToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Kommentar löschen", role: .destructive) {
                    guard let value = commentToDelete else { return }
                    deleteComment(value)
                    commentToDelete = nil
                }
                Button("Abbrechen", role: .cancel) { commentToDelete = nil }
            } message: {
                Text("Der Kommentar wird aus diesem gemeinsamen Moment entfernt.")
            }
        }
    }

    private var reactionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            LoveSectionTitle("Reaktionen")
            HStack(spacing: 10) {
                ForEach(["❤️", "🥰", "😂", "🥹", "✨"], id: \.self) { emoji in
                    Button(emoji) { toggleReaction(emoji) }
                        .font(.title2)
                        .padding(9)
                        .background(hasMyReaction(emoji) ? LovePalette.pink.opacity(0.22) : Color.secondary.opacity(0.09), in: Circle())
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mit \(emoji) reagieren")
                }
            }
            if let reactions = moment.payload.reactions, !reactions.isEmpty {
                Text("\(reactions.count) Reaktion\(reactions.count == 1 ? "" : "en")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .loveCard()
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LoveSectionTitle("Kommentare")
            if let comments = moment.payload.comments, !comments.isEmpty {
                ForEach(comments) { value in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(value.authorName).font(.caption.bold()).foregroundStyle(LovePalette.cyan)
                            Spacer()
                            if let date = value.createdAt.rjDate {
                                Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Button(role: .destructive) {
                                commentToDelete = value
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                            .accessibilityLabel("Kommentar von \(value.authorName) löschen")
                        }
                        Text(value.text).font(.subheadline)
                    }
                    .padding(11)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            } else {
                Text("Noch kein Kommentar – schreib etwas Süßes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Kommentar", text: $comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addComment()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .loveCard()
    }

    private func hasMyReaction(_ emoji: String) -> Bool {
        guard let me = appState.me?.id else { return false }
        return moment.payload.reactions?.contains { $0.authorID == me && $0.emoji == emoji } == true
    }

    private func toggleReaction(_ emoji: String) {
        guard let me = appState.me?.id else { return }
        var payload = moment.payload
        var values = payload.reactions ?? []
        if let index = values.firstIndex(where: { $0.authorID == me && $0.emoji == emoji }) {
            values.remove(at: index)
        } else {
            values.removeAll { $0.authorID == me }
            values.append(MomentReaction(authorID: me, emoji: emoji))
        }
        payload.reactions = values
        save(payload)
    }

    private func addComment() {
        guard let me = appState.me else { return }
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var payload = moment.payload
        var comments = payload.comments ?? []
        comments.append(
            MomentComment(id: UUID().uuidString, authorID: me.id, authorName: me.displayName, text: String(value.prefix(500)), createdAt: Date.now.rjISO8601)
        )
        payload.comments = comments
        comment = ""
        save(payload)
    }

    private func deleteComment(_ value: MomentComment) {
        var payload = moment.payload
        payload.comments?.removeAll { $0.id == value.id }
        save(payload)
    }

    private func save(_ payload: RecordPayload) {
        saving = true
        Task {
            if let saved = await appState.saveRecord(id: moment.id, kind: .moment, payload: payload) {
                moment = saved
            }
            saving = false
        }
    }
}

struct MomentMetadataEditor:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record:SharedRecord
    @State private var caption=""
    @State private var date=Date.now
    @State private var albumID=""
    @State private var saving=false
    var body:some View {NavigationStack{Form{
        TextField("Unser Moment in Worten",text:$caption,axis:.vertical)
        DatePicker("Aufgenommen",selection:$date,in:...Date.now)
        if record.kind == .moment{Picker("Album",selection:$albumID){Text("Alle Momente").tag("");ForEach(app.records.filter{$0.kind == .album}){Text($0.payload.title ?? "Album").tag($0.id)}}}
    }.navigationTitle("Unseren Moment beschreiben").toolbar{ToolbarItem(placement:.cancellationAction){Button("Abbrechen"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Speichern"){saving=true;Task{var payload=record.payload;payload.caption=caption;payload.capturedAt=date.rjISO8601;if record.kind == .moment{payload.albumID=albumID.isEmpty ? nil:albumID};if await app.saveRecord(id:record.id,kind:record.kind,payload:payload) != nil{dismiss()};saving=false}}.disabled(saving)}}.onAppear{caption=record.payload.caption ?? "";date=min((record.payload.capturedAt ?? record.createdAt).rjDate ?? .now,.now);albumID=record.payload.albumID ?? ""}}}
}

