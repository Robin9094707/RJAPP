import Foundation

enum RecordKind: String, Codable, CaseIterable, Sendable {
    case note
    case reminder
    case moment
    case geofence
    case calendar
    case chat, wish, milestone, checkin, coupon, gratitude
}

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let accent: String
    let storageLimitMB: Int

    enum CodingKeys: String, CodingKey {
        case id, accent
        case displayName = "display_name"
        case storageLimitMB = "storage_limit_mb"
    }
}

struct PresencePayload: Codable, Hashable, Sendable {
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var speed: Double?
    var course: Double?
    var locationTimestamp: String?
    var batteryLevel: Int?
    var batteryState: String?
    var lowPowerMode: Bool?
    var networkType: String?
    var wifiName: String?
    var focusActive: Bool?
    var motion: String?
    var steps: Int?
    var sleepMinutes: Int?
    var sleepScore: Int?
    var healthMetrics: [String: Double]?
    var healthUpdatedAt: String?
    var locationSharing: Bool?
    var statusMessage: String?
    var deviceName: String?
    var appVersion: String?
    var reportedAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, altitude, speed, course, steps, motion
        case horizontalAccuracy = "horizontal_accuracy"
        case locationTimestamp = "location_timestamp"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case lowPowerMode = "low_power_mode"
        case networkType = "network_type"
        case wifiName = "wifi_name"
        case focusActive = "focus_active"
        case sleepMinutes = "sleep_minutes"
        case sleepScore = "sleep_score"
        case healthMetrics = "health_metrics"
        case healthUpdatedAt = "health_updated_at"
        case locationSharing = "location_sharing"
        case statusMessage = "status_message"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case reportedAt = "reported_at"
        case updatedAt = "updated_at"
    }
}

struct PartnerSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let accent: String
    let storageLimitMB: Int
    var presence: PresencePayload?

    enum CodingKeys: String, CodingKey {
        case id, accent, presence
        case displayName = "display_name"
        case storageLimitMB = "storage_limit_mb"
    }
}

struct MomentComment: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var authorID: String
    var authorName: String
    var text: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case authorID = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
    }
}

struct MomentReaction: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(authorID)-\(emoji)" }
    var authorID: String
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case emoji
        case authorID = "author_id"
    }
}

struct RecordPayload: Codable, Hashable, Sendable {
    var title: String?
    var text: String?
    var message: String?
    var dueAt: String?
    var targetID: String?
    var alarmEnabled: Bool?
    var completed: Bool?
    var caption: String?
    var imageBase64: String?
    var mimeType: String?
    var comments: [MomentComment]?
    var reactions: [MomentReaction]?
    var name: String?
    var latitude: Double?
    var longitude: Double?
    var radius: Double?
    var notifyOnEnter: Bool?
    var notifyOnExit: Bool?
    var startAt: String?
    var endAt: String?
    var notes: String?
    var location: String?

    enum CodingKeys: String, CodingKey {
        case title, text, message, completed, caption, comments, reactions, name
        case latitude, longitude, radius, notes, location
        case dueAt = "due_at"
        case targetID = "target_id"
        case alarmEnabled = "alarm_enabled"
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case notifyOnEnter = "notify_on_enter"
        case notifyOnExit = "notify_on_exit"
        case startAt = "start_at"
        case endAt = "end_at"
    }

    init(
        title: String? = nil,
        text: String? = nil,
        message: String? = nil,
        dueAt: String? = nil,
        targetID: String? = nil,
        alarmEnabled: Bool? = nil,
        completed: Bool? = nil,
        caption: String? = nil,
        imageBase64: String? = nil,
        mimeType: String? = nil,
        comments: [MomentComment]? = nil,
        reactions: [MomentReaction]? = nil,
        name: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radius: Double? = nil,
        notifyOnEnter: Bool? = nil,
        notifyOnExit: Bool? = nil,
        startAt: String? = nil,
        endAt: String? = nil,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.title = title
        self.text = text
        self.message = message
        self.dueAt = dueAt
        self.targetID = targetID
        self.alarmEnabled = alarmEnabled
        self.completed = completed
        self.caption = caption
        self.imageBase64 = imageBase64
        self.mimeType = mimeType
        self.comments = comments
        self.reactions = reactions
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
        self.startAt = startAt
        self.endAt = endAt
        self.notes = notes
        self.location = location
    }
}

struct SharedRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: RecordKind
    let ownerID: String
    var payload: RecordPayload
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, payload
        case ownerID = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteCommand: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let ownerID: String
    let targetID: String
    let kind: String
    let payload: CommandPayload
    let dueAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, payload
        case ownerID = "owner_id"
        case targetID = "target_id"
        case dueAt = "due_at"
        case createdAt = "created_at"
    }
}

struct CommandPayload: Codable, Hashable, Sendable {
    let message: String
}

struct RemoteEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case createdAt = "created_at"
    }
}

struct ServerFeatures: Codable, Hashable, Sendable {
    let audioStudioEnabled: Bool?
    let apnsEnabled: Bool
    let lowBatteryThreshold: Int
    let maxRequestMB: Int

    enum CodingKeys: String, CodingKey {
        case audioStudioEnabled = "audio_studio_enabled"
        case apnsEnabled = "apns_enabled"
        case lowBatteryThreshold = "low_battery_threshold"
        case maxRequestMB = "max_request_mb"
    }
}

struct BootstrapResponse: Codable, Sendable {
    let farts: [FartClip]?
    let serverTime: String
    let localDay: String
    let me: UserProfile
    let partners: [PartnerSnapshot]
    let myPresence: PresencePayload?
    let thoughts: [String: Int]
    let records: [SharedRecord]
    let commands: [RemoteCommand]
    let events: [RemoteEvent]
    let storageUsedBytes: Int
    let features: ServerFeatures

    enum CodingKeys: String, CodingKey {
        case me, partners, thoughts, records, commands, events, features, farts
        case serverTime = "server_time"
        case localDay = "local_day"
        case myPresence = "my_presence"
        case storageUsedBytes = "storage_used_bytes"
    }
}

struct LoginResponse: Codable, Sendable {
    let token: String
    let expiresAt: String
    let user: UserProfile
    let serverVersion: String

    enum CodingKeys: String, CodingKey {
        case token, user
        case expiresAt = "expires_at"
        case serverVersion = "server_version"
    }
}

struct ThoughtResponse: Codable, Sendable {
    let day: String
    let count: Int
}

struct CreatedCommandResponse: Codable, Sendable {
    let id: String
}

struct APIErrorEnvelope: Codable, Sendable {
    let error: String
    let message: String
}

struct EmptyResponse: Codable, Sendable {}

extension ISO8601DateFormatter {
    static let rjLove: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let rjLoveBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension String {
    var rjDate: Date? {
        ISO8601DateFormatter.rjLove.date(from: self) ?? ISO8601DateFormatter.rjLoveBasic.date(from: self)
    }
}

extension Date {
    var rjISO8601: String {
        ISO8601DateFormatter.rjLove.string(from: self)
    }
}
