import AVFoundation
import Foundation
import Observation

@MainActor @Observable final class VoiceNoteService:NSObject,AVAudioRecorderDelegate,AVAudioPlayerDelegate {
    static let shared=VoiceNoteService()
    var recording=false
    var playing=false
    var duration=0.0
    var level=0.0
    var file:URL?
    var error:String?
    private var recorder:AVAudioRecorder?
    private var player:AVAudioPlayer?
    private var timer:Task<Void,Never>?
    private var onFinish:(()->Void)?
    func record() async {
        EveningPlaylistService.shared.stop()
        guard await AVAudioApplication.requestRecordPermission() else{error="Bitte Mikrofonzugriff erlauben.";return}
        stop();error=nil
        do {
            let session=AVAudioSession.sharedInstance();try session.setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker]);try session.setActive(true)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
            let recorder=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:96000]);recorder.delegate=self;recorder.isMeteringEnabled=true
            guard recorder.record(forDuration:60) else{throw MediaError.unreadable};self.recorder=recorder;file=url;recording=true;duration=0
            timer=Task{[weak self] in while !Task.isCancelled {guard let self,let recorder=self.recorder else{return};self.duration=recorder.currentTime;recorder.updateMeters();self.level=max(0,min(1,pow(10,Double(recorder.averagePower(forChannel:0))/35)));try? await Task.sleep(for:.milliseconds(80))}}
        }catch{self.error=error.localizedDescription}
    }
    func stopRecording(){if let recorder{duration=recorder.currentTime;recorder.stop()};recorder=nil;recording=false;timer?.cancel();timer=nil;if !EveningPlaylistService.shared.active {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}}
    func play(_ url:URL,volume:Double=1,onFinish:(()->Void)?=nil) throws {
        EveningPlaylistService.shared.stop();stop();let session=AVAudioSession.sharedInstance();try session.setCategory(.playback,mode:.default);try session.setActive(true)
        let player=try AVAudioPlayer(contentsOf:url);player.delegate=self;player.volume=Float(max(0.05,min(1,volume)))
        guard player.play() else{throw MediaError.unreadable};self.player=player;playing=true;self.onFinish=onFinish
    }
    func speak(_ text:String,volume:Double=1){EveningPlaylistService.shared.stop();SpeechPlayback.shared.speak(text,volume:Float(volume))}
    func stop(){stopRecording();player?.stop();player=nil;playing=false;onFinish=nil;SpeechPlayback.shared.stop();if !EveningPlaylistService.shared.active {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}}
    nonisolated func audioRecorderDidFinishRecording(_ recorder:AVAudioRecorder,successfully flag:Bool){Task{@MainActor [weak self] in self?.stopRecording()}}
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool){Task{@MainActor [weak self] in guard let self,self.player === player else{return};let callback=self.onFinish;self.stop();callback?()}}
}
@MainActor final class SpeechPlayback:NSObject,AVSpeechSynthesizerDelegate {
    static let shared=SpeechPlayback();private let synthesizer=AVSpeechSynthesizer()
    func speak(_ text:String,volume:Float){let utterance=AVSpeechUtterance(string:text);utterance.voice=AVSpeechSynthesisVoice(language:"de-DE");utterance.volume=max(0.05,min(1,volume));synthesizer.speak(utterance)}
    func stop(){synthesizer.stopSpeaking(at:.immediate)}
}
