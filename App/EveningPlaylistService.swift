import AVFoundation
import MediaPlayer
import Observation
import UIKit

struct EveningTrack:Identifiable {
    let id:String
    let ownerID:String
    let title:String
    let detail:String
    let date:Date
    let assetID:String?
    var isVideo:Bool {assetID != nil}
    init(_ clip:FartClip) {id=clip.id;ownerID=clip.ownerID;title=clip.title;detail=clip.caption;date=clip.date ?? .distantPast;assetID=nil}
    init?(_ record:SharedRecord) {
        guard record.payload.mediaKind == "video",let asset=record.payload.assetIDs?.first else{return nil}
        id=record.id;ownerID=record.ownerID;title=record.payload.caption?.isEmpty == false ? record.payload.caption!:"Unser Film";detail="Ein Video aus euren Momenten";date=JournalDates.date(record) ?? .distantPast;assetID=asset
    }
}

@MainActor @Observable final class EveningPlaylistService {
    static let shared=EveningPlaylistService()
    private(set) var tracks:[EveningTrack]=[]
    private(set) var index=0
    private(set) var player:AVQueuePlayer?
    private(set) var preparing=false
    private(set) var playing=false
    private(set) var elapsed=0.0
    private(set) var duration=0.0
    private(set) var sleepUntil:Date?
    var error:String?
    private var api:APIClient?
    private var nextLoad=0
    private var generation=UUID()
    private var fillTask:Task<Void,Never>?
    private var sleepTask:Task<Void,Never>?
    private var observations:[NSKeyValueObservation]=[]
    private var notifications:[NSObjectProtocol]=[]
    private var timeObserver:Any?
    private var identities:[ObjectIdentifier:Int]=[:]
    private var files:[Int:URL]=[:]
    private var remoteTargets:[(MPRemoteCommand,Any)]=[]
    var current:EveningTrack? {tracks.indices.contains(index) ? tracks[index]:nil}
    var active:Bool {player != nil}
    private init() {
        let center=NotificationCenter.default
        notifications.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main){[weak self] note in
            let type=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type==AVAudioSession.InterruptionType.began.rawValue {Task{@MainActor in self?.pause()}}
        })
        notifications.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main){[weak self] note in
            if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {Task{@MainActor in self?.pause()}}
        })
    }
    func start(_ tracks:[EveningTrack],api:APIClient,from:Int=0) {
        guard !AudioStudioService.shared.hasRecording,!VoiceNoteService.shared.recording else{error="Bitte zuerst deine Aufnahme beenden.";return}
        stop();AudioStudioService.shared.stopPlayback();VoiceNoteService.shared.stop()
        guard tracks.indices.contains(from) else{return}
        self.tracks=tracks;self.api=api.sessionCopy();index=from;nextLoad=from;playing=true
        let queue=AVQueuePlayer();queue.actionAtItemEnd = .advance;queue.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player=queue
        observations=[queue.observe(\.currentItem,options:[.new]){[weak self] _,_ in Task{@MainActor in self?.changedItem()}},queue.observe(\.timeControlStatus,options:[.new]){[weak self] queue,_ in Task{@MainActor in guard self?.player === queue else{return};self?.updateNowPlaying()}}]
        timeObserver=queue.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.5,preferredTimescale:600),queue:.main){[weak self] _ in Task{@MainActor in self?.tick()}}
        do {try activateAudio()}catch{self.error=error.localizedDescription;playing=false}
        installRemoteControls();fill()
    }
    private func activateAudio()throws {
        let session=AVAudioSession.sharedInstance();try session.setCategory(.playback,mode:.default);try session.setActive(true)
    }
    private func fill() {
        guard fillTask==nil,let queue=player,let api else{return}
        let operation=generation;preparing=true
        fillTask=Task{[weak self] in
            guard let self else{return}
            defer {if self.generation==operation{self.preparing=false;self.fillTask=nil;self.updateNowPlaying()}}
            while !Task.isCancelled,self.generation==operation,queue.items().count<3,self.nextLoad<self.tracks.count {
                let i=self.nextLoad,track=self.tracks[i]
                var uncommittedFile:URL?
                defer {if let file=uncommittedFile{try? FileManager.default.removeItem(at:file)}}
                do {
                    let file:URL
                    if let asset=track.assetID {file=try await api.assetFile(id:asset,mime:"video/quicktime")}
                    else {file=FileManager.default.temporaryDirectory.appendingPathComponent("rj-evening-"+UUID().uuidString+".m4a");let bytes=try await api.fartAudio(id:track.id);try bytes.write(to:file,options:.atomic)}
                    uncommittedFile=file
                    guard !Task.isCancelled,self.generation==operation else{try? FileManager.default.removeItem(at:file);return}
                    try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:file.path)
                    let item=AVPlayerItem(url:file)
                    let playable=try await item.asset.load(.isPlayable)
                    guard playable else{try? FileManager.default.removeItem(at:file);throw MediaError.unreadable}
                    guard !Task.isCancelled,self.generation==operation else{try? FileManager.default.removeItem(at:file);return}
                    self.files[i]=file;uncommittedFile=nil;self.identities[ObjectIdentifier(item)]=i
                    queue.insert(item,after:nil);self.nextLoad=i+1
                    if self.playing{queue.play()}
                    self.error=nil
                }catch {
                    if !Task.isCancelled,self.generation==operation {self.error="„\(track.title)“ konnte nicht geladen werden. Du kannst erneut laden oder diesen Beitrag überspringen."}
                    return
                }
            }
        }
    }
    private func changedItem() {
        guard let queue=player else{return}
        if let item=queue.currentItem,let i=identities[ObjectIdentifier(item)] {
            index=i;elapsed=0;duration=0
            for key in Array(files.keys) where key<i {if let file=files.removeValue(forKey:key){try? FileManager.default.removeItem(at:file)}}
            if playing{queue.play()}
        }else if nextLoad>=tracks.count,!preparing {stop();return}
        fill();updateNowPlaying()
    }
    private func tick() {
        guard let queue=player else{return}
        let time=queue.currentTime().seconds,d=queue.currentItem?.duration.seconds ?? 0
        elapsed=time.isFinite ? max(0,time):0;duration=d.isFinite ? max(0,d):0
        if let sleepUntil,sleepUntil<=Date.now{pause();setSleep(minutes:0)}
        updateNowPlaying()
    }
    func toggle(){playing ? pause():resume()}
    func pause(){playing=false;player?.pause();updateNowPlaying()}
    func resume(){guard active else{return};do{try activateAudio();playing=true;player?.play();fill();updateNowPlaying()}catch{self.error=error.localizedDescription}}
    func next(){guard let queue=player else{return};if queue.currentItem != nil{queue.advanceToNextItem()}else if nextLoad<tracks.count{nextLoad += 1};error=nil;fill()}
    func previous(){guard let api else{return};let oldTracks=tracks;let i=elapsed>3 ? index:max(0,index-1);start(oldTracks,api:api,from:i)}
    func retry(){error=nil;fill()}
    func seek(_ value:Double){guard duration>0 else{return};player?.seek(to:CMTime(seconds:max(0,min(duration,value)),preferredTimescale:600));updateNowPlaying()}
    func setSleep(minutes:Int) {
        sleepTask?.cancel();sleepTask=nil;sleepUntil=minutes>0 ? Date.now.addingTimeInterval(Double(minutes)*60):nil
        guard minutes>0 else{return}
        sleepTask=Task{[weak self] in do{try await Task.sleep(for:.seconds(minutes*60));guard !Task.isCancelled else{return};self?.pause();self?.sleepUntil=nil}catch{}}
    }
    func stop() {
        let hadPlayer=player != nil
        generation=UUID();fillTask?.cancel();fillTask=nil;preparing=false;sleepTask?.cancel();sleepTask=nil;sleepUntil=nil
        observations=[]
        if let timeObserver{player?.removeTimeObserver(timeObserver)};timeObserver=nil
        player?.pause();player?.removeAllItems();player=nil;identities=[:]
        for file in files.values{try? FileManager.default.removeItem(at:file)};files=[:]
        for (command,target) in remoteTargets{command.removeTarget(target)};remoteTargets=[]
        tracks=[];index=0;nextLoad=0;elapsed=0;duration=0;playing=false;api=nil;error=nil
        if hadPlayer{MPNowPlayingInfoCenter.default().nowPlayingInfo=nil;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
    }
    private func installRemoteControls() {
        let c=MPRemoteCommandCenter.shared()
        func add(_ command:MPRemoteCommand,_ action:@escaping @MainActor()->Void) {command.isEnabled=true;let target=command.addTarget{_ in Task{@MainActor in action()};return .success};remoteTargets.append((command,target))}
        add(c.playCommand){[weak self] in self?.resume()};add(c.pauseCommand){[weak self] in self?.pause()};add(c.togglePlayPauseCommand){[weak self] in self?.toggle()};add(c.nextTrackCommand){[weak self] in self?.next()};add(c.previousTrackCommand){[weak self] in self?.previous()};add(c.stopCommand){[weak self] in self?.stop()}
    }
    private func updateNowPlaying() {
        guard active,let current else{return}
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[MPMediaItemPropertyTitle:current.title,MPMediaItemPropertyArtist:"RJ Love · Euer Abend",MPMediaItemPropertyAlbumTitle:"\(index+1) von \(tracks.count)",MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:elapsed,MPNowPlayingInfoPropertyPlaybackRate:player?.rate ?? 0]
    }
}
