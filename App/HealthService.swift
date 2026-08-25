import Foundation
import HealthKit

@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()

    @Published private(set) var requested = UserDefaults.standard.bool(forKey: "rjlove.health-requested")
    @Published private(set) var steps: Int?
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var sleepScore: Int?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var sharingEnabled: Bool {
        didSet { UserDefaults.standard.set(sharingEnabled, forKey: "rjlove.health-sharing") }
    }

    private let store = HKHealthStore()

    private init() {
        sharingEnabled = UserDefaults.standard.bool(forKey: "rjlove.health-sharing")
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            errorMessage = "Health-Daten sind auf diesem Gerät nicht verfügbar."
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAuthorization(toShare: [], read: [steps, sleep]) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: HealthError.authorizationDenied) }
                }
            }
            requested = true
            UserDefaults.standard.set(true, forKey: "rjlove.health-requested")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            DebugLogger.shared.log("HealthKit: \(error.localizedDescription)", category: "Health")
        }
    }

    func refresh() async {
        guard requested, HKHealthStore.isHealthDataAvailable() else { return }
        async let currentSteps = querySteps()
        async let sleepResult = querySleep()
        do {
            let (stepValue, sleepValue) = try await (currentSteps, sleepResult)
            steps = stepValue
            sleepMinutes = sleepValue.minutes
            sleepScore = sleepValue.score
            lastUpdated = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func querySteps() async throws -> Int {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                let value = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(value.rounded()))
            }
            store.execute(query)
        }
    }

    private func querySleep() async throws -> (minutes: Int, score: Int) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (0, 0) }
        let start = Calendar.current.date(byAdding: .hour, value: -30, to: .now) ?? .now.addingTimeInterval(-108_000)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let minutes = max(0, Int((seconds / 60).rounded()))
        // RJ Schlafbalance is deliberately an app-side duration score, not an Apple Health sleep score.
        let durationScore = min(100, Int((Double(minutes) / 480.0 * 100).rounded()))
        return (minutes, durationScore)
    }
}

enum HealthError: LocalizedError {
    case authorizationDenied
    var errorDescription: String? { "Health-Zugriff wurde nicht erlaubt." }
}
