import AVFoundation
import Foundation
import Observation
@preconcurrency import PushToTalk
import UIKit

struct RadioJoin: Decodable {
    let cursor: Int
    let backgroundPushConfigured: Bool
    enum CodingKeys: String, CodingKey { case cursor; case backgroundPushConfigured = "background_push_configured" }
}
struct RadioEvent: Decodable, Identifiable {
    let seq: Int
    let transmissionID: String
    let userID: String
    let kind: String
    let audioBase64: String?
    let text: String
    let speaker: String
    var id: Int { seq }
    enum CodingKeys: String, CodingKey { case seq, kind, text, speaker; case transmissionID = "transmission_id"; case userID = "user_id"; case audioBase64 = "audio_base64" }
}
struct RadioFeed: Decodable {
    let events: [RadioEvent]
    let cursor: Int
    let speakerID: String?
    let backgroundPushConfigured: Bool
    enum CodingKeys: String, CodingKey { case events, cursor; case speakerID = "speaker_id"; case backgroundPushConfigured = "background_push_configured" }
}

@MainActor @Observable final class WalkieTalkieService: NSObject, @preconcurrency PTChannelManagerDelegate, PTChannelRestorationDelegate, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = WalkieTalkieService()
    private(set) var enabled = UserDefaults.standard.bool(forKey: "rjlove.radio-enabled")
    var speakTexts = UserDefaults.standard.object(forKey: "rjlove.radio-speak-texts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(speakTexts, forKey: "rjlove.radio-speak-texts") }
    }
    var playIncoming = UserDefaults.standard.object(forKey: "rjlove.radio-play-incoming") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(playIncoming, forKey: "rjlove.radio-play-incoming")
            if !playIncoming { stopReceiving() }
        }
    }
    private(set) var joinedSystem = false
    private(set) var backgroundPushConfigured = false
    private(set) var transmitting = false
    private(set) var receiving = false
    private(set) var connecting = false
    private(set) var connected = false
    private(set) var status = "Walkie-Talkie ist aus"
    private(set) var systemMessage: String?
    private(set) var lastTexts: [RadioEvent] = []
    var errorMessage: String?
    private let channelID = UUID(uuidString: "524A4C4F-5645-4000-8000-000000000022")!
    private var manager: PTChannelManager?
    private var api: APIClient?
    private var cursor = 0
    private var ephemeralToken = ""
    private var receiveTask: Task<Void, Never>?
    private var transmitTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private var pending: [RadioEvent] = []
    private var activeTransmission: String?
    private var wantsToTalk = false
    private var systemAudioActive = false
    private var inBackground = false
    private var studioPaused = false
    private var operation = UUID()
    private var expectedLeaves = 0
    private var uploadTask: Task<Void, Error>?
    private var uploadedChunks = 0
    private var capturedSliceDuration = 0.0
    private var receiveDeadline: Date?
    private override init() { super.init(); speech.delegate = self }

    func configure(api: APIClient) {
        self.api = api.sessionCopy()
        if enabled { Task { await prepareSystemChannel() } }
    }
    private func prepareSystemChannel() async {
        guard enabled, !studioPaused else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            if manager == nil { manager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self) }
            if manager?.activeChannelUUID == channelID { joinedSystem = true }
        } catch { systemMessage = "iOS-Systemkanal nicht verfügbar: " + error.localizedDescription }
    }
    func enable(api: APIClient) async {
        guard !connecting else { return }
        self.api = api.sessionCopy(); enabled = true; UserDefaults.standard.set(true, forKey: "rjlove.radio-enabled")
        studioPaused = false; inBackground = false; connecting = true
        defer { connecting = false }
        errorMessage = nil
        await prepareSystemChannel()
        do {
            let result = try await api.radioJoin(token: ephemeralToken)
            connected = true
            if !receiving { cursor = max(cursor, result.cursor) }; backgroundPushConfigured = result.backgroundPushConfigured
            startReceiving()
            if manager?.activeChannelUUID == channelID {
                joinedSystem = true; startReceiving()
            } else { manager?.requestJoinChannel(channelUUID: channelID, descriptor: descriptor()) }
            updateStatus()
        } catch {
            // A signing entitlement failure must not prevent foreground conversation.
            connected = false; errorMessage = error.localizedDescription
            updateStatus()
        }
    }
    func restoreIfEnabled(api: APIClient) async {
        self.api = api.sessionCopy(); inBackground = false
        guard enabled else { return }
        if studioPaused || receiveTask == nil { await enable(api: api) }
    }
    func disable() {
        enabled = false; connected = false; UserDefaults.standard.set(false, forKey: "rjlove.radio-enabled")
        operation = UUID(); wantsToTalk = false
        finishTalking(); stopReceiving(); receiveTask?.cancel(); receiveTask = nil
        manager?.leaveChannel(channelUUID: channelID)
        joinedSystem = false; cursor = 0; ephemeralToken = ""; lastTexts = []; status = "Walkie-Talkie ist aus"
        let api = api; Task { try? await api?.radioAction("leave") }
    }
    func pauseForStudio() {
        guard enabled else { return }
        studioPaused = true; finishTalking(); stopReceiving(); receiveTask?.cancel(); receiveTask = nil
        if joinedSystem { expectedLeaves += 1; manager?.leaveChannel(channelUUID: channelID) }; joinedSystem = false
        Task { try? await api?.radioAction("leave") }
        status = "Für das Duftstudio pausiert"
    }
    func enterBackground() {
        inBackground = true
        // The system owns PTT runtime. No silent audio or polling keeps the app awake.
        if !joinedSystem { finishTalking(); stopReceiving(); receiveTask?.cancel(); receiveTask = nil }
        else if !transmitting && !receiving { receiveTask?.cancel(); receiveTask = nil }
    }
    func beginTalking() {
        guard enabled, !connecting, !studioPaused, !wantsToTalk, !transmitting, !receiving else { return }
        wantsToTalk = true; errorMessage = nil
        let nonce = UUID(); operation = nonce
        Task {
            guard await AVAudioApplication.requestRecordPermission(), operation == nonce, wantsToTalk else {
                if operation == nonce { wantsToTalk = false; errorMessage = "Mikrofon bitte in den iPhone-Einstellungen erlauben." }; return
            }
            guard !AudioStudioService.shared.hasRecording else { wantsToTalk = false; errorMessage = "Beende zuerst deine Duftaufnahme."; return }
            if joinedSystem { manager?.requestBeginTransmitting(channelUUID: channelID) }
            else {
                do { try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP]); try AVAudioSession.sharedInstance().setActive(true); startTransmitting() }
                catch { wantsToTalk = false; errorMessage = error.localizedDescription }
            }
        }
    }
    func finishTalking() {
        wantsToTalk = false; operation = UUID()
        if joinedSystem { manager?.stopTransmitting(channelUUID: channelID) }
        // Stop the microphone immediately, but finish the ordered upload queue.
        stopCapture()
        transmitting = false
        updateStatus()
    }
    private func stopCapture() {
        if let recorder {
            capturedSliceDuration = max(capturedSliceDuration, recorder.currentTime)
            recorder.stop()
        }
    }
    private func startTransmitting() {
        guard wantsToTalk, transmitTask == nil, let api else { return }
        transmitting = true; stopReceiving(); status = "Funkverbindung wird geöffnet …"
        let tx = UUID().uuidString
        uploadedChunks = 0; uploadTask = nil
        transmitTask = Task {
            var index = 0
            do {
                try await api.radioAction("begin", transmissionID: tx)
                if wantsToTalk { status = "Du sprichst · Loslassen zum Senden" }
                let started = Date.now
                while wantsToTalk && !Task.isCancelled && Date.now.timeIntervalSince(started) < 30 {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("radio-" + UUID().uuidString + ".m4a")
                    do {
                        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48000]
                        let recorder = try AVAudioRecorder(url: url, settings: settings)
                        self.recorder = recorder; capturedSliceDuration = 0
                        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                        guard recorder.record() else { throw APIClientError.transport("Mikrofon konnte nicht starten.") }
                        let slice = Date.now
                        while wantsToTalk && Date.now.timeIntervalSince(slice) < 0.75 && !Task.isCancelled {
                            try await Task.sleep(for: .milliseconds(30))
                        }
                        let duration = max(recorder.currentTime, capturedSliceDuration)
                        recorder.stop(); self.recorder = nil
                        if duration >= 0.08 {
                            let audio = try Data(contentsOf: url)
                            let previous = uploadTask; let chunk = index
                            uploadTask = Task {
                                try await previous?.value
                                try await api.radioAction("audio", transmissionID: tx, chunkIndex: chunk, audio: audio)
                                uploadedChunks = chunk + 1
                            }
                            index += 1
                            if index - uploadedChunks > 6 { throw APIClientError.transport("Die Verbindung ist zu langsam für Live-Funk. Bitte erneut versuchen.") }
                        }
                        try? FileManager.default.removeItem(at: url)
                    } catch { try? FileManager.default.removeItem(at: url); throw error }
                }
                try await uploadTask?.value
                try await api.radioAction("end", transmissionID: tx, chunkIndex: index)
            } catch {
                errorMessage = error.localizedDescription
                _ = try? await uploadTask?.value
                try? await api.radioAction("end", transmissionID: tx, chunkIndex: uploadedChunks)
            }
            uploadTask = nil
            recorder?.stop(); recorder = nil; wantsToTalk = false; transmitting = false; transmitTask = nil
            if joinedSystem { manager?.stopTransmitting(channelUUID: channelID) }
            else { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            updateStatus()
        }
    }
    func sendText(_ text: String) async -> Bool {
        guard enabled, let api else { return false }
        do { try await api.radioAction("text", transmissionID: UUID().uuidString, text: text); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    private func startReceiving() {
        guard receiveTask == nil, enabled, !studioPaused, let api else { return }
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.enabled else { return }
                do {
                    let feed = try await api.radioFeed(after: self.cursor)
                    guard !Task.isCancelled else { return }
                    self.connected = true
                    self.backgroundPushConfigured = feed.backgroundPushConfigured
                    self.cursor = feed.cursor
                    for event in feed.events {
                        if event.kind == "text" {
                            if !self.lastTexts.contains(where: { $0.id == event.id }) { self.lastTexts.insert(event, at: 0); self.lastTexts = Array(self.lastTexts.prefix(20)) }
                        }
                        if self.playIncoming && (!self.transmitting) {
                            self.pending.append(event)
                            if event.kind == "audio" || event.kind == "text" {
                                self.receiveDeadline = .now.addingTimeInterval(12)
                                if self.joinedSystem && !self.systemAudioActive {
                                    self.manager?.setActiveRemoteParticipant(PTParticipant(name: event.speaker, image: nil), channelUUID: self.channelID) { _ in }
                                }
                            }
                        }
                    }
                    self.playNext()
                    if let deadline = self.receiveDeadline, Date.now > deadline, self.player == nil, !self.speech.isSpeaking {
                        self.stopReceiving()
                    }
                    if self.inBackground && !self.transmitting && !self.receiving && self.pending.isEmpty {
                        self.receiveTask = nil; return
                    }
                } catch {
                    if Task.isCancelled { return }
                    self.connected = false; self.errorMessage = error.localizedDescription; self.updateStatus()
                    if let apiError = error as? APIClientError, case .server(let code, _) = apiError, code == 401 { self.disable(); return }
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
    private func playNext() {
        guard player == nil, !speech.isSpeaking, !pending.isEmpty, playIncoming, !transmitting else { return }
        if joinedSystem && !systemAudioActive { return }
        let event = pending.removeFirst()
        if event.kind == "end" {
            if pending.isEmpty { stopReceiving() } else { playNext() }; return
        }
        do {
            if !joinedSystem {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            receiving = true; activeTransmission = event.transmissionID; status = event.speaker + " spricht zu dir"
            if event.kind == "text" {
                guard speakTexts else { if pending.isEmpty { stopReceiving() } else { playNext() }; return }
                let utterance = AVSpeechUtterance(string: event.text)
                utterance.voice = AVSpeechSynthesisVoice(language: "de-DE"); utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                speech.speak(utterance)
            } else if let encoded = event.audioBase64, let data = Data(base64Encoded: encoded) {
                let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
                player.delegate = self; self.player = player
                guard player.play() else { self.player = nil; playNext(); return }
            } else { playNext() }
        } catch { errorMessage = error.localizedDescription; player = nil; stopReceiving() }
    }
    func stopReceiving() {
        let wasReceiving = receiving || activeTransmission != nil
        pending = []; player?.stop(); player = nil; speech.stopSpeaking(at: .immediate)
        receiving = false; activeTransmission = nil; receiveDeadline = nil
        if joinedSystem && wasReceiving { manager?.setActiveRemoteParticipant(nil, channelUUID: channelID) { _ in } }
        else if !joinedSystem && !transmitting { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        updateStatus()
    }
    private func updateStatus() {
        if !enabled { status = "Walkie-Talkie ist aus" }
        else if studioPaused { status = "Für das Duftstudio pausiert" }
        else if !connected { status = "Verbindung zum Funkserver fehlt" }
        else if !transmitting && !receiving { status = joinedSystem && backgroundPushConfigured ? "Systemkanal bereit · Hintergrund-Push konfiguriert" : "Bereit in der geöffneten App" }
    }
    nonisolated private func descriptor() -> PTChannelDescriptor { PTChannelDescriptor(name: "Robin & Raphaela", image: UIImage(systemName: "heart.fill")) }
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor { descriptor() }
    func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        joinedSystem = true; systemMessage = nil; updateStatus()
    }
    func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        joinedSystem = false; systemAudioActive = false; finishTalking(); stopReceiving()
        if expectedLeaves > 0 { expectedLeaves -= 1; return }
        if !studioPaused && enabled { disable() }
    }
    func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        joinedSystem = false; systemMessage = "Systemkanal: " + error.localizedDescription; updateStatus()
    }
    func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: Error) { systemMessage = error.localizedDescription }
    func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        ephemeralToken = pushToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do { if let result = try await api?.radioJoin(token: ephemeralToken) { backgroundPushConfigured = result.backgroundPushConfigured; updateStatus() } }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        guard enabled && !studioPaused else { channelManager.stopTransmitting(channelUUID: channelUUID); return }
        wantsToTalk = true
        if systemAudioActive { startTransmitting() }
    }
    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        wantsToTalk = false; stopCapture(); transmitting = false; updateStatus()
    }
    func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        systemAudioActive = true
        if wantsToTalk { startTransmitting() }
        else if !playIncoming { stopReceiving() }
        else { receiving = true; startReceiving(); playNext() }
    }
    func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        systemAudioActive = false; wantsToTalk = false; stopCapture(); transmitting = false
        player?.stop(); player = nil; receiving = false; updateStatus()
    }
    func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) { wantsToTalk = false; errorMessage = error.localizedDescription }
    func channelManager(_ channelManager: PTChannelManager, failedToStopTransmittingInChannel channelUUID: UUID, error: Error) { if transmitting { errorMessage = error.localizedDescription } }
    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        guard UserDefaults.standard.bool(forKey: "rjlove.radio-enabled"),
              let speaker = pushPayload["speaker"] as? String else { return .leaveChannel }
        let sequence = pushPayload["sequence"] as? Int
        Task { @MainActor in
            if let sequence { cursor = min(cursor, max(0, sequence - 1)) }
            receiving = true; receiveDeadline = .now.addingTimeInterval(15); startReceiving()
            if !playIncoming { stopReceiving() }
        }
        return .activeRemoteParticipant(PTParticipant(name: speaker, image: nil))
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in guard self.player === player else { return }; self.player = nil; playNext() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if pending.isEmpty { stopReceiving() } else { playNext() } }
    }
}
