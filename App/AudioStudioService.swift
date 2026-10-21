import ActivityKit
import AVFoundation
import Foundation
import Observation

struct FartDraft: Codable, Identifiable {
    let id: String
    let ownerID: String
    let duration: Double
    let waveform: [Double]
    var url: URL { AudioDraftStore.directory.appendingPathComponent(id + ".m4a") }
}
enum AudioDraftStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AudioDrafts", isDirectory: true)
    }
    static var metadataURL: URL { directory.appendingPathComponent("draft.json") }
    static func save(_ draft: FartDraft) throws {
        try JSONEncoder().encode(draft).write(to: metadataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func load() -> FartDraft? {
        guard let bytes = try? Data(contentsOf: metadataURL), let draft = try? JSONDecoder().decode(FartDraft.self, from: bytes), UUID(uuidString: draft.id) != nil, FileManager.default.fileExists(atPath: draft.url.path) else { return nil }
        return draft
    }
}

@MainActor @Observable
final class AudioStudioService: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = AudioStudioService()
    enum Mode { case idle, recording, paused, review }
    private(set) var mode: Mode = .idle
    private(set) var elapsed = 0.0
    private(set) var liveLevels: [Double] = []
    private(set) var draft: FartDraft?
    private(set) var playingID: String?
    private(set) var playbackTime = 0.0
    private(set) var playbackDuration = 0.0
    private(set) var loadingID: String?
    var errorMessage: String?
    var playbackRate: Float = 1 { didSet { player?.rate = playbackRate } }
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private var playerTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var recordingID = UUID().uuidString
    private var ownerID = ""
    private var allLevels: [Double] = []
    private var recordingActivity: Activity<FartRecordingAttributes>?
    private var operationID = UUID()

    private override init() {
        super.init()
        draft = AudioDraftStore.load()
        if draft != nil { mode = .review; elapsed = draft?.duration ?? 0 }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                self?.finishRecording(); self?.stopPlayback()
            }
        }
    }
    var isRecording: Bool { mode == .recording }
    var hasRecording: Bool { mode == .recording || mode == .paused }

    func prepare(ownerID: String) {
        if let draft, draft.ownerID != ownerID { discard() }
        self.ownerID = ownerID
    }
    func start(ownerID: String) async {
        guard !hasRecording, draft == nil else { return }
        let operation = UUID(); operationID = operation
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Bitte erlaube RJ Love den Mikrofonzugriff in den iPhone-Einstellungen."; return
        }
        guard operationID == operation, !Task.isCancelled else { return }
        stopPlayback()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            try FileManager.default.createDirectory(at: AudioDraftStore.directory, withIntermediateDirectories: true)
            recordingID = UUID().uuidString; self.ownerID = ownerID
            let url = AudioDraftStore.directory.appendingPathComponent(recordingID + ".m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self; recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: 60) else { throw StudioError.recordingFailed }
            self.recorder = recorder
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            mode = .recording; elapsed = 0; allLevels = []; liveLevels = []
            Haptics.impact(.soft)
            startRecordingActivity()
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder, self.hasRecording else { return }
                    if self.mode == .recording {
                        recorder.updateMeters()
                        let level = max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 35)))
                        self.allLevels.append(level); self.liveLevels = Array(self.allLevels.suffix(48))
                        self.elapsed = min(60, recorder.currentTime)
                        // Persist recoverable metadata while recording, not only after sharing.
                        if self.allLevels.count % 10 == 0 { self.persistDraft(duration: self.elapsed) }
                        if self.elapsed >= 59.9 { self.finishRecording(); return }
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        } catch { errorMessage = error.localizedDescription; mode = .idle; deactivateSession() }
    }
    func togglePause() {
        if mode == .recording { recorder?.pause(); mode = .paused }
        else if mode == .paused {
            if recorder?.record() == true { mode = .recording }
            else { finishRecording(); errorMessage = "Aufnahme wurde beendet. Du kannst den bisherigen Teil teilen." }
        }
        updateRecordingActivity()
    }
    func finishRecording() {
        operationID = UUID()
        guard hasRecording else { return }
        elapsed = min(60, max(elapsed, recorder?.currentTime ?? 0))
        meterTask?.cancel(); meterTask = nil
        recorder?.stop(); recorder = nil
        if elapsed >= 0.2 {
            persistDraft(duration: elapsed); mode = .review
        } else {
            try? FileManager.default.removeItem(at: AudioDraftStore.directory.appendingPathComponent(recordingID + ".m4a"))
            mode = .idle; draft = nil
        }
        endRecordingActivity(); deactivateSession(); Haptics.impact(.light)
    }
    private func persistDraft(duration: Double) {
        guard duration >= 0.2 else { return }
        let value = FartDraft(id: recordingID, ownerID: ownerID, duration: duration, waveform: Self.summarize(allLevels))
        draft = value
        do { try AudioDraftStore.save(value) }
        catch { errorMessage = "Lokales Sichern fehlgeschlagen: \(error.localizedDescription)" }
    }
    private static func summarize(_ levels: [Double]) -> [Double] {
        guard !levels.isEmpty else { return [0] }
        let count = min(80, levels.count)
        return (0..<count).map { i in
            let start = i * levels.count / count; let end = max(start + 1, (i + 1) * levels.count / count)
            return levels[start..<min(end, levels.count)].max() ?? 0
        }
    }
    func discard() {
        operationID = UUID()
        let currentURL = recorder?.url
        recorder?.stop(); recorder = nil; meterTask?.cancel(); meterTask = nil
        stopPlayback(); endRecordingActivity()
        if let draft { try? FileManager.default.removeItem(at: draft.url) }
        if let currentURL { try? FileManager.default.removeItem(at: currentURL) }
        try? FileManager.default.removeItem(at: AudioDraftStore.metadataURL)
        draft = nil; mode = .idle; elapsed = 0; liveLevels = []; allLevels = []
        deactivateSession()
    }
    func playDraft() {
        guard let draft, !hasRecording else { return }
        if playingID == draft.id { stopPlayback(); return }
        stopPlayback()
        do { try play(data: Data(contentsOf: draft.url), id: draft.id) }
        catch { errorMessage = error.localizedDescription }
    }
    func togglePlayback(_ clip: FartClip, api: APIClient) {
        guard !hasRecording else { return }
        if playingID == clip.id || loadingID == clip.id { stopPlayback(); return }
        stopPlayback(); loadingID = clip.id
        loadTask = Task { [weak self] in
            do {
                let data = try await api.fartAudio(id: clip.id)
                guard !Task.isCancelled, self?.loadingID == clip.id else { return }
                try self?.play(data: data, id: clip.id)
            } catch {
                if !Task.isCancelled { self?.errorMessage = error.localizedDescription }
            }
            if self?.loadingID == clip.id { self?.loadingID = nil }
        }
    }
    private func play(data: Data, id: String) throws {
        playerTask?.cancel(); playerTask = nil; player?.stop(); player = nil; playingID = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue)
        player.delegate = self; player.enableRate = true; player.rate = playbackRate
        guard player.prepareToPlay(), player.play() else { throw StudioError.playbackFailed }
        self.player = player; playingID = id; playbackTime = 0; playbackDuration = player.duration
        playerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playingID == id else { return }
                self.playbackTime = self.player?.currentTime ?? 0
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }
    func seek(to fraction: Double) {
        guard let player else { return }; player.currentTime = max(0, min(1, fraction)) * player.duration
    }
    func stopPlayback() {
        loadTask?.cancel(); loadTask = nil; loadingID = nil
        playerTask?.cancel(); playerTask = nil; player?.stop(); player = nil
        playingID = nil; playbackTime = 0; playbackDuration = 0
        if !hasRecording { deactivateSession() }
    }
    private func deactivateSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    private func startRecordingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = FartRecordingAttributes.ContentState(startedAt: .now, elapsed: 0, paused: false)
        recordingActivity = try? Activity.request(attributes: FartRecordingAttributes(title: "Duftstudio"), content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(65)))
    }
    private func updateRecordingActivity() {
        guard let activity = recordingActivity else { return }
        let state = FartRecordingAttributes.ContentState(startedAt: Date.now.addingTimeInterval(-elapsed), elapsed: Int(elapsed), paused: mode == .paused)
        Task { await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(65))) }
    }
    private func endRecordingActivity() {
        guard let activity = recordingActivity else { return }; recordingActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.finishRecording()
            if !flag { self.errorMessage = "Die Aufnahme wurde unterbrochen. Prüfe den gespeicherten Entwurf." }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in guard self?.player === player else { return }; self?.stopPlayback() }
    }
}
private enum StudioError: LocalizedError {
    case recordingFailed, playbackFailed
    var errorDescription: String? { self == .recordingFailed ? "Die Aufnahme konnte nicht gestartet werden." : "Die Aufnahme konnte nicht abgespielt werden." }
}
