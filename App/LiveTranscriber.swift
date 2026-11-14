import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text on the iPhone (Apple speech recognition, on-device when available).
/// Audio and transcripts never go to OpenAI: the ChatGPT plan does not include audio, and this
/// keeps voice notes free and private. Optionally records the same audio to an M4A file.
@MainActor
@Observable
final class LiveTranscriber {
    private(set) var isRunning = false
    private(set) var transcript = ""
    private(set) var level: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var error: String?
    private(set) var onDevice = false

    private var engine: AVAudioEngine?
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var committed = ""
    private var partial = ""
    private var startedAt = Date()
    private var clock: Task<Void, Never>?

    /// Shared between the audio thread and the main actor; the request is swapped when a segment ends.
    final class RequestBox: @unchecked Sendable {
        var request: SFSpeechAudioBufferRecognitionRequest?
        var file: AVAudioFile?
    }

    struct Result: Sendable { let text: String; let fileURL: URL?; let seconds: Double }

    static func requestAccess() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(record: Bool) async {
        guard !isRunning else { return }
        error = nil
        guard await Self.requestAccess() else {
            error = "Bitte erlaube Mikrofon und Spracherkennung in den iPhone-Einstellungen."
            return
        }
        let locale = Locale(identifier: Locale.current.language.languageCode?.identifier == "en" ? "en-US" : "de-DE")
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Die Spracherkennung ist gerade nicht verfügbar."
            return
        }
        self.recognizer = recognizer
        onDevice = recognizer.supportsOnDeviceRecognition
        WalkieService.shared.stopPlayback(clearQueue: false)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MediaError.unreadable }
            if record {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-" + UUID().uuidString + ".m4a")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 64000]
                file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                fileURL = url
            } else { file = nil; fileURL = nil }
            box.file = file
            committed = ""; partial = ""; transcript = ""
            beginSegment()
            input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.tapBlock(box: box) { [weak self] value in
                Task { @MainActor in self?.level = value }
            })
            engine.prepare()
            try engine.start()
            self.engine = engine
            isRunning = true
            startedAt = .now
            elapsed = 0
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, self.isRunning else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                }
            }
            Haptics.impact(.light)
        } catch {
            self.error = "Aufnahme konnte nicht starten: " + error.localizedDescription
            cleanUp(deleteFile: true)
        }
    }

    /// Stops listening and returns the final text (and the recording, if requested).
    func stop() async -> Result {
        guard isRunning else { return Result(text: transcript, fileURL: nil, seconds: 0) }
        let seconds = Date().timeIntervalSince(startedAt)
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        box.request?.endAudio()
        isRunning = false
        // Give the recognizer a moment to deliver the last words.
        for _ in 0..<12 where !partial.isEmpty || task?.state == .running {
            try? await Task.sleep(for: .milliseconds(100))
            if task?.state == .completed || task == nil { break }
        }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = fileURL
        box.file = nil
        file = nil
        cleanUp(deleteFile: false)
        Haptics.impact(.soft)
        return Result(text: text, fileURL: url, seconds: seconds)
    }

    func cancel() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        box.request?.endAudio()
        isRunning = false
        cleanUp(deleteFile: true)
    }

    private func beginSegment() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        box.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, final, failed in
            Task { @MainActor in self?.receive(text: text, final: final, failed: failed) }
        })
    }

    private func receive(text: String?, final: Bool, failed: Bool) {
        if let text { partial = text }
        transcript = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
        if final || failed {
            // Recognition segments end after pauses or about a minute: keep the text and continue.
            if !partial.isEmpty { committed = transcript }
            partial = ""
            if isRunning { beginSegment() }
        }
    }

    private func cleanUp(deleteFile: Bool) {
        clock?.cancel(); clock = nil
        task?.cancel(); task = nil
        box.request = nil
        engine = nil
        level = 0
        if deleteFile, let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        if deleteFile { fileURL = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Built outside the main actor: both closures run on audio and speech queues.
    nonisolated private static func tapBlock(box: RequestBox, onLevel: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        var counter = 0
        return { buffer, _ in
            box.request?.append(buffer)
            try? box.file?.write(from: buffer)
            counter += 1
            guard counter % 3 == 0, let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for index in 0..<frames { sum += channel[index] * channel[index] }
            let rms = sqrt(sum / Float(frames))
            onLevel(Double(max(0, min(1, rms * 6))))
        }
    }

    nonisolated private static func resultHandler(_ deliver: @escaping @Sendable (String?, Bool, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        return { result, error in
            deliver(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
