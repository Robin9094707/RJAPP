import Foundation
import ActivityKit

struct FartRating: Codable, Hashable, Sendable {
    let userID: String
    let overall: Int
    let power: Int
    let style: Int
    let comment: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey { case overall, power, style, comment; case userID = "user_id"; case updatedAt = "updated_at" }
}
struct FartReaction: Codable, Hashable, Sendable {
    let userID: String
    let emoji: String
    enum CodingKeys: String, CodingKey { case emoji; case userID = "user_id" }
}
struct FartClip: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let ownerID: String
    let title: String
    let caption: String
    let category: String
    let duration: Double
    let waveform: [Double]
    let sizeBytes: Int
    let createdAt: String
    let ratings: [FartRating]
    let reactions: [FartReaction]
    var revision: Int? = nil
    var updatedAt: String? = nil
    var stars: Int? { ratings.first?.overall }
    enum CodingKeys: String, CodingKey {
        case id, title, caption, category, duration, waveform, ratings, reactions, revision
        case updatedAt = "updated_at"
        case ownerID = "owner_id"; case sizeBytes = "size_bytes"; case createdAt = "created_at"
    }
}
struct FartUpload: Encodable {
    let id: String
    let title: String
    let caption: String
    let category: String
    let duration: Double
    let waveform: [Double]
    var baseRevision: Int? = nil
    var editID: String? = nil
    let audioBase64: String
    enum CodingKeys: String, CodingKey { case id, title, caption, category, duration, waveform; case audioBase64 = "audio_base64"; case baseRevision = "base_revision"; case editID = "edit_id" }
}
enum FartCategory: String, CaseIterable, Identifiable {
    case natural = "Naturtalent", thunder = "Donnergrollen", ninja = "Ninja", trumpet = "Trompete", duck = "Quietschente", love = "Liebeslüftchen"
    var id: String { rawValue }
    var emoji: String {
        switch self { case .natural: "💨"; case .thunder: "⛈️"; case .ninja: "🥷"; case .trumpet: "🎺"; case .duck: "🦆"; case .love: "💗" }
    }
}
struct FartRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var startedAt: Date; var elapsed: Int; var paused: Bool }
    var title: String
}
