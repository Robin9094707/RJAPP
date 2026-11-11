import AudioToolbox
import AVFoundation
import Foundation
import Observation
import UIKit

struct WalkieList: Decodable { let messages: [WalkieMessage]; let serverTime: String
    enum CodingKeys: String, CodingKey { case messages; case serverTime = "server_time" }
}

extension APIClient {
    /// Long poll: the server answers at once when something is new, otherwise after `wait` seconds.
    func walkieMessages(after: String?, wait: Int) async throws -> WalkieList {
        var req = try request(path: "/v1/walkie", method: "GET")
        var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "wait", value: String(wait))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        url.queryItems = items; req.url = url.url
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
            throw APIClientError.server(status: http.statusCode, message: envelope?.message ?? "Funk nicht erreichbar (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(WalkieList.self, from: data)
    }
    func sendWalkie(id: String, assetID: String, duration: Double) async throws -> WalkieMessage {
        let body = try JSONSerialization.data(withJSONObject: ["id": id, "asset_id": assetID, "duration": duration])
        return try await execute(try request(path: "/v1/walkie", method: "POST", body: body), as: WalkieMessage.self)
    }
    func markWalkiePlayed(id: String) async throws {
        _ = try await execute(try request(path: "/v1/walkie/\(id)/played", method: "POST", body: Data("{}".utf8)), as: EmptyResponse.self)
    }
    func deleteWalkie(id: String) async throws {
        _ = try await execute(try request(path: "/v1/walkie/\(id)", method: "DELETE"), as: EmptyResponse.self)
    }
}

