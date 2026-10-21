import BackgroundTasks
import Foundation

final class BackgroundRefreshCoordinator: @unchecked Sendable {
    static let shared = BackgroundRefreshCoordinator()
    static let identifier = "eu.rjuhas.rjlove.refresh"

    var handler: (@Sendable () async -> Bool)?
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
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Task { @MainActor in
                DebugLogger.shared.log("Background Refresh: \(error.localizedDescription)", category: "Hintergrund")
            }
        }
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
