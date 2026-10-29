import Foundation

struct CachedAppSnapshot: Codable, Sendable {
    var farts: [FartClip]? = nil
    var activity:[String:PartnerActivity]? = nil
    var lastOpened:[String:String]? = nil
    let profile: ServerProfile
    let localDay: String
    let me: UserProfile
    let partners: [PartnerSnapshot]
    let records: [SharedRecord]
    let thoughts: [String: Int]
    let storageUsedBytes: Int
    let features: ServerFeatures
    let lastSync: Date
}

enum AppCache {
    private static let cacheVersion = 1
    /// Encoding and writing happen on this serial queue, never on the main thread.
    private static let queue = DispatchQueue(label: "eu.rjuhas.rjlove.offline-cache", qos: .utility)
    private static let state = PendingState()

    private struct Envelope: Codable {
        let version: Int
        let snapshot: CachedAppSnapshot
    }

    /// Coalesces bursts of saves: only the newest snapshot of a generation is written.
    private final class PendingState: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 0
        private var latest: CachedAppSnapshot?
        func enqueue(_ snapshot: CachedAppSnapshot) -> Int {
            lock.lock(); defer { lock.unlock() }
            latest = snapshot
            return generation
        }
        func take(for expected: Int) -> CachedAppSnapshot? {
            lock.lock(); defer { lock.unlock() }
            guard expected == generation else { return nil }
            let value = latest
            latest = nil
            return value
        }
        func invalidate() {
            lock.lock(); defer { lock.unlock() }
            generation += 1
            latest = nil
        }
    }

    static func load(matching profile: ServerProfile) -> CachedAppSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == cacheVersion,
              envelope.snapshot.profile == profile else {
            return nil
        }
        return envelope.snapshot
    }

    static func save(_ snapshot: CachedAppSnapshot) {
        let generation = state.enqueue(snapshot)
        queue.async {
            // A later save replaces this one; a logout invalidates both.
            guard let value = state.take(for: generation) else { return }
            write(value)
        }
    }

    private static func write(_ snapshot: CachedAppSnapshot) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Envelope(version: cacheVersion, snapshot: snapshot))
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in
                DebugLogger.shared.log("Offline-Cache: \(message)", category: "Speicher")
            }
        }
    }

    static func clear() {
        state.invalidate()
        guard let fileURL else { return }
        // Remove synchronously after any write already in flight, so no stale snapshot survives a logout.
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RJLove", isDirectory: true)
            .appendingPathComponent("offline-cache-v1.json")
    }
}
