import Foundation

struct WidgetSnapshot: Codable, Hashable, Sendable {
    var connectionIssue:String? = nil
    var locationSharing:Bool? = nil
    var distanceMeters:Int? = nil
    var distanceValidUntil:String? = nil
    var locationUpdatedAt:String? = nil
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
    var countdowns:[LoveCountdown]? = nil
    var milestoneTitle: String?
    var milestoneDate: String?
}

struct PendingThought:Codable {let id:String;let occurredAt:String?}

enum WidgetSharedStore {
    static let configuredSuite = "group.dfbc88d056a46f1b.1"
    static let suiteName: String = {
        let configured=Bundle.main.object(forInfoDictionaryKey:"RJAppGroupIdentifier") as? String ?? configuredSuite
        for candidate in [configured,"group.eu.rjuhas.rjlove"] {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:candidate) != nil {return candidate}
        }
        return configured
    }()
    static var connected:Bool {FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:suiteName) != nil}
    static var connectionMessage:String? {connected ? nil:"App und Widget sind nicht verbunden. App-Group-Signierung prüfen."}
    private static let snapshotKey = "rjlove.widget.snapshot.v1"
    private static let pendingThoughtsKey = "rjlove.widget.pending-thoughts.v1"
    private static let pendingThoughtsDayKey = "rjlove.widget.pending-thoughts-day.v1"

    static var defaults: UserDefaults? {
        guard connected else{return nil}
        return UserDefaults(suiteName:suiteName)
    }

    static func loadSnapshot() -> WidgetSnapshot {
        guard let defaults else {var value=WidgetSnapshot();value.connectionIssue=connectionMessage;return value}
        if Bundle.main.bundleURL.pathExtension=="appex" {defaults.set(Date.now.rjISO8601,forKey:"rjlove.widget-read-at");defaults.set(Bundle.main.bundleIdentifier,forKey:"rjlove.widget-reader")}
        let directory=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:suiteName)!
        guard let data = (try? Data(contentsOf:directory.appendingPathComponent("widget-snapshot-v2.json"))) ?? defaults.data(forKey: snapshotKey),
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
        guard let defaults,let directory=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:suiteName),let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to:directory.appendingPathComponent("widget-snapshot-v2.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        defaults.set(data, forKey: snapshotKey)
    }

    private static var queueURL:URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:suiteName)?.appendingPathComponent("pending-hearts-v3.json")
    }
    private static func withQueue<T>(_ action:(inout [PendingThought])->T)->T? {
        guard let url=queueURL,let defaults else{return nil}
        var failure:NSError?;var result:T?
        NSFileCoordinator().coordinate(writingItemAt:url,options:.forMerging,error:&failure){coordinated in
            var queue=(try? Data(contentsOf:coordinated)).flatMap{try? JSONDecoder().decode([PendingThought].self,from:$0)} ?? []
            if !defaults.bool(forKey:"rjlove.hearts-migrated") {
                queue += (0..<min(10000,max(0,defaults.integer(forKey:pendingThoughtsKey)))).map{_ in PendingThought(id:UUID().uuidString,occurredAt:nil)}
                defaults.set(true,forKey:"rjlove.hearts-migrated");defaults.removeObject(forKey:pendingThoughtsKey)
            }
            let value=action(&queue)
            if let data=try? JSONEncoder().encode(queue),(try? data.write(to:coordinated,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])) != nil {result=value}
        }
        return result
    }
    static func addPendingThought()->Int {
        let count=withQueue{queue in queue.append(PendingThought(id:UUID().uuidString,occurredAt:Date.now.rjISO8601));return queue.count} ?? 0
        if count>0 {var snapshot=loadSnapshot();snapshot.myThoughts += 1;saveSnapshot(snapshot)}
        return count
    }
    static func pendingThoughts()->Int {withQueue{$0.count} ?? 0}
    static func pendingThoughtsToday()->Int {withQueue{$0.filter{$0.occurredAt?.rjDate.map{Calendar.current.isDateInToday($0)} ?? true}.count} ?? 0}
    static func nextPendingThought()->PendingThought? {withQueue{$0.first} ?? nil}
    static func consumePendingThought(id:String)->Bool {withQueue{queue in guard let index=queue.firstIndex(where:{$0.id==id}) else{return false};queue.remove(at:index);return true} ?? false}
    static func consumeOnePendingThought()->Bool {withQueue{queue in guard !queue.isEmpty else{return false};queue.removeFirst();return true} ?? false}
    static func clearPendingThoughts(){withQueue{$0.removeAll()};defaults?.removeObject(forKey:pendingThoughtsKey);defaults?.removeObject(forKey:pendingThoughtsDayKey)}
    static func migrateLegacyAppData() {
        guard let defaults,let target=queueURL,!defaults.bool(forKey:"rjlove.group-migration-392") else{return}
        var oldDefaults:[UserDefaults]=[.standard]
        if suiteName != "group.eu.rjuhas.rjlove",FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:"group.eu.rjuhas.rjlove") != nil,let old=UserDefaults(suiteName:"group.eu.rjuhas.rjlove"){oldDefaults.append(old)}
        if defaults.data(forKey:snapshotKey)==nil,let data=oldDefaults.compactMap({$0.data(forKey:snapshotKey)}).first,let value=try? JSONDecoder().decode(WidgetSnapshot.self,from:data){saveSnapshot(value)}
        var candidates=[FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("pending-hearts-v3.json")]
        if let old=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:"group.eu.rjuhas.rjlove"){candidates.append(old.appendingPathComponent("pending-hearts-v3.json"))}
        for source in candidates where source != target {
            guard let bytes=try? Data(contentsOf:source),let values=try? JSONDecoder().decode([PendingThought].self,from:bytes) else{continue}
            let success=withQueue{queue in let ids=Set(queue.map(\.id));queue += values.filter{!ids.contains($0.id)};return true} ?? false
            if success{try? FileManager.default.removeItem(at:source)}
        }
        defaults.set(true,forKey:"rjlove.group-migration-392")
    }

    static func localDayStamp(date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

}
