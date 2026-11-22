import AVFoundation
import Foundation
import Observation

private enum GroupWire: Decodable {
    case message(SharedRecord)
    case deleted(String)
    private enum Keys: String, CodingKey { case id, deleted }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .deleted) == true {
            self = .deleted(try container.decode(String.self, forKey: .id))
        } else {
            self = .message(try SharedRecord(from: decoder))
        }
    }
}

private struct GroupList: Decodable {
    let messages: [GroupWire]
    let serverTime: String
    enum CodingKeys: String, CodingKey { case messages; case serverTime = "server_time" }
}

extension APIClient {
    fileprivate func groupMessages(after: String?, wait: Int) async throws -> GroupList {
        var req = try request(path: "/v1/group", method: "GET")
        var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "wait", value: String(wait)), URLQueryItem(name: "limit", value: "120")]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        url.queryItems = items
        req.url = url.url
        req.timeoutInterval = TimeInterval(wait + 15)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(wait + 15)
        configuration.timeoutIntervalForResource = TimeInterval(wait + 20)
        let longPoll = URLSession(configuration: configuration)
        defer { longPoll.finishTasksAndInvalidate() }
        let (data, response) = try await longPoll.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(status: http.statusCode, message: envelope?.message ?? "Gruppenchat nicht erreichbar (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(GroupList.self, from: data)
    }
}

/// Love actions: one tap, ChatGPT writes something for both of you into the group chat.
enum GroupLoveAction: String, CaseIterable, Identifiable {
    case compliment, poem, date, memory, question, plan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compliment: "Komplimente"
        case .poem: "Liebesgedicht"
        case .date: "Date-Idee"
        case .memory: "Weißt du noch?"
        case .question: "Frage für uns"
        case .plan: "Wochenende planen"
        }
    }
    var symbol: String {
        switch self {
        case .compliment: "heart.fill"
        case .poem: "text.quote"
        case .date: "sparkles"
        case .memory: "clock.arrow.circlepath"
        case .question: "questionmark.bubble.fill"
        case .plan: "calendar.badge.plus"
        }
    }
    var prompt: String {
        switch self {
        case .compliment: "Schreib uns beiden je ein liebevolles, konkretes Kompliment, das sich auf etwas bezieht, das wir zuletzt erlebt oder geschrieben haben."
        case .poem: "Schreib ein kurzes, zärtliches Liebesgedicht über uns zwei (höchstens 8 Zeilen), mit einem echten Detail aus unserem App-Wissen."
        case .date: "Schlag uns zwei konkrete Date-Ideen für die nächsten Tage vor, passend zu dem, was wir mögen. Kurz und mit einem Satz warum."
        case .memory: "Erinnere uns liebevoll an einen schönen gemeinsamen Moment aus unserem App-Wissen („Weißt du noch …?“) und frag, was wir daran am meisten mochten."
        case .question: "Stell uns eine schöne, tiefe Frage, die wir beide hier im Chat beantworten können."
        case .plan: "Hilf uns, das kommende Wochenende zu planen: was ansteht, was wir uns wünschen, und ein kleiner Vorschlag für jeden Tag."
        }
    }
}

/// Group chat for both partners with ChatGPT as a third member. Answers are written by the phone
/// that asked (with its own ChatGPT plan) and appear for both. Voice messages are transcribed live on
/// the iPhone, so the text is there for both people and for ChatGPT.
@MainActor
@Observable
final class GroupChatService {
    static let shared = GroupChatService()

    private(set) var messages: [SharedRecord] = []
    private(set) var loading = false
    private(set) var connected = false
    private(set) var sending = false
    private(set) var aiWorking = false
    private(set) var aiPartial = ""
    private(set) var aiStatus: String?
    private(set) var playingID: String?
    var error: String?

    private var cursor: String?
    private var pollTask: Task<Void, Never>?
    private var watchers = 0
    private var player: AVAudioPlayer?
    private weak var app: AppState?

    func attach(_ app: AppState) { self.app = app }

    func start(_ app: AppState) {
        self.app = app
        watchers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel(); pollTask = nil; connected = false
    }

    private func pollLoop() async {
        var failures = 0
        while !Task.isCancelled {
            guard let app else { return }
            do {
                if cursor == nil { loading = messages.isEmpty }
                let list = try await app.api.groupMessages(after: cursor, wait: cursor == nil ? 0 : 20)
                merge(list.messages, full: cursor == nil)
                cursor = list.serverTime
                connected = true; loading = false; failures = 0
            } catch {
                if Task.isCancelled { return }
                connected = false; loading = false; failures += 1
                try? await Task.sleep(for: .seconds(min(15, 2 * failures)))
            }
        }
    }

    private func merge(_ incoming: [GroupWire], full: Bool) {
        var byID = full ? [:] : Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in incoming {
            switch item {
            case .message(let record): byID[record.id] = record
            case .deleted(let id): byID[id] = nil
            }
        }
        messages = byID.values.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }

    private func insert(_ record: SharedRecord) { merge([.message(record)], full: false) }

    // MARK: Sending

