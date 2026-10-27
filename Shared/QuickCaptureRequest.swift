import Foundation

/// The foreground intent runs in the app process. Keep a local copy as well as
/// the optional App Group copy, so re-signing without groups cannot lose a tap.
struct QuickCaptureRequest: Codable, Equatable {
    let id: String
    let createdAt: Date
}
enum QuickCaptureRequests {
    static let notification = Notification.Name("rjEmergencyFartRequested")
    private static let key = "rjlove.quick-capture.v2"
    private static let acknowledgedKey = "rjlove.quick-capture.acknowledged"
    @discardableResult static func enqueue() -> QuickCaptureRequest {
        let request = QuickCaptureRequest(id: UUID().uuidString, createdAt: .now)
        if let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: key)
            WidgetSharedStore.defaults?.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: notification, object: nil)
        return request
    }
    static func pending() -> QuickCaptureRequest? {
        let acknowledged = UserDefaults.standard.string(forKey: acknowledgedKey)
        let candidates = [UserDefaults.standard.data(forKey: key), WidgetSharedStore.defaults?.data(forKey: key)]
            .compactMap { $0 }.compactMap { try? JSONDecoder().decode(QuickCaptureRequest.self, from: $0) }
            .filter { $0.id != acknowledged && Date.now.timeIntervalSince($0.createdAt) < 3600 }
        if let request = candidates.max(by: { $0.createdAt < $1.createdAt }) { return request }
        // Honor requests left by an older installed widget exactly once.
        if WidgetSharedStore.defaults?.bool(forKey: "rjlove.quick-fart-requested") == true {
            WidgetSharedStore.defaults?.removeObject(forKey: "rjlove.quick-fart-requested")
            return enqueue()
        }
        return nil
    }
    static func acknowledge(_ id: String) {
        UserDefaults.standard.set(id, forKey: acknowledgedKey)
        for defaults in [UserDefaults.standard, WidgetSharedStore.defaults].compactMap({ $0 }) {
            if let data = defaults.data(forKey: key),
               let request = try? JSONDecoder().decode(QuickCaptureRequest.self, from: data), request.id == id {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
