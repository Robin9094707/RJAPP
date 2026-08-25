import Foundation

struct CachedAppSnapshot: Codable, Sendable {
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

    private struct Envelope: Codable {
        let version: Int
        let snapshot: CachedAppSnapshot
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
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RJLove", isDirectory: true)
            .appendingPathComponent("offline-cache-v1.json")
    }
}
