import Foundation
import Observation

struct DebugEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let category: String
    let message: String
}

@MainActor
@Observable
final class DebugLogger {
    static let shared = DebugLogger()

    private(set) var entries: [DebugEntry] = []
    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("rjlove-debug.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([DebugEntry].self, from: data) {
            entries = Array(decoded.suffix(300))
        }
    }

    func log(_ message: String, category: String = "App") {
        let sanitized = message
            .replacingOccurrences(of: "Bearer ", with: "Bearer [geschützt]")
        entries.append(DebugEntry(id: UUID(), timestamp: .now, category: category, message: sanitized))
        if entries.count > 300 {
            entries.removeFirst(entries.count - 300)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
