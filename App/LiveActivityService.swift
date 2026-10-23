import ActivityKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class LiveActivityService {
    static let shared = LiveActivityService()

    private(set) var isRunning = false
    private(set) var enabled = UserDefaults.standard.bool(forKey:"rjlove.live-enabled")
    var onPushToken: ((String, String) async -> Void)?
    private var tokenTasks: [Task<Void, Never>] = []

    private init() {
        isRunning = !Activity<ConnectionActivityAttributes>.activities.isEmpty
    }

    func start(partnerName: String, battery: Int?, motion: String, mine: Int, partner: Int, updatedAt: Date? = nil) async throws {
        guard UIApplication.shared.applicationState == .active else {return}
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }
        tokenTasks.forEach{$0.cancel()};tokenTasks=[]
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            await onPushToken?(activity.id, "")
        }
        let attributes = ConnectionActivityAttributes(partnerName: partnerName)
        let state = ConnectionActivityAttributes.ContentState(
            battery: battery,
            motion: motion,
            lastUpdate: updatedAt ?? .distantPast,
            myThoughts: mine,
            partnerThoughts: partner
        )
        let activity: Activity<ConnectionActivityAttributes>
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: updatedAt?.addingTimeInterval(120) ?? .now), pushType: .token)
        } catch {
            // Local activities are useful even when a sideload profile cannot support APNs.
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: updatedAt?.addingTimeInterval(120) ?? .now))
        }
        observeTokens(activity)
        isRunning = true
        enabled=true;UserDefaults.standard.set(true,forKey:"rjlove.live-enabled")
    }

    func update(battery: Int?, motion: String, mine: Int, partner: Int, updatedAt: Date? = nil, status:String?=nil, quietUntil:Date?=nil) async {
        let content = ActivityContent(
            state: ConnectionActivityAttributes.ContentState(
                battery: battery,
                motion: motion,
                lastUpdate: updatedAt ?? .distantPast,
                myThoughts: mine,
                partnerThoughts: partner,
                status: status,
                quietUntil: quietUntil
            ),
            staleDate: updatedAt?.addingTimeInterval(120) ?? .now
        )
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.update(content)
        }
        isRunning = !Activity<ConnectionActivityAttributes>.activities.isEmpty
    }

    func restorePushObservers() {
        tokenTasks.forEach { $0.cancel() }; tokenTasks = []
        for activity in Activity<ConnectionActivityAttributes>.activities { observeTokens(activity) }
    }
    private func observeTokens(_ activity: Activity<ConnectionActivityAttributes>) {
        if let token = activity.pushToken {
            Task { await onPushToken?(activity.id, token.map { String(format: "%02x", $0) }.joined()) }
        }
        tokenTasks.append(Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else {return}
                if state == .dismissed || state == .ended {
                    self?.isRunning=false
                    await self?.onPushToken?(activity.id, "")
                    return
                }
            }
        })
        tokenTasks.append(Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                await self?.onPushToken?(activity.id, token.map { String(format: "%02x", $0) }.joined())
            }
        })
    }

    func stop() async {
        enabled=false;UserDefaults.standard.set(false,forKey:"rjlove.live-enabled")
        tokenTasks.forEach { $0.cancel() }; tokenTasks=[]
        let activities=Activity<ConnectionActivityAttributes>.activities
        isRunning=false
        for activity in activities {await activity.end(nil,dismissalPolicy:.immediate)}
        for activity in Activity<FartRecordingAttributes>.activities {await activity.end(nil,dismissalPolicy:.immediate)}
        for activity in activities {await onPushToken?(activity.id,"")}
    }
}

enum LiveActivityError: LocalizedError {
    case disabled
    var errorDescription: String? { "Live-Aktivitäten sind auf diesem iPhone deaktiviert." }
}
