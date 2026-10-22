import Foundation
import HealthKit

@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()
    @Published private(set) var requested = UserDefaults.standard.bool(forKey: "rjlove.health-requested")
    @Published private(set) var steps: Int?
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var sleepScore: Int?
    @Published private(set) var metrics: [String: Double] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var sharingEnabled = UserDefaults.standard.bool(forKey: "rjlove.health-sharing") {
        didSet { UserDefaults.standard.set(sharingEnabled, forKey: "rjlove.health-sharing") }
    }
    @Published var shareActivity = UserDefaults.standard.bool(forKey: "rjlove.share-activity") {
        didSet { UserDefaults.standard.set(shareActivity, forKey: "rjlove.share-activity") }
    }
    @Published var shareSleep = UserDefaults.standard.bool(forKey: "rjlove.share-sleep") {
        didSet { UserDefaults.standard.set(shareSleep, forKey: "rjlove.share-sleep") }
    }
    @Published var shareVitals = UserDefaults.standard.bool(forKey: "rjlove.share-vitals") {
        didSet { UserDefaults.standard.set(shareVitals, forKey: "rjlove.share-vitals") }
    }
    private let store = HKHealthStore()
    private var refreshing = false
    private init() {}

    struct Metric {
        let id: HKQuantityTypeIdentifier
        let key: String
        let unit: HKUnit
        let cumulative: Bool
    }
    private var types: [Metric] { [
        Metric(id: .distanceWalkingRunning, key: "distance_km", unit: .meterUnit(with: .kilo), cumulative: true),
        Metric(id: .activeEnergyBurned, key: "active_kcal", unit: .kilocalorie(), cumulative: true),
        Metric(id: .appleExerciseTime, key: "exercise_minutes", unit: .minute(), cumulative: true),
        Metric(id: .flightsClimbed, key: "flights", unit: .count(), cumulative: true),
        Metric(id: .heartRate, key: "heart_rate", unit: HKUnit.count().unitDivided(by: .minute()), cumulative: false),
        Metric(id: .restingHeartRate, key: "resting_heart_rate", unit: HKUnit.count().unitDivided(by: .minute()), cumulative: false),
        Metric(id: .heartRateVariabilitySDNN, key: "hrv_ms", unit: .secondUnit(with: .milli), cumulative: false),
        Metric(id: .oxygenSaturation, key: "oxygen_percent", unit: .percent(), cumulative: false),
        Metric(id: .respiratoryRate, key: "respiratory_rate", unit: HKUnit.count().unitDivided(by: .minute()), cumulative: false)
    ] }

    var sharedMetrics: [String: Double] {
        guard sharingEnabled else { return [:] }
        let activity = Set(["distance_km", "active_kcal", "exercise_minutes", "flights"])
        return metrics.filter { activity.contains($0.key) ? shareActivity : shareVitals }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { errorMessage = "Apple Health ist nicht verfügbar."; return }
        var read = Set<HKObjectType>(types.compactMap { HKObjectType.quantityType(forIdentifier: $0.id) })
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { read.insert(steps) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { read.insert(sleep) }
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            requested = true
            UserDefaults.standard.set(true, forKey: "rjlove.health-requested")
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(force:Bool=false) async {
        guard requested, !refreshing, HKHealthStore.isHealthDataAvailable() else { return }
        // Health samples need not be re-read with every foreground sync.
        if !force, let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < 60 { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let stepMetric = Metric(id: .stepCount, key: "steps", unit: .count(), cumulative: true)
            steps = (try? await quantity(stepMetric)).map { Int($0.rounded()) }
            let sleep = try await querySleep()
            sleepMinutes = sleep
            sleepScore = sleep.map { min(100, Int(Double($0) / 480 * 100)) }
            var next: [String: Double] = [:]
            for metric in types {
                if let value = try? await quantity(metric) {
                    next[metric.key] = metric.key == "oxygen_percent" ? value * 100 : value
                }
            }
            metrics = next
            lastUpdated = .now
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private nonisolated static func isEmptyHealthResult(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == HKErrorDomain && [HKError.Code.errorNoData.rawValue, HKError.Code.errorAuthorizationDenied.rawValue].contains(value.code)
    }

    private func quantity(_ metric: Metric) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: metric.id) else { return nil }
        let start = metric.cumulative ? Calendar.current.startOfDay(for: .now) : Date.now.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        if metric.cumulative {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                    if let error {
                        if Self.isEmptyHealthResult(error) { continuation.resume(returning: nil) }
                        else { continuation.resume(throwing: error) }
                        return
                    }
                    continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: metric.unit))
                }
                store.execute(query)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error {
                    if Self.isEmptyHealthResult(error) { continuation.resume(returning: nil) }
                    else { continuation.resume(throwing: error) }
                    return
                }
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: metric.unit))
            }
            store.execute(query)
        }
    }

    private func querySleep() async throws -> Int? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        // Latest 24 hours; union overlapping sources/stages to avoid double-counting.
        let start = Date.now.addingTimeInterval(-86400)
        let end = Date.now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    if Self.isEmptyHealthResult(error) { continuation.resume(returning: []) }
                    else { continuation.resume(throwing: error) }
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            })
        }
        let values = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let intervals = samples.filter { values.contains($0.value) }.map { (max(start, $0.startDate), min(end, $0.endDate)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return nil }
        var seconds = 0.0
        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 { current.1 = max(current.1, interval.1) }
            else { seconds += current.1.timeIntervalSince(current.0); current = interval }
        }
        seconds += current.1.timeIntervalSince(current.0)
        return Int((seconds / 60).rounded())
    }
}
