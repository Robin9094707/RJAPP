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
    var history: [CinemaHistory] = []
    var sameScreen = false
    var bridgeConnected = false
    var bridgeError: String?
    private var lastBridgeCheck = Date.distantPast
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
    var miniPlayerHidden = false
    var externalPlaybackActive = false
    var foreground = true
    var userID = ""
    var api: APIClient?
    var namespace = ""
    var features: CinemaFeatures?
    var autoJoin = true { didSet { if !namespace.isEmpty { UserDefaults.standard.set(autoJoin,forKey: "rjlove.cinema.autoJoin."+namespace) } } }
    var youtubeBrowsing = false
    private var ignoredRoomID: String?
    private var discoveryInProgress = false
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
            guard let self, self.foreground, !self.youtubeBrowsing, Date.now > self.ignorePlayerEventsUntil, let room = self.room else { return }
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
        autoJoin = UserDefaults.standard.object(forKey: "rjlove.cinema.autoJoin."+scope) as? Bool ?? true
        plex.configure(namespace: "rjlove.cinema." + scope)
        YouTubeAccount.shared.configure(namespace: "rjlove.cinema." + scope, api: api)
        NativeYouTubeService.shared.configure(namespace: scope)
        TVPresentation.shared.attach(app: app)
        TVTogetherService.shared.configure(api: app.api,namespace: scope,user: user)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.namespace == scope else { return }
                await self.refreshSelectedRoom()
                self.checkSleepTimer()
                if self.foreground && Date.now.timeIntervalSince(self.lastBridgeCheck)>30 {
                    self.lastBridgeCheck = .now
                    await self.refreshPlexBridge()
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    func reset() {
        loop?.cancel(); loop = nil; stopLocal(); plex.reset(); YouTubeAccount.shared.reset()
        room = nil; rooms = []; stats = []; history = []; sameScreen = false; bridgeConnected = false; bridgeError = nil; lastBridgeCheck = .distantPast; api = nil; namespace = ""; userID = ""; features = nil
        TVTogetherService.shared.reset()
        ignoredRoomID = nil; youtubeBrowsing = false; discoveryInProgress = false; miniPlayerHidden = false; externalPlaybackActive = false
        TVPresentation.shared.clear()
    }
    func refresh() async {
        guard let api else { return }
        do {
            features = try await api.cinema("features", as: CinemaFeatures.self)
            rooms = try await api.cinemaRooms(); stats = try await api.cinemaStats()
            struct HistoryPage: Decodable { let items: [CinemaHistory] }
            history = try await api.cinema("history", as: HistoryPage.self).items; error = nil
        } catch {
            self.error = "Medienserver: \(error.localizedDescription) Für gemeinsames Schauen und Suche den neuen Python-Server verwenden. Eure bisherigen Funktionen bleiben verfügbar."
        }
    }
    func startYouTube(id: String, title: String, together: Bool) async {
        guard UserDefaults.standard.bool(forKey: "rjlove.youtube.consent.v1") else { error = "Bitte zuerst YouTube aktivieren und die Datenschutzhinweise bestätigen."; return }
        if together, let current = room, current.provider == "youtube", let api {
            do {
                let next = try await api.cinema("rooms/\(current.id)/select",body: ["revision":current.revision,"media_id":id,"title":String(title.prefix(250))],as: CinemaRoom.self)
                apply(next); error = nil
            } catch { self.error = error.localizedDescription; await refreshSelectedRoom() }
            return
        }
        ignoredRoomID = nil
        await begin(provider: "youtube", id: id, title: String(title.prefix(250)), together: together, url: nil)
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
    func join(_ invitation: CinemaRoom, localPlayback: Bool = false) async {
        guard let api, !busy else { return }
        if invitation.provider == "youtube" && !UserDefaults.standard.bool(forKey: "rjlove.youtube.consent.v1") { error = "Bitte zuerst YouTube aktivieren und die Datenschutzhinweise bestätigen."; return }
        busy = true; defer { busy = false }
        await leave(); stopLocal()
        do {
            let joined = try await api.cinema("rooms/\(invitation.id)/join", body: [:], as: CinemaRoom.self)
            provider = joined.provider; mediaID = joined.mediaID; title = joined.title; room = joined
            if provider == "youtube" { youtube.load(mediaID) }
            else if localPlayback {
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
        let selected = room; ignoredRoomID = selected?.id; room = nil; sameScreen = false
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
        guard let api, foreground || (provider == "plex" && player != nil) else { return }
        guard let selected = room else {
            guard autoJoin, !active, !busy, !discoveryInProgress else { return }
            discoveryInProgress = true; defer { discoveryInProgress = false }
            do {
                rooms = try await api.cinemaRooms()
                if let candidate = rooms.first(where: { $0.id != ignoredRoomID && ($0.provider == "plex" || UserDefaults.standard.bool(forKey: "rjlove.youtube.consent.v1")) }), !AudioStudioService.shared.hasRecording, !VoiceNoteService.shared.recording {
                    await join(candidate)
                }
            } catch let issue as UpdateRequirement { self.error = issue.localizedDescription }
            catch { return }
            return
        }
        let operation = generation
        do {
            let next = try await api.cinema("rooms/\(selected.id)/heartbeat", body: ["playing": player != nil || provider == "youtube" ? playing : false, "same_screen": sameScreen], as: CinemaRoom.self)
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
        let changedVideo = provider == "youtube" && mediaID != next.mediaID
        title = next.title
        if let length = next.details?.duration, length > 0 { duration = length }
        if changedVideo { mediaID = next.mediaID; title = next.title; youtube.load(next.mediaID); position = 0; playing = false }
        room = next
        sleepUntil = next.sleepUntil.map { Date.now.addingTimeInterval($0 - next.serverTime) }
        if next.closed { TVPresentation.shared.mode = .night; stopLocal(); room = nil; return }
        if provider == "plex", player != nil, next.ownerID != userID, !next.plexShared { player?.pause(); playing = false; error = "Die Plex-Freigabe ist beendet."; return }
        // A guest needs a user gesture in the embedded YouTube player; autoplay can be blocked by iOS.
        let drift = abs(position - next.position)
        if changed || drift > 3 || next.playing != playing { setPlayback(next.playing, at: next.position) }
    }
    private func setPlayback(_ play: Bool, at time: Double) {
        ignorePlayerEventsUntil = .now.addingTimeInterval(2)
        let time = max(0, time.isFinite ? time : 0)
        position = time
        if provider == "youtube" {
            youtube.sync(position: time, playing: play && foreground && !youtubeBrowsing)
            if !play { playing = false }
        } else {
            if let player {
                if abs(player.currentTime().seconds - time) > 2 { player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                if play { player.play() } else { player.pause() }
            }
            if player == nil { playing = play }
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
                self?.error = "Plex konnte die Wiedergabe nicht starten. Wähle „Kompatibel (HLS)“ und prüfe Transcoding-Berechtigung, Serverleistung und Netzwerk."
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.externalPlaybackActive = player.isExternalPlaybackActive
                let time = player.currentTime().seconds
                if time.isFinite { self.position = max(0, time) }
                let duration = player.currentItem?.duration.seconds ?? 0
                self.duration = duration.isFinite ? max(0,duration) : 0
                let actual = player.timeControlStatus == .playing
                if let room = self.room, self.foreground, Date.now > self.ignorePlayerEventsUntil, actual != room.playing,
                   player.timeControlStatus == .playing {
                    Task { await self.control(actual ? "play" : "pause") }
                }
                self.playing = actual
                self.checkSleepTimer()
                self.updateNowPlaying()
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
        if provider == "plex", let player {
            if !active { ignorePlayerEventsUntil = .distantFuture }
            else { ignorePlayerEventsUntil = .now.addingTimeInterval(2) }
            if playing { player.play() }
        }
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
        provider = ""; mediaID = ""; title = ""; externalPlaybackActive = false; playing = false; position = 0; duration = 0; sleepUntil = nil
    }
    private func updateNowPlaying() {
        guard provider == "plex" else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: "RJ Love · Unser Kino", MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
    }

    func playOnThisDevice() async {
        guard provider == "plex", player == nil, let room, let api else { return }
        do { let url = try await api.cinemaPlayback(room.id); try installPlayer(url); setPlayback(room.playing, at: room.position); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func stopThisDevice() {
        let saved = room
        stopLocal()
        if let saved { provider = saved.provider; mediaID = saved.mediaID; title = saved.title; room = saved; playing = saved.playing; position = saved.position; duration = saved.details?.duration ?? 0 }
    }
    func resetStatistics() async {
        guard let api else { return }
        struct Result: Decodable { let reset: Bool }
        do { _ = try await api.cinema("stats/reset",body: ["confirmation":"RESET_CINEMA"],as: Result.self); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func connectPlexBridge() async {
        guard let api else { return }
        struct Result: Decodable { let connected: Bool }
        do {
            guard try api.request(path: "",method: "GET").url?.scheme == "https" else { throw APIClientError.transport("Plex-Automatik benötigt HTTPS an eurem RJ-Server.") }
            bridgeConnected = try await api.cinema("plex/connect",body: plex.shareBody(),as: Result.self).connected
            bridgeError = nil
        } catch { bridgeError = error.localizedDescription }
    }
    func disconnectPlexBridge() async {
        guard let api else { return }
        struct Result: Decodable { let connected: Bool }
        do { bridgeConnected = try await api.cinema("plex/disconnect",body: [:],as: Result.self).connected; bridgeError = nil }
        catch { bridgeError = error.localizedDescription }
    }
    private func refreshPlexBridge() async {
        guard let api else { return }
        struct Status: Decodable { let connected: Bool; let error: String? }
        if let status = try? await api.cinema("plex/status",as: Status.self) { bridgeConnected = status.connected; bridgeError = status.error }
        if plex.authenticated && plex.server == nil && !plex.profileRequired { await plex.restoreServer() }
        if plex.server != nil && !bridgeConnected && UserDefaults.standard.bool(forKey: "rjlove.plex.bridge."+namespace) { await connectPlexBridge() }
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

