import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class LiveActivityService {
    static let shared = LiveActivityService()

    private(set) var isRunning = false

    private init() {
        isRunning = !Activity<ConnectionActivityAttributes>.activities.isEmpty
    }

    func start(partnerName: String, battery: Int?, motion: String, mine: Int, partner: Int) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = ConnectionActivityAttributes(partnerName: partnerName)
        let state = ConnectionActivityAttributes.ContentState(
            battery: battery,
            motion: motion,
            lastUpdate: .now,
            myThoughts: mine,
            partnerThoughts: partner
        )
        _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(900)))
        isRunning = true
    }

    func update(battery: Int?, motion: String, mine: Int, partner: Int) async {
        let content = ActivityContent(
            state: ConnectionActivityAttributes.ContentState(
                battery: battery,
                motion: motion,
                lastUpdate: .now,
                myThoughts: mine,
                partnerThoughts: partner
            ),
            staleDate: .now.addingTimeInterval(900)
        )
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.update(content)
        }
        isRunning = !Activity<ConnectionActivityAttributes>.activities.isEmpty
    }

    func stop() async {
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }
}

enum LiveActivityError: LocalizedError {
    case disabled
    var errorDescription: String? { "Live-Aktivitäten sind auf diesem iPhone deaktiviert." }
}
