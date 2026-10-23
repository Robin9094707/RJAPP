import Foundation
import HealthKit

@MainActor
final class HealthService:ObservableObject {
    static let shared=HealthService()
    static let permissionRevision=2
    @Published private(set) var requested=UserDefaults.standard.bool(forKey:"rjlove.health-requested")
    @Published private(set) var steps:Int?
    @Published private(set) var sleepMinutes:Int?
    @Published private(set) var sleepScore:Int?
    @Published private(set) var sleepSummary:SleepSummary?
    @Published private(set) var metrics:[String:Double]=[:]
    @Published private(set) var metricDates:[String:String]=[:]
    @Published private(set) var lastUpdated:Date?
    @Published private(set) var refreshing=false
    @Published private(set) var errorMessage:String?
    @Published var sharingEnabled=UserDefaults.standard.bool(forKey:"rjlove.health-sharing") {didSet{UserDefaults.standard.set(sharingEnabled,forKey:"rjlove.health-sharing")}}
    @Published var shareActivity=UserDefaults.standard.bool(forKey:"rjlove.share-activity") {didSet{UserDefaults.standard.set(shareActivity,forKey:"rjlove.share-activity")}}
    @Published var shareSleep=UserDefaults.standard.bool(forKey:"rjlove.share-sleep") {didSet{UserDefaults.standard.set(shareSleep,forKey:"rjlove.share-sleep")}}
    @Published var shareVitals=UserDefaults.standard.bool(forKey:"rjlove.share-vitals") {didSet{UserDefaults.standard.set(shareVitals,forKey:"rjlove.share-vitals")}}
    @Published var sleepGoalHours=UserDefaults.standard.object(forKey:"rjlove.sleep-goal-hours") as? Double ?? 8 {didSet{UserDefaults.standard.set(sleepGoalHours,forKey:"rjlove.sleep-goal-hours")}}
    private let store=HKHealthStore()
    private init(){}
    var needsExpandedAccess:Bool {UserDefaults.standard.integer(forKey:"rjlove.health-permission-revision")<Self.permissionRevision && !UserDefaults.standard.bool(forKey:"rjlove.health-upgrade-snoozed-2")}
    func deferExpandedAccess(){UserDefaults.standard.set(true,forKey:"rjlove.health-upgrade-snoozed-2")}
    struct Metric {let id:HKQuantityTypeIdentifier;let key:String;let unit:HKUnit;let cumulative:Bool}
    private var types:[Metric] {[
        Metric(id:.distanceWalkingRunning,key:"distance_km",unit:.meterUnit(with:.kilo),cumulative:true),
        Metric(id:.distanceCycling,key:"cycling_km",unit:.meterUnit(with:.kilo),cumulative:true),
        Metric(id:.activeEnergyBurned,key:"active_kcal",unit:.kilocalorie(),cumulative:true),
        Metric(id:.basalEnergyBurned,key:"resting_kcal",unit:.kilocalorie(),cumulative:true),
        Metric(id:.appleExerciseTime,key:"exercise_minutes",unit:.minute(),cumulative:true),
        Metric(id:.appleStandTime,key:"stand_minutes",unit:.minute(),cumulative:true),
        Metric(id:.flightsClimbed,key:"flights",unit:.count(),cumulative:true),
        Metric(id:.heartRate,key:"heart_rate",unit:HKUnit.count().unitDivided(by:.minute()),cumulative:false),
        Metric(id:.restingHeartRate,key:"resting_heart_rate",unit:HKUnit.count().unitDivided(by:.minute()),cumulative:false),
        Metric(id:.walkingHeartRateAverage,key:"walking_heart_rate",unit:HKUnit.count().unitDivided(by:.minute()),cumulative:false),
        Metric(id:.heartRateVariabilitySDNN,key:"hrv_ms",unit:.secondUnit(with:.milli),cumulative:false),
        Metric(id:.oxygenSaturation,key:"oxygen_percent",unit:.percent(),cumulative:false),
        Metric(id:.respiratoryRate,key:"respiratory_rate",unit:HKUnit.count().unitDivided(by:.minute()),cumulative:false),
        Metric(id:.bodyMass,key:"body_mass_kg",unit:.gramUnit(with:.kilo),cumulative:false),
        Metric(id:.bodyTemperature,key:"body_temperature_c",unit:.degreeCelsius(),cumulative:false),
        Metric(id:.appleSleepingWristTemperature,key:"wrist_temperature_c",unit:.degreeCelsius(),cumulative:false),
        Metric(id:.vo2Max,key:"vo2_max",unit:HKUnit.literUnit(with:.milli).unitDivided(by:.gramUnit(with:.kilo)).unitDivided(by:.minute()),cumulative:false),
        Metric(id:.walkingSpeed,key:"walking_speed_kmh",unit:HKUnit.meter().unitDivided(by:.second()),cumulative:false),
        Metric(id:.walkingStepLength,key:"step_length_cm",unit:.meterUnit(with:.centi),cumulative:false),
        Metric(id:.bloodPressureSystolic,key:"systolic_mmhg",unit:.millimeterOfMercury(),cumulative:false),
        Metric(id:.bloodPressureDiastolic,key:"diastolic_mmhg",unit:.millimeterOfMercury(),cumulative:false)
    ]}
    private var activityKeys:Set<String> {Set(["distance_km","cycling_km","active_kcal","resting_kcal","exercise_minutes","stand_minutes","flights","walking_speed_kmh","step_length_cm"])}
    var sharedMetrics:[String:Double] {guard sharingEnabled else{return [:]};return metrics.filter{activityKeys.contains($0.key) ? shareActivity:shareVitals}}
    var sharedMetricDates:[String:String] {let keys=Set(sharedMetrics.keys);return metricDates.filter{keys.contains($0.key)}}
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else{errorMessage="Apple Health ist auf diesem Gerät nicht verfügbar.";return}
        var read=Set<HKObjectType>(types.compactMap{HKObjectType.quantityType(forIdentifier:$0.id)})
        if let steps=HKObjectType.quantityType(forIdentifier:.stepCount){read.insert(steps)}
        if let sleep=HKObjectType.categoryType(forIdentifier:.sleepAnalysis){read.insert(sleep)}
        do {
            try await store.requestAuthorization(toShare:[],read:read)
            requested=true;UserDefaults.standard.set(true,forKey:"rjlove.health-requested")
            UserDefaults.standard.set(Self.permissionRevision,forKey:"rjlove.health-permission-revision")
            await refresh(force:true)
        }catch{errorMessage="Health-Zugriff nicht möglich: "+error.localizedDescription}
    }
    func refresh(force:Bool=false) async {
        guard requested,!refreshing,HKHealthStore.isHealthDataAvailable() else{return}
        if !force,let lastUpdated,Date.now.timeIntervalSince(lastUpdated)<60{return}
        refreshing=true;defer{refreshing=false}
        do {
            if let value=try? await quantity(Metric(id:.stepCount,key:"steps",unit:.count(),cumulative:true)){steps=Int(value.0.rounded())}else{steps=nil}
            let inputs=try await querySleep()
            let target=Int(max(4,min(12,sleepGoalHours))*60)
            let summary=await Task.detached(priority:.utility){SleepAnalyzer.analyze(inputs,targetMinutes:target)}.value
            sleepSummary=summary;sleepMinutes=summary?.night.totalMinutes;sleepScore=summary?.score
            var next:[String:Double]=[:],dates:[String:String]=[:]
            for metric in types {
                if let result=try? await quantity(metric) {
                    let multiplier=metric.key=="oxygen_percent" ? 100.0:metric.key=="walking_speed_kmh" ? 3.6:1
                    next[metric.key]=result.0*multiplier;dates[metric.key]=result.1.rjISO8601
                }
            }
            metrics=next;metricDates=dates;lastUpdated = .now;errorMessage=nil
        }catch{errorMessage=error.localizedDescription}
    }
    private nonisolated static func isEmptyHealthResult(_ error:Error)->Bool {
        let value=error as NSError
        return value.domain==HKErrorDomain && [HKError.Code.errorNoData.rawValue,HKError.Code.errorAuthorizationDenied.rawValue].contains(value.code)
    }
    private func quantity(_ metric:Metric) async throws -> (Double,Date)? {
        guard let type=HKObjectType.quantityType(forIdentifier:metric.id) else{return nil}
        let now=Date.now
        // Activity is today's total; sparse measurements retain their actual date (up to 30 days).
        let start=metric.cumulative ? Calendar.current.startOfDay(for:now):now.addingTimeInterval(-30*86400)
        let predicate=HKQuery.predicateForSamples(withStart:start,end:now,options:.strictStartDate)
        if metric.cumulative {
            return try await withCheckedThrowingContinuation {continuation in
                store.execute(HKStatisticsQuery(quantityType:type,quantitySamplePredicate:predicate,options:.cumulativeSum){_,result,error in
                    if let error {if Self.isEmptyHealthResult(error){continuation.resume(returning:nil)}else{continuation.resume(throwing:error)};return}
                    continuation.resume(returning:result?.sumQuantity().map{($0.doubleValue(for:metric.unit),now)})
                })
            }
        }
        return try await withCheckedThrowingContinuation {continuation in
            store.execute(HKSampleQuery(sampleType:type,predicate:predicate,limit:1,sortDescriptors:[NSSortDescriptor(key:HKSampleSortIdentifierEndDate,ascending:false)]){_,samples,error in
                if let error {if Self.isEmptyHealthResult(error){continuation.resume(returning:nil)}else{continuation.resume(throwing:error)};return}
                continuation.resume(returning:(samples?.first as? HKQuantitySample).map{($0.quantity.doubleValue(for:metric.unit),$0.endDate)})
            })
        }
    }
    private func querySleep() async throws -> [SleepInput] {
        guard let type=HKObjectType.categoryType(forIdentifier:.sleepAnalysis) else{return []}
        let start=Date.now.addingTimeInterval(-16*86400)
        let predicate=HKQuery.predicateForSamples(withStart:start,end:.now,options:[])
        let samples:[HKCategorySample]=try await withCheckedThrowingContinuation {continuation in
            store.execute(HKSampleQuery(sampleType:type,predicate:predicate,limit:HKObjectQueryNoLimit,sortDescriptors:nil){_,samples,error in
                if let error {if Self.isEmptyHealthResult(error){continuation.resume(returning:[])}else{continuation.resume(throwing:error)};return}
                continuation.resume(returning:samples as? [HKCategorySample] ?? [])
            })
        }
        return samples.compactMap{sample in
            let stage:SleepStage
            switch sample.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:stage = .bed
            case HKCategoryValueSleepAnalysis.awake.rawValue:stage = .awake
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:stage = .core
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:stage = .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:stage = .rem
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:stage = .unspecified
            default:return nil
            }
            return SleepInput(start:max(start,sample.startDate),end:sample.endDate,stage:stage,sourceID:sample.sourceRevision.source.bundleIdentifier+"|"+(sample.device?.name ?? ""),sourceName:sample.sourceRevision.source.name)
        }
    }
}
