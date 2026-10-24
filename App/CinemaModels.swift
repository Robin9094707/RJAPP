import Foundation

struct CinemaRoom: Decodable, Identifiable {
    let id: String
    let ownerID: String
    let provider: String
    let mediaID: String
    let title: String
    let position: Double
    let playing: Bool
    let revision: Int
    let serverTime: Double
    let sleepUntil: Double?
    let closed: Bool
    let members: [String]
    let joined: Bool
    let plexShared: Bool
    enum CodingKeys: String, CodingKey {
        case id, provider, title, position, playing, revision, closed, members, joined
        case ownerID = "owner_id", mediaID = "media_id", serverTime = "server_time"
        case sleepUntil = "sleep_until", plexShared = "plex_shared"
    }
}
struct CinemaStat: Decodable, Identifiable {
    let provider: String
    let seconds: Double
    let evenings: Int
    var id: String { provider }
}
struct YouTubeResult: Decodable, Identifiable {
    let id: String
    let title: String
    let channel: String
}
struct YouTubeSearchPage: Decodable {
    let items: [YouTubeResult]
    let nextPage: String?
    enum CodingKeys: String, CodingKey { case items; case nextPage = "next_page" }
}
struct CinemaFeatures: Decodable {
    let version: Int
    let youtubeSearch: Bool
    enum CodingKeys: String, CodingKey { case version; case youtubeSearch = "youtube_search" }
}
extension APIClient {
    func cinema<T: Decodable>(_ path: String, body: [String: Any]? = nil, as type: T.Type) async throws -> T {
        try await execute(request(path: "/v1/cinema/" + path, method: body == nil ? "GET" : "POST",
                                  body: body.map { try JSONSerialization.data(withJSONObject: $0) }), as: type)
    }
    func cinemaRooms() async throws -> [CinemaRoom] {
        struct Page: Decodable { let rooms: [CinemaRoom] }
        return try await cinema("rooms", as: Page.self).rooms
    }
    func cinemaStats() async throws -> [CinemaStat] {
        struct Page: Decodable { let stats: [CinemaStat] }
        return try await cinema("stats", as: Page.self).stats
    }
    func cinemaPlayback(_ room: String) async throws -> URL {
        struct Result: Decodable { let path: String }
        let value = try await cinema("rooms/" + room + "/playback", body: [:], as: Result.self)
        // request() preserves a reverse-proxy prefix; media endpoint is outside /v1.
        return try request(path: value.path, method: "GET").url!
    }
}
enum YouTubeLink {
    static func videoID(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil { return value }
        guard let url = URLComponents(string: value), let host = url.host?.lowercased(),
              ["youtu.be", "www.youtube.com", "youtube.com", "m.youtube.com", "www.youtube-nocookie.com"].contains(host) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let id = host == "youtu.be" ? parts.first : (["embed", "shorts", "live"].contains(parts.first ?? "") ? parts.dropFirst().first : url.queryItems?.first { $0.name == "v" }?.value)
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }
}
