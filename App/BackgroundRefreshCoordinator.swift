import BackgroundTasks
import Foundation

final class BackgroundRefreshCoordinator: @unchecked Sendable {
    static let shared = BackgroundRefreshCoordinator()
    static let identifier = "eu.rjuhas.rjlove.refresh"
    /// 10.0: longer, network-bound maintenance window (iOS prefers idle/charging phases).
    static let processingIdentifier = "eu.rjuhas.rjlove.processing"

    var handler: (@Sendable () async -> Bool)?
    var processingHandler: (@Sendable () async -> Bool)?
    private var registered = false
    private let lock = NSLock()

    private init() {}

    func register() {
        lock.lock()
        guard !registered else { lock.unlock(); return }
        registered = true
        lock.unlock()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(refreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: nil) { [weak self] task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(processing)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            let processing = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
            processing.earliestBeginDate = .now.addingTimeInterval(30 * 60)
            processing.requiresNetworkConnectivity = true
            processing.requiresExternalPower = false
            try BGTaskScheduler.shared.submit(processing)
        } catch {
            Task { @MainActor in
                DebugLogger.shared.log("Background Refresh: \(error.localizedDescription)", category: "Hintergrund")
            }
        }
    }

    private func handle(_ task: BGProcessingTask) {
        schedule()
        let work = Task {
            let success = await processingHandler?() ?? false
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = { work.cancel(); Task { @MainActor in BackgroundDeliveryService.shared.cancel() } }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            let success = await handler?() ?? false
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = { work.cancel(); Task { @MainActor in BackgroundDeliveryService.shared.cancel() } }
    }
}
