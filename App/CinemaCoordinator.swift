import AVFoundation
import CryptoKit
import MediaPlayer
import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class CinemaCoordinator {
    static let shared = CinemaCoordinator()
    let youtube = YouTubeCinemaPlayer()
    let plex = PlexCinemaClient()
    var room: CinemaRoom?
    var rooms: [CinemaRoom] = []
    var stats: [CinemaStat] = []
    var player: AVPlayer?
    var provider = ""
    var mediaID = ""
    var title = ""
    var playing = false
    var position = 0.0
    var duration = 0.0
    var sleepUntil: Date?
    var error: String?
    var busy = false
    var screenVisible = false
    var foreground = true
    var userID = ""
    var api: APIClient?
    var namespace = ""
    var features: CinemaFeatures?
    private var loop: Task<Void, Never>?
    private var timeObserver: Any?
    private var playerObservation: NSKeyValueObservation?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var changing = false
    private var generation = UUID()
    private var ignorePlayerEventsUntil = Date.distantPast
    var active: Bool { !mediaID.isEmpty }
    private init() {
        youtube.stateChanged = { [weak self] playing, position in
            guard let self, self.provider == "youtube" else { return }
            self.playing = playing; self.position = max(0, position)
        }
        youtube.intentChanged = { [weak self] play, time in
            guard let self, self.foreground, Date.now > self.ignorePlayerEventsUntil, let room = self.room else { return }
            if room.playing != play {
                Task { await self.control(play ? "play" : "pause", value: time) }
            } else if abs(room.position + (room.playing ? max(0,Date.now.timeIntervalSince1970-room.serverTime) : 0)-time)>3 {
                Task { await self.control("seek", value: time) }
            }
        }
        youtube.failed = { [weak self] error in self?.error = error; self?.playing = false }
    }
    func configure(app: AppState) {
        guard let user = app.me?.id else { reset(); return }
        let base = (try? app.api.request(path: "", method: "GET").url?.absoluteString) ?? ""
        let scope = SHA256.hash(data: Data((base + "|" + user).utf8)).map { String(format: "%02x", $0) }.joined()
        guard namespace != scope else { return }
        reset(); namespace = scope; userID = user; api = app.api.sessionCopy()
        plex.configure(namespace: "rjlove.cinema." + scope)
        YouTubeAccount.shared.configure(namespace: "rjlove.cinema." + scope, api: api)
        TVPresentation.shared.attach(app: app)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.namespace == scope else { return }
                await self.refreshSelectedRoom()
                self.checkSleepTimer()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    func reset() {
        loop?.cancel(); loop = nil; stopLocal(); plex.reset(); YouTubeAccount.shared.reset()
        room = nil; rooms = []; stats = []; api = nil; namespace = ""; userID = ""; features = nil
        TVPresentation.shared.clear()
    }
    func refresh() async {
        guard let api else { return }
        do {
            features = try await api.cinema("features", as: CinemaFeatures.self)
            rooms = try await api.cinemaRooms(); stats = try await api.cinemaStats(); error = nil
        } catch {
            self.error = "Medienserver: \(error.localizedDescription) Für gemeinsames Schauen und Suche den neuen Python-Server verwenden. Eure bisherigen Funktionen bleiben verfügbar."
        }
    }
    func startYouTube(id: String, title: String, together: Bool) async {
        guard UserDefaults.standard.bool(forKey: "rjlove.youtube.consent.v1") else { error = "Bitte zuerst YouTube aktivieren und die Datenschutzhinweise bestätigen."; return }
        await begin(provider: "youtube", id: id, title: title, together: together, url: nil)
    }
    func startPlex(_ entry: PlexEntry, together: Bool, share: Bool) async {
        guard !busy else { return }
        if together && !share { error = "Bitte die zeitweise Freigabe für diesen Film einschalten. Dein Plex-Konto bleibt dabei privat."; return }
        do {
            let url = try await plex.media(entry)
            await begin(provider: "plex", id: entry.id, title: entry.title, together: together, url: url)
            if share, let room, together, let api {
                // Plex credentials only go to the user's own HTTPS server.
                let request = try api.request(path: "", method: "GET")
                guard request.url?.scheme == "https" else { throw APIClientError.transport("Plex-Freigaben benötigen HTTPS an eurem RJ-Server. Alleine schauen funktioniert weiterhin.") }
                self.room = try await api.cinema("rooms/\(room.id)/plex-share", body: plex.shareBody(), as: CinemaRoom.self)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func begin(provider: String, id: String, title: String, together: Bool, url: URL?) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard !AudioStudioService.shared.hasRecording, !VoiceNoteService.shared.recording else { error = "Bitte zuerst die Aufnahme beenden."; return }
        await leave(); stopLocal(); error = nil
        do {
            if together {
                guard let api else { throw APIClientError.invalidResponse }
                room = try await api.cinema("rooms", body: ["provider": provider, "media_id": id, "title": title], as: CinemaRoom.self)
            }
            self.provider = provider; mediaID = id; self.title = title
            if provider == "youtube" { youtube.load(id) }
            else if let url { try installPlayer(url) }
            if together { if let room { apply(room) } }
            else { await control("play") }
        } catch { self.error = error.localizedDescription; stopLocal(); room = nil }
    }
    func join(_ invitation: CinemaRoom) async {
        guard let api, !busy else { return }
        if invitation.provider == "youtube" && !UserDefaults.standard.bool(forKey: "rjlove.youtube.consent.v1") { error = "Bitte zuerst YouTube aktivieren und die Datenschutzhinweise bestätigen."; return }
        busy = true; defer { busy = false }
        await leave(); stopLocal()
        do {
            let joined = try await api.cinema("rooms/\(invitation.id)/join", body: [:], as: CinemaRoom.self)
            provider = joined.provider; mediaID = joined.mediaID; title = joined.title; room = joined
            if provider == "youtube" { youtube.load(mediaID) }
            else {
                let url = try await api.cinemaPlayback(joined.id)
                try installPlayer(url)
            }
            apply(joined); error = nil
        } catch {
            self.error = error.localizedDescription
            // Leave the membership if resolving the media failed.
            if let selected = room { _ = try? await api.cinema("rooms/\(selected.id)/leave", body: [:], as: CinemaRoom.self) }
            room = nil; stopLocal()
        }
    }
    func leave() async {
        let selected = room; room = nil
        if let selected, let api { _ = try? await api.cinema("rooms/\(selected.id)/leave", body: [:], as: CinemaRoom.self) }
        stopLocal()
    }
    func control(_ action: String, value: Double? = nil) async {
        guard active, !changing else { return }
        changing = true; defer { changing = false }
        if let room, let api {
            do {
                var body: [String: Any] = ["revision": room.revision, "action": action]
                if ["play", "pause", "seek"].contains(action) { body["position"] = max(0, value ?? position) }
                if action == "timer" { body["seconds"] = value ?? 0 }
                let next = try await api.cinema("rooms/\(room.id)/control", body: body, as: CinemaRoom.self)
                apply(next); error = nil
            } catch { self.error = error.localizedDescription; await refreshSelectedRoom() }
        } else {
            switch action {
            case "play": setPlayback(true, at: value ?? position)
            case "pause": setPlayback(false, at: value ?? position)
            case "seek": setPlayback(playing, at: value ?? position)
            case "timer": sleepUntil = (value ?? 0) > 0 ? .now.addingTimeInterval(value ?? 0) : nil
            case "end": stopLocal()
            default: break
            }
        }
    }
    private func refreshSelectedRoom() async {
        guard let selected = room, let api, foreground else { return }
        let operation = generation
        do {
            let next = try await api.cinema("rooms/\(selected.id)/heartbeat", body: ["playing": playing], as: CinemaRoom.self)
            guard generation == operation, room?.id == selected.id else { return }
            apply(next)
        } catch {
            guard generation == operation else { return }
            if case APIClientError.server(let status, _) = error, [403,404,410].contains(status) { room = nil; stopLocal() }
            self.error = error.localizedDescription
        }
    }
    private func apply(_ next: CinemaRoom) {
        let changed = room?.revision != next.revision
        room = next
        sleepUntil = next.sleepUntil.map { Date.now.addingTimeInterval($0 - next.serverTime) }
        if next.closed { TVPresentation.shared.mode = .night; stopLocal(); room = nil; return }
        if provider == "plex", next.ownerID != userID, !next.plexShared { player?.pause(); playing = false; error = "Die Plex-Freigabe ist beendet."; return }
        // A guest needs a user gesture in the embedded YouTube player; autoplay can be blocked by iOS.
        let drift = abs(position - next.position)
        if changed || drift > 3 || next.playing != playing { setPlayback(next.playing, at: next.position) }
    }
    private func setPlayback(_ play: Bool, at time: Double) {
        ignorePlayerEventsUntil = .now.addingTimeInterval(2)
        let time = max(0, time.isFinite ? time : 0)
        position = time
        if provider == "youtube" {
            youtube.sync(position: time, playing: play && foreground)
            if !play { playing = false }
        } else {
            if let player {
                if abs(player.currentTime().seconds - time) > 2 { player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                if play { player.play() } else { player.pause() }
            }
            updateNowPlaying()
        }
    }
    private func installPlayer(_ url: URL) throws {
        EveningPlaylistService.shared.stop(); MomentVideoAudio.shared.stop()
        AudioStudioService.shared.stopPlayback(); VoiceNoteService.shared.stop()
        let audio = AVAudioSession.sharedInstance(); try audio.setCategory(.playback, mode: .moviePlayback); try audio.setActive(true)
        let player = AVPlayer(url: url); player.allowsExternalPlayback = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        self.player = player
        playerObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.playing = false
                self?.error = "Plex kann diese Datei nicht nativ abspielen. Dieses Update unterstützt Direct Play; für andere Codecs die Plex-App verwenden."
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                let time = player.currentTime().seconds
                if time.isFinite { self.position = max(0, time) }
                let duration = player.currentItem?.duration.seconds ?? 0
                self.duration = duration.isFinite ? max(0,duration) : 0
                let actual = player.timeControlStatus == .playing
                if let room = self.room, self.foreground, Date.now > self.ignorePlayerEventsUntil, actual != room.playing,
                   player.timeControlStatus == .playing || player.timeControlStatus == .paused {
                    Task { await self.control(actual ? "play" : "pause") }
                }
                self.playing = actual
                self.checkSleepTimer(); self.updateNowPlaying()
            }
        }
        installRemoteCommands()
    }
    private func checkSleepTimer() {
        if let deadline = sleepUntil, deadline <= .now {
            sleepUntil = nil; player?.pause(); youtube.pause(); playing = false
            TVPresentation.shared.mode = .night
        }
    }
    func setForeground(_ active: Bool) {
        foreground = active
        UIApplication.shared.isIdleTimerDisabled = active && TVPresentation.shared.connected
        if !active, provider == "youtube" { youtube.pause(); playing = false }
        if active { checkSleepTimer() }
    }
    func stopLocal() {
        if provider == "youtube" { youtube.pause() }
        generation = UUID(); youtube.stop()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil; playerObservation = nil; player?.pause(); player = nil
        for (command, target) in remoteTargets { command.removeTarget(target) }; remoteTargets = []
        if provider == "plex" { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        provider = ""; mediaID = ""; title = ""; playing = false; position = 0; duration = 0; sleepUntil = nil
    }
    private func updateNowPlaying() {
        guard provider == "plex" else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: "RJ Love · Unser Kino", MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
    }
    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        for (command, action) in [(center.playCommand, "play"), (center.pauseCommand, "pause"), (center.togglePlayPauseCommand, "toggle")] {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in guard let self else { return }; await self.control(action == "toggle" ? (self.playing ? "pause" : "play") : action) }
                return .success
            }
            remoteTargets.append((command,target))
        }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in await self?.control("seek",value:event.positionTime) }; return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand,target))
    }
}
