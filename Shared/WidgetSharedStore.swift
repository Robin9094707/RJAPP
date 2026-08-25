import Foundation

struct WidgetSnapshot: Codable, Hashable, Sendable {
    var partnerName = "Schatzi"
    var partnerBattery: Int?
    var partnerBatteryState: String?
    var partnerNetwork: String?
    var partnerMotion: String?
    var partnerLastSeen: String?
    var myThoughts = 0
    var partnerThoughts = 0
    var lastSync: String?
}

enum WidgetSharedStore {
    static let suiteName = "group.eu.rjuhas.rjlove"
    private static let snapshotKey = "rjlove.widget.snapshot.v1"
    private static let pendingThoughtsKey = "rjlove.widget.pending-thoughts.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func loadSnapshot() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func addPendingThought() -> Int {
        let next = defaults.integer(forKey: pendingThoughtsKey) + 1
        defaults.set(next, forKey: pendingThoughtsKey)
        return next
    }

    static func pendingThoughts() -> Int {
        defaults.integer(forKey: pendingThoughtsKey)
    }

    static func consumeOnePendingThought() -> Bool {
        let value = pendingThoughts()
        guard value > 0 else { return false }
        defaults.set(value - 1, forKey: pendingThoughtsKey)
        return true
    }
}
