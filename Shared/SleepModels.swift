import Foundation

enum SleepStage:String,Codable,CaseIterable,Sendable {
    case awake,rem,core,deep,unspecified,bed
    var title:String {switch self{case .awake:"Wach";case .rem:"REM";case .core:"Kernschlaf";case .deep:"Tiefschlaf";case .unspecified:"Schlaf ohne Phasen";case .bed:"Im Bett"}}
    var asleep:Bool {self != .awake && self != .bed}
    var priority:Int {switch self{case .awake:6;case .deep:5;case .rem:4;case .core:3;case .unspecified:2;case .bed:1}}
}
struct SleepSegment:Codable,Hashable,Identifiable,Sendable {
    var stage:SleepStage
    var startAt:String
    var endAt:String
    var id:String {stage.rawValue+startAt+endAt}
    var start:Date? {SleepDates.date(startAt)}
    var end:Date? {SleepDates.date(endAt)}
    enum CodingKeys:String,CodingKey {case stage;case startAt="start_at",endAt="end_at"}
}
struct SleepNight:Codable,Hashable,Identifiable,Sendable {
    var startAt:String
    var endAt:String
    var totalMinutes:Int
    var remMinutes:Int?
    var coreMinutes:Int?
    var deepMinutes:Int?
    var awakeMinutes:Int?
    var unspecifiedMinutes:Int
    var wakeCount:Int?
    var source:String
    var id:String {startAt}
    var start:Date? {SleepDates.date(startAt)}
    var end:Date? {SleepDates.date(endAt)}
    var efficiency:Double? {guard let start,let end,end>start,awakeMinutes != nil else{return nil};return min(100,Double(totalMinutes)/max(1,end.timeIntervalSince(start)/60)*100)}
    enum CodingKeys:String,CodingKey {case source;case startAt="start_at",endAt="end_at",totalMinutes="total_minutes",remMinutes="rem_minutes",coreMinutes="core_minutes",deepMinutes="deep_minutes",awakeMinutes="awake_minutes",unspecifiedMinutes="unspecified_minutes",wakeCount="wake_count"}
}
struct SleepSummary:Codable,Hashable,Sendable {
    var night:SleepNight
    var segments:[SleepSegment]
    var history:[SleepNight]
    var score:Int?
    var durationPoints:Double
    var consistencyPoints:Double?
    var interruptionPoints:Double?
    var baselineNights:Int
    var targetMinutes:Int
    var algorithm:String="rj_sleep_v2"
    enum CodingKeys:String,CodingKey {case night,segments,history,score,algorithm;case durationPoints="duration_points",consistencyPoints="consistency_points",interruptionPoints="interruption_points",baselineNights="baseline_nights",targetMinutes="target_minutes"}
}
struct SleepInput:Sendable {
    var start:Date
    var end:Date
    var stage:SleepStage
    var sourceID:String
    var sourceName:String
}
enum SleepDates {
    static func string(_ date:Date)->String {let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.string(from:date)}
    static func date(_ text:String)->Date? {let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];if let date=f.date(from:text){return date};f.formatOptions=[.withInternetDateTime];return f.date(from:text)}
}
enum SleepAnalyzer {
    // One source per night; detailed stages take precedence over coarse/duplicated totals.
    static func analyze(_ input:[SleepInput],targetMinutes:Int=480,now:Date = .now,calendar:Calendar = .current)->SleepSummary? {
        let valid=input.filter{$0.end>$0.start && $0.start<now && $0.end.timeIntervalSince($0.start)<=36*3600}
        let asleep=valid.filter{$0.stage.asleep}.sorted{$0.start<$1.start}
        guard let first=asleep.first else{return nil}
        var windows:[(Date,Date)]=[];var window=(first.start,first.end)
        for sample in asleep.dropFirst() {
            if sample.start.timeIntervalSince(window.1)<=3*3600 {window.1=max(window.1,sample.end)}else{windows.append(window);window=(sample.start,sample.end)}
        };windows.append(window)
        var nights:[(SleepNight,[SleepSegment])]=[]
        for (begin,finish) in windows {
            let candidates=valid.filter{$0.end>begin && $0.start<finish}
            let sources=Dictionary(grouping:candidates,by:{$0.sourceID})
            let ordered=sources.keys.sorted {a,b in
                let x=sources[a] ?? [],y=sources[b] ?? []
                let dx=coverage(x.filter{[SleepStage.core,.deep,.rem].contains($0.stage)}),dy=coverage(y.filter{[SleepStage.core,.deep,.rem].contains($0.stage)})
                if (dx>0) != (dy>0) {return dx>0}
                let sx=coverage(x.filter{$0.stage.asleep}),sy=coverage(y.filter{$0.stage.asleep})
                if sx != sy{return sx>sy};return a<b
            }
            guard let key=ordered.first,let samples=sources[key],let source=samples.first else{continue}
            let sleepSamples=samples.filter{$0.stage.asleep}
            guard let start=sleepSamples.map(\.start).min(),let end=sleepSamples.map(\.end).max(),end>start,end.timeIntervalSince(start)<=24*3600 else{continue}
            let clipped=samples.compactMap {x->SleepInput? in var x=x;x.start=max(start,x.start);x.end=min(end,x.end,now);return x.end>x.start ? x:nil}
            let segments=timeline(clipped)
            var totals:[SleepStage:Double]=[:]
            for seg in segments {if let a=seg.start,let b=seg.end {totals[seg.stage,default:0]+=b.timeIntervalSince(a)/60}}
            let detailed=totals.keys.contains{[SleepStage.core,.deep,.rem].contains($0)}
            let hasAwake=detailed || totals[.awake] != nil
            let minutes=Int(totals.filter{$0.key.asleep}.values.reduce(0,+).rounded())
            guard minutes>=15 else{continue}
            let night=SleepNight(startAt:SleepDates.string(start),endAt:SleepDates.string(min(end,now)),totalMinutes:minutes,remMinutes:detailed ? Int((totals[.rem] ?? 0).rounded()):nil,coreMinutes:detailed ? Int((totals[.core] ?? 0).rounded()):nil,deepMinutes:detailed ? Int((totals[.deep] ?? 0).rounded()):nil,awakeMinutes:hasAwake ? Int((totals[.awake] ?? 0).rounded()):nil,unspecifiedMinutes:Int((totals[.unspecified] ?? 0).rounded()),wakeCount:hasAwake ? segments.filter{$0.stage == .awake}.count:nil,source:source.sourceName)
            nights.append((night,segments))
        }
        nights.sort{($0.0.end ?? .distantPast)>($1.0.end ?? .distantPast)}
        // Prefer the latest substantial sleep over a short nap. Keep its actual date visible.
        guard let chosen=nights.first(where:{$0.0.totalMinutes>=120}) ?? nights.first,let onset=chosen.0.start else{return nil}
        var history:[SleepNight]=[];var days=Set<Date>()
        for (night,_) in nights where (night.end ?? .distantFuture)<onset && night.totalMinutes>=120 {
            guard let end=night.end else{continue}
            let day=calendar.startOfDay(for:end)
            if days.insert(day).inserted {history.append(night)}
            if history.count==13 {break}
        }
        let target=max(240,min(720,targetMinutes))
        let duration=min(50,max(0,Double(chosen.0.totalMinutes)/Double(target)*50))
        var consistency:Double?
        if history.count>=3 {
            let angles=history.compactMap(\.start).map{date->Double in let c=calendar.dateComponents([.hour,.minute],from:date);return Double((c.hour ?? 0)*60+(c.minute ?? 0))/1440*2*Double.pi}
            let mean=atan2(angles.map{sin($0)}.reduce(0,+),angles.map{cos($0)}.reduce(0,+))
            let c=calendar.dateComponents([.hour,.minute],from:onset)
            let current=Double((c.hour ?? 0)*60+(c.minute ?? 0))/1440*2*Double.pi
            let difference=abs(atan2(sin(current-mean),cos(current-mean)))*1440/(2*Double.pi)
            consistency=max(0,30*(1-difference/120))
        }
        var interruption:Double?
        if let awake=chosen.0.awakeMinutes,let count=chosen.0.wakeCount,let end=chosen.0.end {
            let fraction=Double(awake)/max(1,end.timeIntervalSince(onset)/60)
            interruption=max(0,20*(1-min(1,fraction*2+Double(max(0,count-1))*0.04)))
        }
        let score=consistency.flatMap{regular in interruption.map{Int((duration+regular+$0).rounded())}}
        return SleepSummary(night:chosen.0,segments:Array(chosen.1.prefix(300)),history:history,score:score,durationPoints:duration,consistencyPoints:consistency,interruptionPoints:interruption,baselineNights:history.count,targetMinutes:target)
    }
    private static func coverage(_ input:[SleepInput])->Double {
        let sorted=input.sorted{$0.start<$1.start};guard var current=sorted.first.map({($0.start,$0.end)}) else{return 0}
        var total=0.0
        for x in sorted.dropFirst(){if x.start<=current.1{current.1=max(current.1,x.end)}else{total+=current.1.timeIntervalSince(current.0);current=(x.start,x.end)}}
        return total+current.1.timeIntervalSince(current.0)
    }
    private static func timeline(_ input:[SleepInput])->[SleepSegment] {
        let times=Array(Set(input.flatMap{[$0.start,$0.end]})).sorted();guard times.count>1 else{return []}
        var output:[SleepSegment]=[]
        for i in 0..<times.count-1 {
            let a=times[i],b=times[i+1]
            guard let selected=input.filter({$0.start<=a && $0.end>=b}).max(by:{$0.stage.priority<$1.stage.priority}) else{continue}
            let start=SleepDates.string(a),end=SleepDates.string(b)
            if let last=output.last,last.stage==selected.stage,last.endAt==start {output[output.count-1].endAt=end}else{output.append(SleepSegment(stage:selected.stage,startAt:start,endAt:end))}
        }
        return output
    }
}
