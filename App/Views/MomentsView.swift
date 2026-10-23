import PhotosUI
import SwiftUI
import UIKit
struct MomentsView:View {
    @Environment(AppState.self) private var app
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
    private var moments:[SharedRecord]{app.moments.filter{albumID.isEmpty || $0.payload.albumID==albumID}.sorted{($0.payload.capturedAt ?? $0.createdAt)>($1.payload.capturedAt ?? $1.createdAt)}}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:20){
            VStack(alignment:.leading,spacing:12){LoveEyebrow(text:"Unsere kleine Ewigkeit");Text("Momente, die bleiben.").font(.system(size:32,weight:.medium,design:.serif));Text("Fotos, Videos und echte Live Photos. In unseren Alben, auf unserem Server.").foregroundStyle(.secondary);StorageSummaryView()}.loveCard()
            Button("Moment aufnehmen",systemImage:"camera.fill"){camera=true}.buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink { InstantGalleryView() } label: { Label("Unser BeReal-Verlauf",systemImage:"camera.on.rectangle.fill") }.buttonStyle(.bordered)
            HStack{Button("Moment hinzufügen",systemImage:"plus"){picker=true}.buttonStyle(.borderedProminent);Button("Album",systemImage:"folder.badge.plus"){albumName="";newAlbum=true}.buttonStyle(.bordered)}
            ScrollView(.horizontal,showsIndicators:false){HStack{Button("Alle Momente"){albumID=""}.buttonStyle(.bordered).tint(albumID.isEmpty ? LovePalette.pink:LovePalette.violet);ForEach(albums){album in Button(album.payload.title ?? "Album"){albumID=album.id}.buttonStyle(.bordered).tint(albumID==album.id ? LovePalette.pink:LovePalette.violet).contextMenu{Button("Umbenennen"){albumName=album.payload.title ?? "";renameAlbum=album};Button("Album entfernen",role:.destructive){deleteAlbum=album}}}}}
            if MediaTransfer.shared.busy{ProgressView(value:MediaTransfer.shared.progress);Text("Upload \(Int(MediaTransfer.shared.progress*100)) %").font(.caption)}
            if moments.isEmpty{ContentUnavailableView("Unser nächster Lieblingsmoment",systemImage:"photo.stack.fill",description:Text("Teilt ein Foto, Video oder Live Photo miteinander."))}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){ForEach(moments){moment in Button{selected=moment}label:{MomentTile(moment:moment)}.buttonStyle(.plain)}}
        }.padding(18)}.background(LoveBackground()).navigationTitle("Unsere Momente")
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button("Moment hinzufügen",systemImage:"plus"){picker=true}}}
            .sheet(isPresented:$picker,onDismiss:{pending=queuedMedia;queuedMedia=nil}){MediaPicker{result in picker=false;switch result{case .success(let media):queuedMedia=media;case .failure(let error):if error is CancellationError{return};app.alert=AppAlert(title:"Medium nicht geladen",message:error.localizedDescription)}}}
            .fullScreenCover(isPresented:$camera,onDismiss:{pending=queuedMedia;queuedMedia=nil}){MomentCameraView{result in camera=false;switch result{case .success(let media):queuedMedia=media;case .failure(let error):if !(error is CancellationError){app.alert=AppAlert(title:"Fotoaufnahme",message:error.localizedDescription)}}}}
            .sheet(item:$pending){MediaComposer(media:$0,kind:.moment)}
            .sheet(item:$selected){MomentDetailView(initialMoment:$0)}
            .alert("Unser neues Album",isPresented:$newAlbum){TextField("Albumname",text:$albumName);Button("Anlegen"){Task{if let album=await app.saveRecord(kind:.album,payload:RecordPayload(title:albumName)){albumID=album.id}}}.disabled(albumName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty);Button("Abbrechen",role:.cancel){}}
            .alert("Album umbenennen",isPresented:Binding(get:{renameAlbum != nil},set:{if !$0{renameAlbum=nil}})){TextField("Albumname",text:$albumName);Button("Speichern"){if let album=renameAlbum{Task{_ = await app.saveRecord(id:album.id,kind:.album,payload:RecordPayload(title:albumName))}};renameAlbum=nil}.disabled(albumName.isEmpty);Button("Abbrechen",role:.cancel){renameAlbum=nil}}
            .alert("Album entfernen?",isPresented:Binding(get:{deleteAlbum != nil},set:{if !$0{deleteAlbum=nil}})){Button("Album entfernen",role:.destructive){if let album=deleteAlbum{Task{_ = await app.deleteRecord(album)}};albumID="";deleteAlbum=nil};Button("Abbrechen",role:.cancel){deleteAlbum=nil}}message:{Text("Die Fotos und Videos bleiben unter Alle Momente erhalten.")}
            .task{await app.loadRecordArchive(kind:.moment);await app.loadRecordArchive(kind:.album)}
    }
}
struct StorageSummaryView:View {
    @Environment(AppState.self) private var app
    var body:some View{VStack(alignment:.leading,spacing:6){Text("Gemeinsam belegt: "+ByteCountFormatter.string(fromByteCount:Int64(app.storageByUser.values.reduce(0,+)),countStyle:.file)).font(.subheadline.bold());ForEach(app.storageByUser.keys.sorted(),id:\.self){id in Text((id==app.me?.id ? "Du":app.partner?.displayName ?? id)+": "+ByteCountFormatter.string(fromByteCount:Int64(app.storageByUser[id] ?? 0),countStyle:.file)).font(.caption).foregroundStyle(.secondary)}}}
}
private struct MomentTile: View {
    let moment: SharedRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let data = imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [LovePalette.cyan.opacity(0.3), LovePalette.pink.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "photo.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(height: 165)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text(moment.payload.caption?.isEmpty == false ? moment.payload.caption! : "Unser Moment")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack {
                    Label("\(moment.payload.reactions?.count ?? 0)", systemImage: "heart.fill")
                    Spacer()
                    Label("\(moment.payload.comments?.count ?? 0)", systemImage: "bubble.left.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var imageData: Data? {
        (moment.payload.posterBase64 ?? moment.payload.imageBase64).flatMap { Data(base64Encoded: $0) }
    }
}

private struct MomentComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let imageData: Data
    @State private var caption = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .listRowInsets(EdgeInsets())
                }
                TextField("Was macht diesen Moment besonders?", text: $caption, axis: .vertical)
                    .lineLimit(3...7)
            }
            .navigationTitle("Moment teilen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Teilen") {
                        saving = true
                        Task {
                            var payload = RecordPayload()
                            payload.caption = caption
                            payload.imageBase64 = imageData.base64EncodedString()
                            payload.mimeType = "image/jpeg"
                            payload.comments = []
                            payload.reactions = []
                            if await appState.saveRecord(kind: .moment, payload: payload) != nil { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

struct MomentDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var editingMetadata=false
    @State private var moment: SharedRecord
    @State private var comment = ""
    @State private var deleting = false
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
                    if moment.payload.assetIDs?.isEmpty == false {MediaAttachmentView(record:moment)}
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
                    Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash") }
                }
            }
            .sheet(isPresented:$editingMetadata){MomentMetadataEditor(record:moment)}
            .onChange(of:appState.records){_,records in if let current=records.first(where:{$0.id==moment.id}){moment=current}}
            .alert("Moment für euch beide löschen?", isPresented: $deleting) {
                Button("Löschen", role: .destructive) {
                    Task { if await appState.deleteRecord(moment) { dismiss() } }
                }
                Button("Abbrechen", role: .cancel) {}
            }
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