/// Walkie-talkie without Apple's Push-to-Talk entitlement: hold to talk, release to send.
/// While both apps are open, a long poll delivers messages within a moment. Unheard messages
/// play out loud as soon as the app is in the foreground, unless quiet mode is on.
@MainActor @Observable final class WalkieService: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = WalkieService()
    static let maximumSeconds = 120.0

    private(set) var messages: [WalkieMessage] = []
    private(set) var recording = false
    private(set) var recordDuration = 0.0
    private(set) var level = 0.0
    private(set) var sending = false
    private(set) var playingID: String?
    private(set) var playProgress = 0.0
    private(set) var connected = false
    var error: String?

    var autoplay: Bool {
        get { _ = settingsRevision; return UserDefaults.standard.object(forKey: "rjlove.walkie-autoplay") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rjlove.walkie-autoplay"); settingsRevision += 1 }
    }
    var loud: Bool {
        get { _ = settingsRevision; return UserDefaults.standard.object(forKey: "rjlove.walkie-loud") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rjlove.walkie-loud"); settingsRevision += 1 }
    }
    var roger: Bool {
        get { _ = settingsRevision; return UserDefaults.standard.object(forKey: "rjlove.walkie-roger") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rjlove.walkie-roger"); settingsRevision += 1 }
    }
    private var settingsRevision = 0

    private weak var app: AppState?
    private var pollTask: Task<Void, Never>?
    private var cursor: String?
    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var meterTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?
    private var queue: [WalkieMessage] = []
    private var playedLocally = Set<String>()

    var myID: String? { app?.me?.id }
    var unheard: [WalkieMessage] { messages.filter { $0.targetID == myID && $0.playedAt == nil && !playedLocally.contains($0.id) } }

    func attach(_ app: AppState) { self.app = app }

    // MARK: Live connection

    func start() {
        guard pollTask == nil, let app, app.phase == .authenticated else { return }
        let api = app.api
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let list = try await api.walkieMessages(after: self.cursor, wait: self.cursor == nil ? 0 : 25)
                    guard !Task.isCancelled else { return }
                    self.merge(list.messages, full: self.cursor == nil)
                    self.cursor = list.serverTime
                    self.connected = true; failures = 0
                    self.autoplayIfAllowed()
                } catch {
                    if Task.isCancelled { return }
                    self.connected = false; failures += 1
                    try? await Task.sleep(for: .seconds(min(30, 2 * failures)))
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil; connected = false
        if recording { cancelRecording() }
        stopPlayback(clearQueue: true)
    }

    func reset() {
        stop(); messages = []; cursor = nil; playedLocally = []; error = nil
    }

    /// Called after a normal sync announced unheard messages, e.g. right after opening the app.
    func refresh() {
        if pollTask == nil { start() }
        autoplayIfAllowed()
    }

    private func merge(_ incoming: [WalkieMessage], full: Bool) {
        if full { messages = incoming.filter { $0.deleted != true }.sorted { $0.createdAt < $1.createdAt }; return }
        for message in incoming {
            if message.deleted == true {
                // Recalled by the sender: remove it everywhere, including queue, playback and cache.
                messages.removeAll { $0.id == message.id }
                queue.removeAll { $0.id == message.id }
                if playingID == message.id { stopPlayback(clearQueue: false); playNextInQueue() }
                let cached = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("walkie/" + message.assetID + ".m4a")
                try? FileManager.default.removeItem(at: cached)
                continue
            }
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            else { messages.append(message) }
        }
        messages.sort { $0.createdAt < $1.createdAt }
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    }

    // MARK: Auto play

    func autoplayIfAllowed() {
        guard autoplay, let app, app.phase == .authenticated, app.myStatus?.isQuiet != true,
              UIApplication.shared.applicationState == .active,
              !recording, !app.showingFartRecorder, app.studio.mode != .recording else { return }
        let pending = unheard.filter { candidate in !queue.contains { $0.id == candidate.id } && candidate.id != playingID }
        guard !pending.isEmpty else { return }
        queue.append(contentsOf: pending)
        if playingID == nil { playNextInQueue() }
    }

    private func playNextInQueue() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { await play(next) }
    }

    // MARK: Playback

    func play(_ message: WalkieMessage) async {
        guard let app else { return }
        if playingID == message.id { stopPlayback(clearQueue: true); return }
        stopPlayback(clearQueue: false)
        playingID = message.id; playProgress = 0; error = nil
        do {
            let file = try await cachedAudio(message, api: app.api)
            guard playingID == message.id else { return }
            VoiceNoteService.shared.stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: file)
            player.delegate = self
            player.volume = loud ? 1 : 0.6
            guard player.play() else { throw MediaError.unreadable }
            self.player = player
            Haptics.impact(.soft)
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let player = self.player, player.duration > 0 else { return }
                    self.playProgress = min(1, player.currentTime / player.duration)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            if message.targetID == myID, message.playedAt == nil {
                playedLocally.insert(message.id)
                Task { try? await app.api.markWalkiePlayed(id: message.id) }
            }
        } catch {
            self.error = "Funk konnte nicht abgespielt werden: " + error.localizedDescription
            playingID = nil
            playNextInQueue()
        }
    }

    func stopPlayback(clearQueue: Bool) {
        if clearQueue { queue.removeAll() }
        progressTask?.cancel(); progressTask = nil
        player?.stop(); player = nil; playingID = nil; playProgress = 0
        if !recording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func cachedAudio(_ message: WalkieMessage, api: APIClient) async throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("walkie", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(message.assetID + ".m4a")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let downloaded = try await api.assetFile(id: message.assetID, mime: "audio/mp4")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: downloaded, to: target)
        return target
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.progressTask?.cancel(); self.progressTask = nil
            self.player = nil; self.playingID = nil; self.playProgress = 0
            if self.queue.isEmpty {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } else {
                try? await Task.sleep(for: .milliseconds(450))
                self.playNextInQueue()
            }
        }
    }

    // MARK: Recording

    func beginRecording() async {
        guard !recording, !sending else { return }
        guard await AVAudioApplication.requestRecordPermission() else { error = "Bitte erlaube den Mikrofonzugriff in den iPhone-Einstellungen."; return }
        stopPlayback(clearQueue: false)
        VoiceNoteService.shared.stop()
        error = nil
        do {
            if roger { AudioServicesPlaySystemSound(1113) }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("walkie-" + UUID().uuidString + ".m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 32000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maximumSeconds) else { throw MediaError.unreadable }
            self.recorder = recorder; recordURL = url; recording = true; recordDuration = 0; level = 0
            Haptics.impact(.medium)
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    self.recordDuration = recorder.currentTime
                    self.level = max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 30)))
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        } catch {
            self.error = "Aufnahme konnte nicht starten: " + error.localizedDescription
            recording = false
        }
    }

    func cancelRecording() {
        meterTask?.cancel(); meterTask = nil
        recorder?.stop(); recorder = nil
        if let recordURL { try? FileManager.default.removeItem(at: recordURL) }
        recordURL = nil; recording = false; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stops the recorder and sends the message. Very short taps are discarded.
    func finishRecording() async {
        guard recording, let recorder, let url = recordURL else { return }
        let duration = recorder.currentTime
        meterTask?.cancel(); meterTask = nil
        recorder.stop(); self.recorder = nil; recording = false; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if roger { AudioServicesPlaySystemSound(1114) }
        guard duration >= 0.6 else {
            try? FileManager.default.removeItem(at: url); recordURL = nil
            error = "Halte die Taste gedrückt, solange du sprichst."
            Haptics.warning(); return
        }
        recordURL = nil
        await send(file: url, duration: min(duration, Self.maximumSeconds))
    }

    private func send(file: URL, duration: Double) async {
        guard let app else { return }
        sending = true; defer { sending = false }
        let id = UUID().uuidString
        do {
            let asset = try await app.api.uploadAsset(file: file, mime: "audio/mp4") { _ in }
            let message = try await app.api.sendWalkie(id: id, assetID: asset, duration: duration)
            // Keep a local copy so the sender can listen again without a download.
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("walkie", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let cached = folder.appendingPathComponent(asset + ".m4a")
            try? FileManager.default.removeItem(at: cached)
            try? FileManager.default.moveItem(at: file, to: cached)
            merge([message], full: false)
            Haptics.success()
        } catch {
            try? FileManager.default.removeItem(at: file)
            self.error = "Funk nicht gesendet: " + error.localizedDescription
            Haptics.warning()
        }
    }

    func delete(_ message: WalkieMessage) async {
        guard let app, message.senderID == myID else { return }
        do {
            try await app.api.deleteWalkie(id: message.id)
            messages.removeAll { $0.id == message.id }
        } catch { self.error = error.localizedDescription }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Reached the two-minute limit while the button is still held: send what was recorded.
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder, self.recording else { return }
            await self.finishRecording()
        }
    }
}
