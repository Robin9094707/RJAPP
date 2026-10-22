import Foundation
struct ThoughtEvent: Codable, Identifiable, Sendable {
    let id: String
    let userID: String
    let occurredAt: String?
    let receivedAt: String
    enum CodingKeys: String,CodingKey { case id; case userID="user_id", occurredAt="occurred_at", receivedAt="received_at" }
}
struct OpenedRecord: Codable, Sendable {
    let recordID: String
    let userID: String
    let openedAt: String
    enum CodingKeys: String,CodingKey { case recordID="record_id",userID="user_id",openedAt="opened_at" }
}
struct AppRelease: Codable, Identifiable, Sendable {
    let id: String
    let version: String
    let build: String
    let createdAt: String
    enum CodingKeys: String,CodingKey {case id,version,build;case createdAt="created_at"}
}
