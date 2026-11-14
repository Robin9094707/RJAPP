import SwiftUI

/// All saved conversations of this iPhone.
struct AIChatListView: View {
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var opened: UUID?
    @State private var renaming: AIConversation?
    @State private var newTitle = ""

    var body: some View {
        List {
            if !ai.signedIn {
                Section { AISignInPrompt() }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            } else {
                Section {
                    Button { open(ai.newConversation()) } label: { Label("Neues Gespräch", systemImage: "square.and.pencil").font(.headline) }
                    Button { open(ai.newConversation(usesContext: false)) } label: { Label("Neues Gespräch ohne App-Wissen", systemImage: "eye.slash") }.font(.subheadline)
                } footer: { Text("Modell: \(ai.modelName)") }
            }
            if !ai.conversations.isEmpty {
                Section("Eure Gespräche") {
                    ForEach(ai.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(conversation.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if !conversation.usesContext { Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary) }
                                }
                                Text(conversation.messages.last?.text ?? "Noch leer").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(conversation.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                            }.padding(.vertical, 3)
                        }
                        .swipeActions {
                            Button("Löschen", systemImage: "trash", role: .destructive) { ai.delete(conversation.id) }
                            Button("Umbenennen", systemImage: "pencil") { newTitle = conversation.title; renaming = conversation }.tint(LovePalette.violet)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(LoveBackground())
        .navigationTitle("KI-Chat").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { AIChatView(conversationID: $0) }
        .navigationDestination(item: $opened) { AIChatView(conversationID: $0) }
        .toolbar {
            if ai.signedIn {
                ToolbarItem(placement: .topBarTrailing) { Button { open(ai.newConversation()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("Neues Gespräch") }
            }
        }
        .alert("Gespräch umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $newTitle)
            Button("Speichern") { if let renaming { ai.rename(renaming.id, to: newTitle) }; renaming = nil }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
    }

    private func open(_ conversation: AIConversation) { opened = conversation.id }
}

/// Starts a chat directly: used by shortcuts and the companion hub.
struct AIChatEntryView: View {
    @State private var ai = AICompanion.shared
    @State private var conversationID: UUID?
    var starter: String? = nil
    var body: some View {
        Group {
            if !ai.signedIn { ScrollView { AISignInPrompt().padding(LoveMetrics.screenPadding) }.background(LoveBackground()).navigationTitle("KI-Chat") }
            else if let conversationID { AIChatView(conversationID: conversationID, starter: starter) }
            else { ProgressView() }
        }
        .onAppear {
            guard conversationID == nil, ai.signedIn else { return }
            if starter == nil, let recent = ai.conversations.first, recent.messages.isEmpty { conversationID = recent.id }
            else { conversationID = ai.newConversation().id }
        }
        .onChange(of: ai.signedIn) { _, signedIn in if signedIn && conversationID == nil { conversationID = ai.newConversation().id } }
    }
}

struct AIChatView: View {
    let conversationID: UUID
    var starter: String? = nil
    @Environment(AppState.self) private var app
    @State private var ai = AICompanion.shared
    @State private var draft = ""
    @State private var partial = ""
    @State private var status: String?
    @State private var sending = false
    @State private var task: Task<Void, Never>?
    @State private var diaryText: DiaryDraftSeed?
    @State private var sentToPartner = false
    @State private var usedStarter = false
    @FocusState private var focused: Bool

    private var conversation: AIConversation? { ai.conversation(conversationID) }
    private var partnerName: String { app.partner?.displayName ?? "deinen Lieblingsmenschen" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if conversation?.messages.isEmpty != false && !sending { welcome }
                    ForEach(conversation?.messages ?? []) { message in
                        AIChatBubble(message: message, partnerName: partnerName, onDiary: { diaryText = DiaryDraftSeed(text: message.text) }, onSend: { Task { await sendToPartner(message.text) } }, onRetry: retryAction(message))
                            .id(message.id)
                    }
                    if sending {
                        if let status { Label(status, systemImage: status.contains("Internet") ? "globe" : "sparkles").font(.caption).foregroundStyle(LovePalette.violet) }
                        AIChatBubble(message: AIChatMessage(role: .assistant, text: partial.isEmpty ? "" : partial), partnerName: partnerName, streaming: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation?.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: partial.count / 80) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(LoveBackground())
        .navigationTitle(conversation?.title ?? "KI-Chat").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { optionsMenu } }
        .sheet(item: $diaryText) { seed in DiaryEditorView(day: DiaryDay.key(.now), seed: seed.text) }
        .alert("An \(partnerName) gesendet 💌", isPresented: $sentToPartner) { Button("OK", role: .cancel) {} }
        .onAppear {
            if let starter, !usedStarter, conversation?.messages.isEmpty != false { usedStarter = true; draft = starter; send() }
        }
        .onDisappear { if !sending { task = nil } }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LoveIcon(symbol: "wand.and.sparkles", tint: LovePalette.violet, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hallo \(app.me?.displayName ?? "")!").font(.loveDisplay(24))
                    Text(conversation?.usesContext == false ? "Ohne App-Wissen: ein ganz normales ChatGPT-Gespräch." : "Ich kenne eure Momente, euer Tagebuch, Pläne und das Duftstudio.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Probier zum Beispiel:").font(.caption.bold()).foregroundStyle(.secondary)
            FlowChips(items: suggestions) { suggestion in draft = suggestion; send() }
        }.loveCard()
    }

    private var suggestions: [String] {
        [
            "Wie war unsere letzte Woche?",
            "Schreib mir eine liebe Nachricht für \(partnerName).",
            "Plane uns ein schönes Date für dieses Wochenende.",
            "Was steht bei uns demnächst an?",
            "Welche Wünsche haben wir noch offen?",
            "Kür das beste Duftwerk des Monats. 🏆",
            "Gib mir eine Tagebuchfrage für heute Abend.",
        ]
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(sending ? "Antwort entsteht …" : "Frag deinen KI-Begleiter …", text: $draft, axis: .vertical)
                .lineLimit(1...6).focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(LoveSurface.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LoveSurface.hairline, lineWidth: 0.5) }
                .submitLabel(.send)
                .accessibilityIdentifier("ai-chat-input")
            Button {
                if sending { task?.cancel() } else { send() }
            } label: {
                Image(systemName: sending ? "stop.fill" : "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(sending ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(LovePalette.dusk), in: Circle())
            }
            .buttonStyle(.lovePress)
            .disabled(!sending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(sending ? "Antwort stoppen" : "Senden")
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
    }

    private var optionsMenu: some View {
        Menu {
            if !ai.models.isEmpty {
                Picker("Modell", selection: Binding(get: { ai.effectiveModel }, set: { ai.model = $0 })) {
                    ForEach(ai.models) { Text($0.name).tag($0.id) }
                }
            }
            Picker("Denktiefe", selection: Binding(get: { ai.effort }, set: { ai.effort = $0 })) {
                ForEach(AIEffort.allCases) { Text($0.title).tag($0) }
            }
            Toggle("App-Wissen verwenden", isOn: Binding(get: { conversation?.usesContext ?? true }, set: { ai.setUsesContext($0, for: conversationID) }))
            Toggle("Im Internet suchen", systemImage: "globe", isOn: Binding(get: { conversation?.usesWeb == true }, set: { ai.setUsesWeb($0, for: conversationID) }))
            Divider()
            if let last = conversation?.messages.last(where: { $0.role == .assistant && $0.failed != true }) {
                Button("Letzte Antwort ins Tagebuch", systemImage: "book.pages") { diaryText = DiaryDraftSeed(text: last.text) }
                Button("Letzte Antwort kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = last.text }
            }
            Button("Gespräch löschen", systemImage: "trash", role: .destructive) { ai.delete(conversationID) }
        } label: {
            Label(ai.modelName, systemImage: "slider.horizontal.3")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""
        partial = ""
        sending = true
        Haptics.impact(.light)
        task = Task { @MainActor in
            do {
                try await ai.send(text, in: conversationID, app: app, onStatus: { value in status = value }) { value in partial = value }
                Haptics.success()
            } catch {
                if !(error is CancellationError) { Haptics.warning() }
            }
            sending = false
            partial = ""
            status = nil
        }
    }

    private func retryAction(_ message: AIChatMessage) -> (() -> Void)? {
        guard message.failed == true else { return nil }
        return { retry(message) }
    }

    private func retry(_ failed: AIChatMessage) {
        guard let messages = conversation?.messages, let index = messages.firstIndex(where: { $0.id == failed.id }), index > 0 else { return }
        let question = messages[..<index].last { $0.role == .user }?.text ?? ""
        ai.removeFailedMessage(failed.id, in: conversationID)
        draft = question
        send()
    }

    private func sendToPartner(_ text: String) async {
        var payload = RecordPayload(text: String(text.prefix(4000)))
        payload.notificationPriority = "normal"
        if await app.saveRecord(kind: .chat, payload: payload) != nil { sentToPartner = true }
    }
}

struct DiaryDraftSeed: Identifiable { let id = UUID(); let text: String }

struct AIChatBubble: View {
    let message: AIChatMessage
    let partnerName: String
    var streaming = false
    var onDiary: (() -> Void)? = nil
    var onSend: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    private var mine: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                Group {
                    if streaming && message.text.isEmpty {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Denkt nach …").font(.subheadline).foregroundStyle(.secondary) }
                    } else {
                        Text(Self.rendered(message.text)).font(.body).textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .background {
                    if mine { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LovePalette.dusk) }
                    else if message.failed == true { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange.opacity(0.14)) }
                    else { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LoveSurface.card) }
                }
                .overlay { if !mine { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(LoveSurface.hairline, lineWidth: 0.5) } }
                .contextMenu {
                    Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                    if !streaming, message.failed != true {
                        if let onDiary { Button("Ins Tagebuch übernehmen", systemImage: "book.pages") { onDiary() } }
                        if let onSend { Button("An \(partnerName) senden", systemImage: "paperplane") { onSend() } }
                    }
                }
                if let onRetry { Button("Erneut versuchen", systemImage: "arrow.clockwise", action: onRetry).font(.caption).buttonStyle(.bordered) }
                if let sources = message.sources, !sources.isEmpty, !streaming { AISourceList(sources: sources).padding(.horizontal, 6) }
                if !streaming, !mine, message.failed != true, let model = message.model {
                    Text(model + " · " + message.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !mine { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    /// Inline Markdown (bold, italics, links) while keeping line breaks and lists readable.
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Wrapping suggestion chips.
struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item).font(.subheadline).multilineTextAlignment(.leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LovePalette.violet.opacity(0.1), in: Capsule())
                        .overlay { Capsule().strokeBorder(LovePalette.violet.opacity(0.2), lineWidth: 0.6) }
                }.buttonStyle(.lovePress).foregroundStyle(.primary)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// Shown wherever AI needs a signed-in ChatGPT account.
struct AISignInPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LoveIcon(symbol: "wand.and.sparkles", tint: LovePalette.violet, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("KI ist optional.").font(.headline)
                    Text("Melde dich einmal mit ChatGPT an, um Chat und Tagebuch-Hilfe über dein Abo zu nutzen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            NavigationLink { ChatGPTAccountView() } label: { Label("Mit ChatGPT verbinden", systemImage: "person.badge.key.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(LovePalette.violet)
        }.loveCard()
    }
}