    func send(text: String) async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app, !value.isEmpty else { return }
        sending = true; defer { sending = false }
        do {
            var payload = RecordPayload(text: String(value.prefix(8000)))
            payload.referenceID = nil
            insert(try await app.api.upsertRecord(kind: .group, payload: payload))
            Haptics.impact(.light)
            if Self.mentionsAI(value) { await askAI(prompt: value) }
        } catch { self.error = error.localizedDescription; Haptics.warning() }
    }

    func sendVoice(_ result: LiveTranscriber.Result) async {
        guard let app, let file = result.fileURL else { return }
        sending = true; defer { sending = false }
        do {
            let asset = try await app.api.uploadAsset(file: file, mime: "audio/mp4") { _ in }
            var payload = RecordPayload(text: result.text.isEmpty ? nil : String(result.text.prefix(8000)))
            payload.assetIDs = [asset]
            payload.mediaKind = "audio"
            payload.audioSeconds = min(600, max(0.5, result.seconds))
            let record = try await app.api.upsertRecord(kind: .group, payload: payload)
            // Keep a local copy so the sender can listen again without a download.
            let cached = Self.cacheFolder.appendingPathComponent(asset + ".m4a")
            try? FileManager.default.removeItem(at: cached)
            try? FileManager.default.moveItem(at: file, to: cached)
            insert(record)
            Haptics.success()
            if Self.mentionsAI(result.text) { await askAI(prompt: result.text) }
        } catch {
            try? FileManager.default.removeItem(at: file)
            self.error = "Sprachnachricht nicht gesendet: " + error.localizedDescription
            Haptics.warning()
        }
    }

    func delete(_ record: SharedRecord) async {
        guard let app else { return }
        do { try await app.api.deleteRecord(id: record.id); merge([.deleted(record.id)], full: false) }
        catch { self.error = error.localizedDescription }
    }

    static func mentionsAI(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("@ki") || lower.contains("@chatgpt") || lower.hasPrefix("ki,") || lower.hasPrefix("chatgpt,")
    }

    // MARK: ChatGPT in the group

    func askAI(prompt: String? = nil, action: GroupLoveAction? = nil, webSearch: Bool = false) async {
        guard let app, !aiWorking else { return }
        let ai = AICompanion.shared
        guard ai.signedIn else { error = ChatGPTAuthError.notSignedIn.localizedDescription; return }
        aiWorking = true; aiPartial = ""; aiStatus = nil
        defer { aiWorking = false; aiPartial = ""; aiStatus = nil }
        let me = app.me?.displayName ?? "Ich"
        let partner = app.partner?.displayName ?? "Partner"
        var history: [AIPromptMessage] = []
        for record in messages.suffix(40) {
            let text = record.payload.text ?? ""
            guard !text.isEmpty else { continue }
            if record.payload.ai == true { history.append(AIPromptMessage(role: .assistant, content: text)) }
            else {
                let name = record.ownerID == app.me?.id ? me : partner
                let voice = record.payload.mediaKind == "audio" ? " (Sprachnachricht)" : ""
                history.append(AIPromptMessage(role: .user, content: name + voice + ": " + text))
            }
        }
        // Consecutive user turns are fine for the Responses API; the last turn is the actual request.
        let request = action?.prompt ?? ("\(me) fragt dich im Gruppenchat: " + (prompt ?? "Was meinst du dazu?"))
        let system = """
        Du bist ChatGPT als drittes Mitglied im privaten Gruppenchat von \(me) und \(partner) in RJ Love. Sprich beide herzlich und persönlich an, \
        antworte auf Deutsch, eher kurz wie in einem Messenger (höchstens etwa 120 Wörter, außer es wird mehr gewünscht). Beziehe dich auf den Chatverlauf und das App-Wissen, \
        erfinde keine Erlebnisse. Nachrichten im Verlauf beginnen mit dem Namen der Person. Emojis sparsam.
        """
        do {
            let answer = try await ai.askAnswer(request, system: system, app: app, includeContext: true, history: history, webSearch: webSearch,
                                                onStatus: { [weak self] value in self?.aiStatus = value },
                                                onPartial: { [weak self] value in self?.aiPartial = value })
            var payload = RecordPayload(text: String(answer.text.prefix(8000)))
            payload.ai = true
            payload.model = ai.effectiveModel
            payload.requestedBy = app.me?.id
            if !answer.sources.isEmpty, let data = try? JSONEncoder().encode(Array(answer.sources.prefix(8))) {
                payload.sources = String(decoding: data, as: UTF8.self)
            }
            insert(try await app.api.upsertRecord(kind: .group, payload: payload))
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: Voice playback

    static var cacheFolder: URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("group-voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func togglePlayback(_ record: SharedRecord) async {
        if playingID == record.id { player?.stop(); player = nil; playingID = nil; return }
        guard let app, let asset = record.payload.assetIDs?.first else { return }
        do {
            let target = Self.cacheFolder.appendingPathComponent(asset + ".m4a")
            if !FileManager.default.fileExists(atPath: target.path) {
                let downloaded = try await app.api.assetFile(id: asset, mime: "audio/mp4")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: downloaded, to: target)
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player?.stop()
            let next = try AVAudioPlayer(contentsOf: target)
            next.prepareToPlay()
            next.play()
            player = next
            playingID = record.id
            let duration = next.duration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.2))
                if self?.playingID == record.id { self?.playingID = nil }
            }
        } catch { self.error = "Abspielen fehlgeschlagen: " + error.localizedDescription }
    }

    static func sources(of record: SharedRecord) -> [AISource] {
        guard let raw = record.payload.sources, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AISource].self, from: data)) ?? []
    }
}
