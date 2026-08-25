import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let rjRemoteSyncRequested = Notification.Name("eu.rjuhas.rjlove.remote-sync")
    static let rjDeviceTokenReceived = Notification.Name("eu.rjuhas.rjlove.device-token")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefreshCoordinator.shared.register()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .rjDeviceTokenReceived, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            DebugLogger.shared.log("APNs-Registrierung: \(error.localizedDescription)", category: "Push")
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: .rjRemoteSyncRequested, object: completionHandler)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@MainActor
final class NotificationCoordinator: ObservableObject {
    static let shared = NotificationCoordinator()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            DebugLogger.shared.log("Mitteilungen: \(error.localizedDescription)", category: "Push")
            return false
        }
    }

    func scheduleLocal(event: RemoteEvent) async {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.userInfo = ["rj_event_id": event.id, "rj_event_kind": event.kind]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
