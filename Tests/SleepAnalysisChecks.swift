import Foundation

@main struct SleepAnalysisChecks {
    static func main() {
        let now=Date(timeIntervalSince1970:1772802000)
        var data:[SleepInput]=[]
        for day in 0...4 {
            let end=now.addingTimeInterval(-Double(day)*86400),start=end.addingTimeInterval(-8*3600)
            data.append(SleepInput(start:start,end:end,stage:.core,sourceID:"watch",sourceName:"Apple Watch"))
            // A duplicate coarse source must not double the night or fabricate REM.
            data.append(SleepInput(start:start,end:end,stage:.unspecified,sourceID:"phone",sourceName:"iPhone"))
        }
        guard let summary=SleepAnalyzer.analyze(data,now:now.addingTimeInterval(1)) else{fatalError("Missing sleep summary")}
        assert(summary.night.totalMinutes==480,"Duplicate sources counted twice")
        assert(summary.night.remMinutes==0 && summary.night.deepMinutes==0,"Stages invented")
        assert(summary.score==100 && summary.baselineNights==4,"Stable full nights should reach the configured goal")
        let first=SleepAnalyzer.analyze(Array(data.prefix(2)),now:now.addingTimeInterval(1))!
        assert(first.score==nil,"Score without baseline must remain unavailable")
        let coarse=SleepAnalyzer.analyze(data.filter{$0.sourceID=="phone"},now:now.addingTimeInterval(1))!
        assert(coarse.night.remMinutes==nil && coarse.interruptionPoints==nil && coarse.score==nil,"Coarse data must not pretend to contain stages")
        var fragmented=data.filter{$0.sourceID=="watch"}
        fragmented.append(SleepInput(start:now.addingTimeInterval(-3600),end:now.addingTimeInterval(-1800),stage:.awake,sourceID:"watch",sourceName:"Apple Watch"))
        let interrupted=SleepAnalyzer.analyze(fragmented,now:now.addingTimeInterval(1))!
        assert(interrupted.night.totalMinutes==450 && interrupted.night.awakeMinutes==30,"Awake intervals must replace overlapping sleep")
        assert(interrupted.score!<100,"Interruptions should affect the RJ estimate")
        print("Sleep analysis checked: source deduplication, missing-data behavior and wake intervals.")
    }
}
