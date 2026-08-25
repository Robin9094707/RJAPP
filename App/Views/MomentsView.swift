import PhotosUI
import SwiftUI
import UIKit

struct MomentsView: View {
    @Environment(AppState.self) private var appState
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: Data?
    @State private var selectedMoment: SharedRecord?
    @State private var loadingImage = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                introCard
                if appState.moments.isEmpty {
                    ContentUnavailableView(
                        "Euer erstes Kapitel wartet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Teilt einen Lieblingsmoment mit Bild, Text, Reaktionen und Kommentaren.")
                    )
                    .loveCard()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.moments) { moment in
                            Button { selectedMoment = moment } label: {
                                MomentTile(moment: moment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(LoveBackground())
        .navigationTitle("Unsere Momente")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    if loadingImage { ProgressView() } else { Image(systemName: "plus") }
                }
                .accessibilityLabel("Moment hinzufügen")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            loadingImage = true
            Task {
                defer { loadingImage = false; pickerItem = nil }
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let compressed = compressMomentImage(raw) else {
                    appState.alert = AppAlert(title: "Foto nicht geladen", message: "Das ausgewählte Bild konnte nicht verarbeitet werden.")
                    return
                }
                pendingImage = compressed
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingImage != nil },
            set: { if !$0 { pendingImage = nil } }
        )) {
            if let pendingImage {
                MomentComposerView(imageData: pendingImage)
            }
        }
        .sheet(item: $selectedMoment) { moment in
            MomentDetailView(initialMoment: moment)
        }
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.palette)
                .foregroundStyle(LovePalette.pink, LovePalette.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nur für euch zwei")
                    .font(.headline)
                Text("Fotos werden verkleinert und direkt auf deinem privaten RJ-Love-Server gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .loveCard()
    }

    private func compressMomentImage(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximum: CGFloat = 1600
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, maximum / max(longEdge, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.78)
    }
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
        moment.payload.imageBase64.flatMap { Data(base64Encoded: $0) }
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

private struct MomentDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var moment: SharedRecord
    @State private var comment = ""
    @State private var deleting = false
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
                    Text(moment.payload.caption?.isEmpty == false ? moment.payload.caption! : "Unser Moment")
                        .font(.title2.bold())

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
            .alert("Moment für euch beide löschen?", isPresented: $deleting) {
                Button("Löschen", role: .destructive) {
                    Task { if await appState.deleteRecord(moment) { dismiss() } }
                }
                Button("Abbrechen", role: .cancel) {}
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
