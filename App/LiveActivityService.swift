import ActivityKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class LiveActivityService {
    static let shared = LiveActivityService()

    private(set) var isRunning = false
    private(set) var isStarting = false
    var automaticallyResume = UserDefaults.standard.object(forKey:"rjlove.live-auto-resume") as? Bool ?? true {
        didSet {UserDefaults.standard.set(automaticallyResume,forKey:"rjlove.live-auto-resume")}
    }
    var showBattery = UserDefaults.standard.object(forKey:"rjlove.live-battery") as? Bool ?? true {didSet{UserDefaults.standard.set(showBattery,forKey:"rjlove.live-battery")}}
    var showThoughts = UserDefaults.standard.object(forKey:"rjlove.live-thoughts") as? Bool ?? true {didSet{UserDefaults.standard.set(showThoughts,forKey:"rjlove.live-thoughts")}}
    var showStatus = UserDefaults.standard.object(forKey:"rjlove.live-status") as? Bool ?? true {didSet{UserDefaults.standard.set(showStatus,forKey:"rjlove.live-status")}}
    var showQuickAction = UserDefaults.standard.object(forKey:"rjlove.live-action") as? Bool ?? true {didSet{UserDefaults.standard.set(showQuickAction,forKey:"rjlove.live-action")}}
    private(set) var enabled = UserDefaults.standard.bool(forKey:"rjlove.live-enabled")
    var onPushToken: ((String, String) async -> Void)?
    private var tokenTasks: [Task<Void, Never>] = []

    private init() {
        isRunning = Activity<ConnectionActivityAttributes>.activities.contains{$0.activityState == .active || $0.activityState == .stale}
    }

    func start(partnerName: String, battery: Int?, motion: String, mine: Int, partner: Int, updatedAt: Date? = nil,status:String?=nil,quietUntil:Date?=nil) async throws {
        guard !isStarting else {return}
        guard UIApplication.shared.applicationState == .active else {throw LiveActivityError.foregroundRequired}
        isStarting=true;defer{isStarting=false}
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabled
        }
        tokenTasks.forEach{$0.cancel()};tokenTasks=[]
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            Task {await onPushToken?(activity.id, "")}
        }
        let attributes = ConnectionActivityAttributes(partnerName:partnerName,showBattery:showBattery,showThoughts:showThoughts,showStatus:showStatus,showQuickAction:showQuickAction)
        let state = ConnectionActivityAttributes.ContentState(
            battery: battery,
            motion: motion,
            lastUpdate: updatedAt ?? .distantPast,
            myThoughts: mine,
            partnerThoughts: partner,
            status: status,quietUntil:quietUntil
        )
        let activity: Activity<ConnectionActivityAttributes>
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: updatedAt?.addingTimeInterval(120) ?? .now,relevanceScore:100), pushType: .token)
        } catch {
            // Local activities are useful even when a sideload profile cannot support APNs.
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: updatedAt?.addingTimeInterval(120) ?? .now,relevanceScore:100))
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
            staleDate: updatedAt?.addingTimeInterval(120) ?? .now,relevanceScore:100
        )
        for activity in Activity<ConnectionActivityAttributes>.activities {
            await activity.update(content)
        }
        isRunning = Activity<ConnectionActivityAttributes>.activities.contains{$0.activityState == .active || $0.activityState == .stale}
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
    case disabled, foregroundRequired
    var errorDescription: String? {
        switch self {
        case .disabled:"Live-Aktivitäten sind auf diesem iPhone deaktiviert. Aktiviere sie in Einstellungen → Apps → RJ Love → Live-Aktivitäten."
        case .foregroundRequired:"Öffne RJ Love vollständig, um die Live-Aktivität zu starten."
        }
    }
}
