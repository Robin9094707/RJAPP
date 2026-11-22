import SwiftUI

/// Unser Gruppenchat: you two plus ChatGPT. Voice messages are transcribed live on the iPhone.
struct GroupChatView: View {
    @Environment(AppState.self) private var app
    @State private var chat = GroupChatService.shared
    @State private var ai = AICompanion.shared
    @State private var transcriber = LiveTranscriber()
    @State private var draft = ""
    @State private var webSearch = false
    @State private var deleting: SharedRecord?
    @FocusState private var focused: Bool

    private var partnerName: String { app.partner?.displayName ?? "Lieblingsmensch" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    header
                    if chat.loading { ProgressView("Gruppenchat wird geladen …").frame(maxWidth: .infinity).padding(30) }
                    else if chat.messages.isEmpty { emptyState }
                    ForEach(chat.messages) { record in
                        GroupBubble(record: record, mine: record.ownerID == app.me?.id, authorName: author(record), playing: chat.playingID == record.id,
                                    play: { Task { await chat.togglePlayback(record) } },
                                    delete: deleteAction(record),
                                    toDiary: { diarySeed = DiaryDraftSeed(text: record.payload.text ?? "") })
                            .id(record.id)
                    }
                    if chat.aiWorking { aiTyping }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.messages.count) { _, _ in withAnimation(LoveMotion.fade) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: chat.aiPartial.count / 60) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(LoveBackground())
        .navigationTitle("Gruppenchat").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if ai.signedIn {
                        Toggle("ChatGPT darf im Internet suchen", systemImage: "globe", isOn: $webSearch)
                        Text("Schreib @KI in eine Nachricht, damit ChatGPT antwortet.")
                    } else {
                        NavigationLink { ChatGPTAccountView() } label: { Label("ChatGPT verbinden", systemImage: "person.badge.key") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { chat.start(app) }
        .onDisappear { chat.stop(); if transcriber.isRunning { transcriber.cancel() } }
        .sheet(item: $diarySeed) { seed in DiaryEditorView(day: DiaryDay.key(.now), seed: seed.text) }
        .confirmationDialog("Nachricht für beide zurückrufen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Zurückrufen", role: .destructive) { if let deleting { Task { await chat.delete(deleting) } }; deleting = nil }
            Button("Abbrechen", role: .cancel) { deleting = nil }
        }
        .alert("Gruppenchat", isPresented: Binding(get: { chat.error != nil }, set: { if !$0 { chat.error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(chat.error ?? "") }
    }
    @State private var diarySeed: DiaryDraftSeed?

    private func deleteAction(_ record: SharedRecord) -> (() -> Void)? {
        guard record.ownerID == app.me?.id else { return nil }
        return { deleting = record }
    }

    private func author(_ record: SharedRecord) -> String {
        let owner = record.ownerID == app.me?.id ? (app.me?.displayName ?? "Du") : partnerName
        return record.payload.ai == true ? "ChatGPT · für \(owner)" : owner
    }

    private var header: some View {
        HStack(spacing: -10) {
            PartnerAvatar(name: app.me?.displayName ?? "Du", size: 36)
            PartnerAvatar(name: partnerName, size: 36)
            Image(systemName: "sparkles").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(LovePalette.dusk, in: Circle()).overlay { Circle().stroke(LoveSurface.card, lineWidth: 2) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.me?.displayName ?? "Du"), \(partnerName) & ChatGPT").font(.subheadline.weight(.semibold)).lineLimit(1)
                Label(chat.connected ? "Live verbunden" : "Verbindet …", systemImage: chat.connected ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark")
                    .font(.caption2).foregroundStyle(chat.connected ? Color.green : Color.secondary)
            }.padding(.leading, 20)
            Spacer()
        }.loveCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(LovePalette.violet)
            Text("Euer Gruppenchat mit ChatGPT").font(.headline)
            Text("Schreibt euch, schickt Sprachnachrichten (werden live mitgeschrieben) und holt ChatGPT dazu: mit @KI oder einem der Herz-Knöpfe unten.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28)
    }

    private var aiTyping: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(chat.aiStatus ?? "ChatGPT schreibt …", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet)
            Text(AIChatBubble.rendered(chat.aiPartial.isEmpty ? "…" : chat.aiPartial)).font(.body)
        }
        .padding(12).frame(maxWidth: 520, alignment: .leading)
        .background(LovePalette.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if transcriber.isRunning { recordingPanel }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GroupLoveAction.allCases) { action in
                            Button { Task { await chat.askAI(action: action, webSearch: webSearch) } } label: {
                                Label(action.title, systemImage: action.symbol).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(LovePalette.pink.opacity(0.1), in: Capsule())
                            }.buttonStyle(.lovePress).foregroundStyle(LovePalette.pink).disabled(!ai.signedIn || chat.aiWorking)
                        }
                    }.padding(.horizontal, 14)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    Button { Task { await transcriber.start(record: true) } } label: {
                        Image(systemName: "mic.fill").font(.headline).frame(width: 40, height: 40).background(LoveSurface.card, in: Circle())
                    }.buttonStyle(.lovePress).accessibilityLabel("Sprachnachricht aufnehmen")
                    TextField("Nachricht · @KI fragt ChatGPT", text: $draft, axis: .vertical)
                        .lineLimit(1...5).focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(LoveSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(LoveSurface.hairline, lineWidth: 0.5) }
                    if ai.signedIn {
                        Button {
                            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); draft = ""
                            Task {
                                if !text.isEmpty { await chat.send(text: text) }
                                await chat.askAI(prompt: text.isEmpty ? nil : text, webSearch: webSearch)
                            }
                        } label: {
                            Image(systemName: "sparkles").font(.headline).foregroundStyle(LovePalette.violet).frame(width: 40, height: 40).background(LovePalette.violet.opacity(0.12), in: Circle())
                        }.buttonStyle(.lovePress).disabled(chat.aiWorking).accessibilityLabel("ChatGPT fragen")
                    }
                    Button {
                        let text = draft; draft = ""
                        Task { await chat.send(text: text) }
                    } label: {
                        Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.white).frame(width: 40, height: 40).background(LovePalette.dusk, in: Circle())
                    }.buttonStyle(.lovePress).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.sending).accessibilityLabel("Senden")
                }.padding(.horizontal, 14)
            }
            if let error = transcriber.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 14) }
        }
        .padding(.vertical, 10).background(.bar)
    }

    private var recordingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10).scaleEffect(1 + transcriber.level * 0.8).animation(.linear(duration: 0.1), value: transcriber.level)
                Text(String(format: "%d:%02d", Int(transcriber.elapsed) / 60, Int(transcriber.elapsed) % 60)).font(.subheadline.monospacedDigit())
                Text(transcriber.onDevice ? "· wird auf dem iPhone mitgeschrieben" : "· wird mitgeschrieben").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(transcriber.transcript.isEmpty ? "Sprich einfach los …" : transcriber.transcript)
                .font(.subheadline).foregroundStyle(transcriber.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(5)
            HStack {
                Button(role: .destructive) { transcriber.cancel() } label: { Label("Verwerfen", systemImage: "trash") }.buttonStyle(.bordered)
                Spacer()
                Button {
                    Task {
                        let result = await transcriber.stop()
                        if result.seconds >= 0.8 { await chat.sendVoice(result) }
                    }
                } label: { Label("Senden", systemImage: "paperplane.fill") }.buttonStyle(.borderedProminent).tint(LovePalette.pink)
            }
        }.padding(14).loveCard().padding(.horizontal, 14)
    }
}

