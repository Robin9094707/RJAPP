import AVFoundation
import Foundation

/// Only the currently visible video owns the shared audio session. A late
/// onDisappear from the previous gallery page must not deactivate its successor.
@MainActor final class MomentVideoAudio {
    static let shared=MomentVideoAudio()
    private(set) var owner:UUID?
    private weak var player:AVPlayer?
    var active:Bool {owner != nil}
    func activate(_ player:AVPlayer,owner:UUID) throws {
        guard !AudioStudioService.shared.hasRecording,!VoiceNoteService.shared.recording else{throw VideoAudioError.recording}
        if self.owner != owner {
            self.player?.pause();self.owner=nil;self.player=nil
            EveningPlaylistService.shared.stop()
            AudioStudioService.shared.stopPlayback()
            VoiceNoteService.shared.stop()
        }
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playback,mode:.moviePlayback)
        try session.setActive(true)
        // Preserve the system's output-volume choice; only unmute this player.
        player.isMuted=false;player.volume=1
        self.owner=owner;self.player=player
    }
    func release(owner:UUID){
        guard self.owner==owner else{return}
        player?.pause();self.owner=nil;player=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func stop(){if let owner{release(owner:owner)}}
}
private enum VideoAudioError:LocalizedError {
    case recording
    var errorDescription:String?{"Bitte zuerst deine laufende Aufnahme beenden, bevor du das Video mit Ton abspielst."}
}
