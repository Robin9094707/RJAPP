import AVFoundation
import SwiftUI

struct TrimmedAudio {
    let url: URL
    let duration: Double
    let waveform: [Double]
}
enum AudioEditing {
    /// Export to a new file so a failed export never destroys the local original.
    static func trim(url: URL, start: Double, end: Double, waveform: [Double], duration: Double) async throws -> TrimmedAudio {
        guard start.isFinite, end.isFinite, start >= 0, end <= duration + 0.05, end - start >= 0.2 else { throw AudioEditError.invalidRange }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw AudioEditError.exportFailed }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 44100), duration: CMTime(seconds: end - start, preferredTimescale: 44100))
        do { try await export.export(to: destination, as: .m4a) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        let actual = try await AVURLAsset(url: destination).load(.duration).seconds
        guard actual.isFinite, actual >= 0.2 else { try? FileManager.default.removeItem(at: destination); throw AudioEditError.exportFailed }
        let first = min(max(0, waveform.count - 1), Int(start / duration * Double(waveform.count)))
        let last = min(waveform.count, max(first + 1, Int(ceil(end / duration * Double(waveform.count)))))
        return TrimmedAudio(url: destination, duration: actual, waveform: waveform.isEmpty ? [0] : Array(waveform[first..<last]))
    }
}
private enum AudioEditError: LocalizedError {
    case invalidRange, exportFailed
    var errorDescription: String? { self == .invalidRange ? "Wähle mindestens 0,2 Sekunden innerhalb der Aufnahme." : "Der Schnitt konnte nicht exportiert werden. Das Original bleibt erhalten." }
}

/// Local player owned by the editor. Preview stops at the chosen endpoint.
@MainActor @Observable final class TrimPreview {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private(set) var playing = false
    func play(url: URL, start: Double, end: Double) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback); try session.setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        player.currentTime = start
        guard player.play() else { throw AudioEditError.exportFailed }
        self.player = player; playing = true
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end - start))
            guard !Task.isCancelled else { return }; self?.stop()
        }
    }
    func stop() {
        stopTask?.cancel(); stopTask = nil; player?.stop(); player = nil; playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
struct AudioTrimControls: View {
    let url: URL
    let duration: Double
    let waveform: [Double]
    @Binding var start: Double
    @Binding var end: Double
    @State private var preview = TrimPreview()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dein perfekter Ausschnitt", systemImage: "scissors").font(.headline)
            AudioWaveform(values: waveform, progress: duration > 0 ? end / duration : 0).frame(height: 56)
                .overlay(alignment: .leading) { Rectangle().fill(.background.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading).mask { GeometryReader { g in Rectangle().frame(width: g.size.width * start / max(duration, 0.2)) } } }
            HStack { Text("Start"); Spacer(); Text(String(format: "%.2f s", start)).monospacedDigit() }.font(.caption)
            Slider(value: Binding(get: { start }, set: { preview.stop(); start = min($0, end - 0.2) }), in: 0...max(0.001, duration - 0.2)).tint(LovePalette.pink).accessibilityLabel("Schnittanfang")
            HStack { Text("Ende"); Spacer(); Text(String(format: "%.2f s", end)).monospacedDigit() }.font(.caption)
            Slider(value: Binding(get: { end }, set: { preview.stop(); end = max($0, start + 0.2) }), in: 0.2...max(0.201, duration)).tint(LovePalette.violet).accessibilityLabel("Schnittende")
            AdaptiveLoveRow {
                Button(preview.playing ? "Stoppen" : "Ausschnitt anhören", systemImage: preview.playing ? "stop.fill" : "play.fill") {
                    do { if preview.playing { preview.stop() } else { try preview.play(url: url, start: start, end: end) } }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.bordered)
                Spacer()
                Text(String(format: "%.2f s", end - start)).font(.headline.monospacedDigit()).foregroundStyle(LovePalette.violet)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onDisappear { preview.stop() }
    }
}
struct FartEditorView: View {
    let clip: FartClip
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var start = 0.0
    @State private var end = 0.2
    @State private var title = ""
    @State private var saving = false
    @State private var error: String?
    @State private var editID = UUID().uuidString
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LoveEyebrow(text: "Noch ein bisschen Feinschliff")
                    Text("Nur das Beste bleibt.").font(.system(size: 31, weight: .medium, design: .serif))
                    if let url {
                        AudioTrimControls(url: url, duration: clip.duration, waveform: clip.waveform, start: $start, end: $end).loveCard()
                        TextField("Name", text: $title).textFieldStyle(.roundedBorder)
                        Button {
                            saving = true; error = nil
                            Task {
                                do {
                                    let result = try await AudioEditing.trim(url: url, start: start, end: end, waveform: clip.waveform, duration: clip.duration)
                                    defer { try? FileManager.default.removeItem(at: result.url) }
                                    let bytes = try Data(contentsOf: result.url)
                                    let body = FartUpload(id: clip.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? clip.title : title, caption: clip.caption, category: clip.category, duration: result.duration, waveform: result.waveform, baseRevision: clip.revision ?? 1, editID: editID, audioBase64: bytes.base64EncodedString())
                                    try await appState.editFart(body)
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                                saving = false
                            }
                        } label: { HStack { if saving { ProgressView() }; Label("Schnitt in der Cloud speichern", systemImage: "icloud.and.arrow.up").frame(maxWidth: .infinity) } }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(saving || title.count > 100)
                        Text("Das Original und frühere Schnitte bleiben im Serverarchiv für Backups erhalten. Eure Bewertungen bleiben an dieser Duftpost.").font(.footnote).foregroundStyle(.secondary)
                    } else if error == nil { ProgressView("Aufnahme laden …") }
                    if let error { Text(error).foregroundStyle(.orange) }
                }.padding(24).disabled(saving)
            }.background(LoveBackground()).navigationTitle("Aufnahme schneiden").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
        }.interactiveDismissDisabled(saving)
        .task {
            title = clip.title; end = clip.duration; appState.studio.stopPlayback(); appState.radio.pauseForStudio()
            do {
                let bytes = try await appState.api.fartAudio(id: clip.id)
                let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
                try bytes.write(to: local, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); url = local
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { if let url { try? FileManager.default.removeItem(at: url) }; Task { await appState.radio.restoreIfEnabled(api: appState.api) } }
    }
}
