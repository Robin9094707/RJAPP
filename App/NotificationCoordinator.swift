import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let rjDeviceTokenReceived = Notification.Name("eu.rjuhas.rjlove.device-token")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefreshCoordinator.shared.handler = { await BackgroundDeliveryService.shared.run(source: "iOS-Hintergrundaktualisierung") }
        BackgroundRefreshCoordinator.shared.register()
        let action = UNNotificationAction(identifier: "RJ_SCHEDULE_WAKE", title: "Weckruf jetzt einplanen", options: [])
        let open = UNNotificationAction(identifier: "RJ_OPEN_WAKE", title: "App öffnen & prüfen", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "RJ_WAKE", actions: [action, open], intentIdentifiers: [], options: [])])
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: NotificationCoordinator.deviceTokenKey)
        Task { @MainActor in PushRegistrationStatus.shared.error = nil }
        NotificationCenter.default.post(name: .rjDeviceTokenReceived, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushRegistrationStatus.shared.failed(error)
            DebugLogger.shared.log("APNs-Registrierung: \(error.localizedDescription)", category: "Push")
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let completion = BackgroundPushCompletion(completionHandler)
            let timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                BackgroundDeliveryService.shared.cancel()
                completion.finish(.failed)
            }
            let success = await BackgroundDeliveryService.shared.run(source: "APNs-Hintergrundpush")
            timeout.cancel()
            completion.finish(success ? .newData : .failed)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            _ = await BackgroundDeliveryService.shared.run(source: response.actionIdentifier == "RJ_SCHEDULE_WAKE" ? "Mitteilungsaktion ohne App-Oberfläche" : "Mitteilung geöffnet")
            completionHandler()
        }
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
    var deviceTokenAvailable: Bool { UserDefaults.standard.string(forKey: Self.deviceTokenKey) != nil }
    static let shared = NotificationCoordinator()
    static let deviceTokenKey = "rjlove.apns-device-token"

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
        guard event.kind != "record_photo_request" else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.userInfo = ["rj_event_id": event.id, "rj_event_kind": event.kind]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// APNs fetch completion must be called exactly once, within the iOS time budget.
@MainActor private final class BackgroundPushCompletion {
    private var handler: ((UIBackgroundFetchResult) -> Void)?
    init(_ handler: @escaping (UIBackgroundFetchResult) -> Void) { self.handler = handler }
    func finish(_ result: UIBackgroundFetchResult) {
        let completion = handler
        handler = nil
        completion?(result)
    }
}

