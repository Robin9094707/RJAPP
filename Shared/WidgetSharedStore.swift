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
    private static let pendingThoughtsDayKey = "rjlove.widget.pending-thoughts-day.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func loadSnapshot() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        if let lastSync = snapshot.lastSync?.rjDate,
           !Calendar.current.isDateInToday(lastSync) {
            snapshot.myThoughts = pendingThoughts()
            snapshot.partnerThoughts = 0
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func addPendingThought() -> Int {
        resetPendingThoughtsIfNeeded()
        var snapshot = loadSnapshot()
        let next = defaults.integer(forKey: pendingThoughtsKey) + 1
        defaults.set(next, forKey: pendingThoughtsKey)
        defaults.set(localDayStamp(), forKey: pendingThoughtsDayKey)
        snapshot.myThoughts += 1
        saveSnapshot(snapshot)
        return next
    }

    static func pendingThoughts() -> Int {
        resetPendingThoughtsIfNeeded()
        defaults.integer(forKey: pendingThoughtsKey)
    }

    static func consumeOnePendingThought() -> Bool {
        let value = pendingThoughts()
        guard value > 0 else { return false }
        defaults.set(value - 1, forKey: pendingThoughtsKey)
        return true
    }

    static func clearPendingThoughts() {
        defaults.removeObject(forKey: pendingThoughtsKey)
        defaults.removeObject(forKey: pendingThoughtsDayKey)
    }

    static func localDayStamp(date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func resetPendingThoughtsIfNeeded() {
        let savedDay = defaults.string(forKey: pendingThoughtsDayKey)
        guard savedDay != nil, savedDay != localDayStamp() else { return }
        clearPendingThoughts()
    }
}
