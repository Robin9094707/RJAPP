import Foundation

struct QuietSchedule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var enabled = true
    var label = "Ich schlafe gerade 😴"
    var start = "22:00"
    var end = "06:00"
    var days = Array(0...6)
    var timezone = "Europe/Berlin"
}

struct ExternalPushSettings: Codable, Equatable {
    var provider = "bark"
    var barkDeviceKey = ""
    var ntfyServerURL = "https://ntfy.sh"
    var ntfyTopic = ""
    var ntfyAccessToken = ""
    var fallbackNtfy = false
    var allowCritical = true
    var sound = "alarm"
    var volume = 10
    var repeatLimitMinutes = 0
    var quietSchedules: [QuietSchedule] = []
    enum CodingKeys: String, CodingKey {
        case provider, sound, volume
        case barkDeviceKey = "bark_device_key", ntfyServerURL = "ntfy_server_url"
        case ntfyTopic = "ntfy_topic", ntfyAccessToken = "ntfy_access_token"
        case repeatLimitMinutes = "repeat_limit_minutes"
        case fallbackNtfy = "fallback_ntfy", allowCritical = "allow_critical", quietSchedules = "quiet_schedules"
    }
}

struct QuietStatus: Decodable {
    var active: Bool
    var label: String
    var until: String?
}
struct PartnerPushStatus: Decodable, Identifiable {
    var userID: String
    var displayName: String
    var provider: String
    var quiet: QuietStatus
    var id: String { userID }
    enum CodingKeys: String, CodingKey { case provider, quiet; case userID = "user_id", displayName = "display_name" }
}
struct ActivePushAlarm: Decodable, Identifiable {
    var id: String
    var message: String
    var attempts: Int
    var nextAt: String
    enum CodingKeys: String, CodingKey { case id, message, attempts; case nextAt = "next_at" }
}
struct ExternalPushStatus: Decodable {
    var settings: ExternalPushSettings
    var barkServerURL: String
    var ready: Bool
    var issues: [String]
    var quiet: QuietStatus
    var partners: [PartnerPushStatus]
    var attempts: [PushAttempt]
    var activeAlarms: [ActivePushAlarm]
    var integrationURL: String
    enum CodingKeys: String, CodingKey {
        case settings, ready, issues, quiet, partners, attempts
        case barkServerURL = "bark_server_url", activeAlarms = "active_alarms", integrationURL = "integration_url"
    }
}

extension APIClient {
    func externalPushStatus() async throws -> ExternalPushStatus {
        try await execute(try request(path: "/v1/notifications/settings", method: "GET"), as: ExternalPushStatus.self)
    }
    func saveExternalPush(_ settings: ExternalPushSettings) async throws -> ExternalPushStatus {
        try await execute(try request(path: "/v1/notifications/settings", method: "POST", body: encoder.encode(settings)), as: ExternalPushStatus.self)
    }
    func testExternalPush() async throws {
        _ = try await execute(try request(path: "/v1/notifications/test", method: "POST", body: Data("{}".utf8)), as: EmptyResponse.self)
    }
    func acknowledgePushAlarm(id: String) async throws {
        _ = try await execute(try request(path: "/v1/notifications/\(id)/ack", method: "POST", body: Data("{}".utf8)), as: EmptyResponse.self)
    }
}
