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
struct FartLocation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let capturedAt: String
    enum CodingKeys: String, CodingKey { case latitude, longitude, accuracy; case capturedAt = "captured_at" }
}
enum FartSituation: String, CaseIterable, Identifiable {
    case alltag, morgen, nacht, unterwegs, date, essen, leise, zugabe
    var id: String { rawValue }
    var title: String {
        switch self { case .alltag: "Einfach so"; case .morgen: "Guten Morgen"; case .nacht: "Nachtschwärmer"; case .unterwegs: "Unterwegs"; case .date: "Zeit zu zweit"; case .essen: "Nach dem Essen"; case .leise: "Heimlich & leise"; case .zugabe: "Noch eine Zugabe" }
    }
    var symbol: String {
        switch self { case .alltag: "wind"; case .morgen: "sunrise.fill"; case .nacht: "moon.stars.fill"; case .unterwegs: "figure.walk"; case .date: "heart.fill"; case .essen: "fork.knife"; case .leise: "speaker.slash.fill"; case .zugabe: "sparkles" }
    }
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
    var commentCount: Int? = nil
    var revision: Int? = nil
    var updatedAt: String? = nil
    var recordedAt: String? = nil
    var location: FartLocation? = nil
    var situation: String? = nil
    var date: Date? { (recordedAt ?? createdAt).rjDate }
    var stars: Int? { ratings.first?.overall }
    enum CodingKeys: String, CodingKey {
        case id, title, caption, category, duration, waveform, ratings, reactions, revision, location, situation
        case commentCount = "comment_count"
        case recordedAt = "recorded_at"
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
    var recordedAt: String? = nil
    var location: FartLocation? = nil
    var situation: String? = nil
    var baseRevision: Int? = nil
    var editID: String? = nil
    let audioBase64: String
    enum CodingKeys: String, CodingKey { case id, title, caption, category, duration, waveform; case location, situation; case recordedAt = "recorded_at"; case audioBase64 = "audio_base64"; case baseRevision = "base_revision"; case editID = "edit_id" }
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

struct FartComment:Codable,Identifiable,Hashable,Sendable {
    let id:String
    let clipID:String
    let userID:String
    let text:String
    let createdAt:String
    enum CodingKeys:String,CodingKey {case id,text;case clipID="clip_id",userID="user_id",createdAt="created_at"}
}
