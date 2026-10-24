#if DEBUG
import AVFoundation
import SwiftUI

struct VideoAudioVerificationView:View {
    @State private var report="Prüfung läuft"
    var body:some View {Text(report).accessibilityIdentifier("video-audio-result").task{report=check()}}
    @MainActor private func check()->String {
        let audio=MomentVideoAudio.shared,a=UUID(),b=UUID()
        let first=AVPlayer(),second=AVPlayer()
        do {
            try audio.activate(first,owner:a)
            guard AVAudioSession.sharedInstance().category == .playback,AVAudioSession.sharedInstance().mode == .moviePlayback,!first.isMuted,first.volume==1 else{return "FAIL: playback configuration"}
            // Old page cleanup must not silence the new visible page.
            try audio.activate(second,owner:b);audio.release(owner:a)
            guard audio.owner==b,audio.active,!second.isMuted else{return "FAIL: page ownership"}
            // Existing foreground/background cleanup paths must not silence video.
            AudioStudioService.shared.stopPlayback();VoiceNoteService.shared.stop()
            guard audio.owner==b,AVAudioSession.sharedInstance().category == .playback else{return "FAIL: unrelated cleanup"}
            audio.release(owner:b)
            guard !audio.active else{return "FAIL: audio release"}
            return "VIDEO_AUDIO_CHECKS_PASSED"
        }catch{audio.stop();return "FAIL: "+error.localizedDescription}
    }
}
#endif
