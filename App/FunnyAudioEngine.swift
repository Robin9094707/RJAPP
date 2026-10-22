import AVFoundation
import Foundation

enum FartSoundEffect:String,CaseIterable,Identifiable {
    case original="Original",chipmunk="Quiekendes Eichhörnchen",monster="Keller-Monster",cathedral="Kathedralen-Konzert",alien="Besuch vom Mars"
    var id:String{rawValue}
}
@MainActor final class FunnyAudioEngine {
    var rate:Float=1 {didSet{applyEffect()}}
    var effect:FartSoundEffect = .original {didSet{applyEffect()}}
    private var engine:AVAudioEngine?
    private var node:AVAudioPlayerNode?
    private var pitch:AVAudioUnitTimePitch?
    private var reverb:AVAudioUnitReverb?
    private var file:AVAudioFile?
    private var temporary:URL?
    private var startFrame:AVAudioFramePosition=0
    private var operation=UUID()
    private var finished:(()->Void)?
    var duration:Double {guard let file else{return 0};return Double(file.length)/file.processingFormat.sampleRate}
    var currentTime:Double {
        guard let file else{return 0}
        let frame=node.flatMap{node in node.lastRenderTime.flatMap{node.playerTime(forNodeTime:$0)}}?.sampleTime ?? 0
        return min(duration,Double(startFrame+frame)/file.processingFormat.sampleRate)
    }
    func play(data:Data,onFinish:@escaping()->Void)throws {
        stop();let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a");try data.write(to:url,options:.completeFileProtection);temporary=url
        let file=try AVAudioFile(forReading:url);self.file=file
        let engine=AVAudioEngine(),node=AVAudioPlayerNode(),pitch=AVAudioUnitTimePitch(),reverb=AVAudioUnitReverb()
        engine.attach(node);engine.attach(pitch);engine.attach(reverb)
        engine.connect(node,to:pitch,format:file.processingFormat);engine.connect(pitch,to:reverb,format:file.processingFormat);engine.connect(reverb,to:engine.mainMixerNode,format:file.processingFormat)
        reverb.loadFactoryPreset(.largeHall);self.engine=engine;self.node=node;self.pitch=pitch;self.reverb=reverb;finished=onFinish;applyEffect()
        try engine.start();schedule(from:0)
    }
    private func applyEffect(){pitch?.rate=rate;pitch?.pitch=effect == .chipmunk ? 1100:effect == .monster ? -900:effect == .alien ? 650:0;reverb?.wetDryMix=effect == .cathedral ? 55:effect == .alien ? 28:0}
    func seek(_ fraction:Double){guard let file else{return};schedule(from:AVAudioFramePosition(max(0,min(0.999,fraction))*Double(file.length)))}
    private func schedule(from frame:AVAudioFramePosition){guard let file,let node else{return};operation=UUID();let id=operation;node.stop();startFrame=frame
        let remaining=file.length-frame;guard remaining>0 else{finished?();return}
        node.scheduleSegment(file,startingFrame:frame,frameCount:AVAudioFrameCount(remaining),at:nil,completionCallbackType:.dataPlayedBack){[weak self] _ in Task{@MainActor in guard let self,self.operation==id else{return};self.finished?()}}
        node.play()
    }
    func stop(){operation=UUID();node?.stop();engine?.stop();node=nil;engine=nil;file=nil;pitch=nil;reverb=nil;finished=nil;startFrame=0;if let temporary{try? FileManager.default.removeItem(at:temporary)};temporary=nil}
}
