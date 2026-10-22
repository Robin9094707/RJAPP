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
    var partnerSteps: Int?
    var partnerSleepMinutes: Int?
    var milestoneTitle: String?
    var milestoneDate: String?
}

struct PendingThought:Codable {let id:String;let occurredAt:String?}

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
            snapshot.myThoughts = pendingThoughtsToday()
            snapshot.partnerThoughts = 0
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private static var queueURL:URL {
        let directory=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:suiteName) ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        return directory.appendingPathComponent("pending-hearts-v3.json")
    }
    private static func withQueue<T>(_ action:(inout [PendingThought])->T)->T {
        let url=queueURL;var failure:NSError?;var result:T?
        NSFileCoordinator().coordinate(writingItemAt:url,options:.forMerging,error:&failure){coordinated in
            var queue=(try? Data(contentsOf:coordinated)).flatMap{try? JSONDecoder().decode([PendingThought].self,from:$0)} ?? []
            if !defaults.bool(forKey:"rjlove.hearts-migrated") {
                queue += (0..<min(10000,max(0,defaults.integer(forKey:pendingThoughtsKey)))).map{_ in PendingThought(id:UUID().uuidString,occurredAt:nil)}
                defaults.set(true,forKey:"rjlove.hearts-migrated");defaults.removeObject(forKey:pendingThoughtsKey)
            }
            result=action(&queue)
            if let data=try? JSONEncoder().encode(queue){try? data.write(to:coordinated,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])}
        }
        if let result{return result}
        var queue:[PendingThought]=[];return action(&queue)
    }
    static func addPendingThought()->Int {
        let count=withQueue{queue in queue.append(PendingThought(id:UUID().uuidString,occurredAt:Date.now.rjISO8601));return queue.count}
        var snapshot=loadSnapshot();snapshot.myThoughts += 1;saveSnapshot(snapshot);return count
    }
    static func pendingThoughts()->Int {withQueue{$0.count}}
    static func pendingThoughtsToday()->Int {withQueue{$0.filter{$0.occurredAt?.rjDate.map{Calendar.current.isDateInToday($0)} ?? true}.count}}
    static func nextPendingThought()->PendingThought? {withQueue{$0.first}}
    static func consumeOnePendingThought()->Bool {withQueue{queue in guard !queue.isEmpty else{return false};queue.removeFirst();return true}}
    static func clearPendingThoughts(){withQueue{$0.removeAll()};defaults.removeObject(forKey:pendingThoughtsKey);defaults.removeObject(forKey:pendingThoughtsDayKey)}

    static func localDayStamp(date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

}