private struct GroupBubble: View {
    let record: SharedRecord
    let mine: Bool
    let authorName: String
    let playing: Bool
    let play: () -> Void
    let delete: (() -> Void)?
    let toDiary: () -> Void

    private var isAI: Bool { record.payload.ai == true }
    private var isVoice: Bool { record.payload.mediaKind == "audio" && record.payload.assetIDs?.isEmpty == false }

    var body: some View {
        HStack(alignment: .bottom) {
            if mine && !isAI { Spacer(minLength: 44) }
            VStack(alignment: mine && !isAI ? .trailing : .leading, spacing: 4) {
                Text(authorName).font(.caption2.weight(.semibold)).foregroundStyle(isAI ? LovePalette.violet : .secondary)
                VStack(alignment: .leading, spacing: 8) {
                    if isVoice {
                        Button(action: play) {
                            HStack(spacing: 10) {
                                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                                Image(systemName: "waveform").font(.title3)
                                Text(String(format: "%.0f s", record.payload.audioSeconds ?? 0)).font(.caption.monospacedDigit())
                            }
                        }.buttonStyle(.plain)
                    }
                    if let text = record.payload.text, !text.isEmpty {
                        if isAI { Text(AIChatBubble.rendered(text)).font(.body) }
                        else { Text(text).font(isVoice ? .subheadline.italic() : .body) }
                    }
                    let sources = GroupChatService.sources(of: record)
                    if !sources.isEmpty { AISourceList(sources: sources) }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(mine && !isAI ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 19, style: .continuous).fill(bubbleStyle)
                }
                .textSelection(.enabled)
                .contextMenu {
                    Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = record.payload.text }
                    Button("Ins Tagebuch übernehmen", systemImage: "book.pages") { toDiary() }
                    if let delete { Button("Für beide zurückrufen", systemImage: "trash", role: .destructive) { delete() } }
                }
                Text((record.createdAt.rjDate ?? .now).formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
            if !mine || isAI { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: mine && !isAI ? .trailing : .leading)
    }

    private var bubbleStyle: AnyShapeStyle {
        if isAI { return AnyShapeStyle(LovePalette.violet.opacity(0.12)) }
        if mine { return AnyShapeStyle(LovePalette.dusk) }
        return AnyShapeStyle(LoveSurface.card)
    }
}

/// Small list of web sources under an answer.
struct AISourceList: View {
    let sources: [AISource]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Quellen", systemImage: "globe").font(.caption2.bold()).foregroundStyle(.secondary)
            ForEach(sources.prefix(6)) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) { Text("\(source.title) · \(source.host)").font(.caption).lineLimit(1) }
                }
            }
        }
    }
}
