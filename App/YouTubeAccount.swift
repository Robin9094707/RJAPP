import Foundation
import Observation

struct YouTubePlaylist: Identifiable { let id: String; let title: String }
@MainActor @Observable final class YouTubeAccount {
    static let shared = YouTubeAccount()
    var connected = false
    var channel = ""
    var playlists: [YouTubePlaylist] = []
    var videos: [YouTubeResult] = []
    var authURL: URL?
    var error: String?
    var busy = false
    private var namespace = ""
    private var api: APIClient?
    private var access: String?
    private var refresh: String?
    private var expiry = Date.distantPast
    private var task: Task<Void, Never>?
    private let session = URLSession(configuration: .ephemeral)
    func configure(namespace: String, api: APIClient?) {
        guard self.namespace != namespace else { return }
        reset(); self.namespace = namespace; self.api = api
        refresh = KeychainStore.get(namespace + ".youtube.refresh")
        access = KeychainStore.get(namespace + ".youtube.access")
        expiry = Date(timeIntervalSince1970: Double(KeychainStore.get(namespace + ".youtube.expiry") ?? "0") ?? 0)
        connected = access != nil || refresh != nil
    }
    func reset() { task?.cancel(); task = nil; access = nil; refresh = nil; connected = false; busy = false; error = nil; channel = ""; playlists = []; videos = []; authURL = nil; namespace = ""; api = nil; expiry = .distantPast }
    func disconnect() async {
        let credential = refresh ?? access
        let keys = ["refresh", "access", "expiry"]
        for key in keys { KeychainStore.delete(namespace + ".youtube." + key) }
        let space = namespace, client = api; reset(); configure(namespace: space, api: client)
        if let credential {
            var url = URLComponents(string: "https://oauth2.googleapis.com/revoke")!; url.queryItems = [URLQueryItem(name: "token", value: credential)]
            var request = URLRequest(url: url.url!); request.httpMethod = "POST"
            _ = try? await session.data(for: request)
        }
    }
    struct Tokens: Decodable {
        let ready: Bool?
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        enum CodingKeys: String, CodingKey { case ready; case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
    }
    private func save(_ tokens: Tokens) throws {
        if let access = tokens.accessToken { self.access = access; try KeychainStore.set(access, for: namespace + ".youtube.access") }
        if let refresh = tokens.refreshToken { self.refresh = refresh; try KeychainStore.set(refresh, for: namespace + ".youtube.refresh") }
        expiry = .now.addingTimeInterval(max(0, (tokens.expiresIn ?? 3600) - 60))
        try KeychainStore.set(String(expiry.timeIntervalSince1970), for: namespace + ".youtube.expiry")
        connected = access != nil
    }
    func signIn() async {
        guard let api, !busy else { return }; busy = true; defer { busy = false }
        do {
            guard try api.request(path: "", method: "GET").url?.scheme == "https" else { throw APIClientError.transport("Google-Anmeldung benötigt HTTPS an eurem RJ-Server.") }
            struct Flow: Decodable { let state: String; let url: URL }
            let flow = try await api.cinema("youtube/connect", body: [:], as: Flow.self)
            authURL = flow.url
            let space = namespace
            task?.cancel()
            task = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<150 {
                    do {
                        try await Task.sleep(for: .seconds(2)); try Task.checkCancellation()
                        let tokens = try await api.cinema("youtube/claim", body: ["state": flow.state], as: Tokens.self)
                        guard self.namespace == space else { return }
                        if tokens.ready == true { try self.save(tokens); self.authURL = nil; await self.loadLibrary(); return }
                    } catch is CancellationError { return }
                    catch { self.error = error.localizedDescription; self.authURL = nil; return }
                }
                self.error = "Google-Anmeldung abgelaufen. Bitte erneut verbinden."; self.authURL = nil
            }
        } catch { self.error = error.localizedDescription }
    }
    private func data(_ endpoint: String, query: [URLQueryItem]) async throws -> [String: Any] {
        let space = namespace
        if expiry <= .now, let refresh, let api {
            let tokens = try await api.cinema("youtube/refresh", body: ["refresh_token": refresh], as: Tokens.self)
            guard namespace == space else { throw CancellationError() }; try save(tokens)
        }
        guard let access else { throw APIClientError.transport("Bitte dein YouTube-Konto verbinden.") }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + endpoint)!
        url.queryItems = query
        var request = URLRequest(url: url.url!); request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let (data,response) = try await session.data(for: request)
        guard namespace == space else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIClientError.transport("YouTube-Kontozugriff fehlgeschlagen. Anmeldung und Google-API-Freigabe prüfen.") }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    func loadLibrary() async {
        guard connected, !busy else { return }; busy = true; defer { busy = false }
        do {
            let channels = try await data("channels", query: [.init(name: "part", value: "snippet"), .init(name: "mine", value: "true")])
            let first = (channels["items"] as? [[String: Any]])?.first
            channel = (first?["snippet"] as? [String: Any])?["title"] as? String ?? "Mein YouTube"
            var page: String?
            var result: [YouTubePlaylist] = []
            repeat {
                var query: [URLQueryItem] = [.init(name: "part",value: "snippet"), .init(name: "mine",value: "true"), .init(name: "maxResults",value: "50")]
                if let page { query.append(.init(name: "pageToken",value: page)) }
                let value = try await data("playlists", query: query)
                result += (value["items"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? String, let snippet = item["snippet"] as? [String: Any] else { return nil }
                    return YouTubePlaylist(id: id, title: snippet["title"] as? String ?? "Playlist")
                }
                page = value["nextPageToken"] as? String
            } while page != nil && !Task.isCancelled
            playlists = result; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func loadPlaylist(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            var result: [YouTubeResult] = []; var page: String?
            repeat {
                var query: [URLQueryItem] = [.init(name: "part",value: "snippet"), .init(name: "playlistId",value: id), .init(name: "maxResults",value: "50")]
                if let page { query.append(.init(name: "pageToken",value: page)) }
                let value = try await data("playlistItems", query: query)
                result += (value["items"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let snippet = item["snippet"] as? [String: Any], let resource = snippet["resourceId"] as? [String: Any], let id = resource["videoId"] as? String else { return nil }
                    return YouTubeResult(id: id, title: snippet["title"] as? String ?? "YouTube", channel: snippet["videoOwnerChannelTitle"] as? String ?? "")
                }
                page = value["nextPageToken"] as? String
            } while page != nil && !Task.isCancelled
            // A playlist may contain the same video more than once.
            var ids = Set<String>(); videos = result.filter { ids.insert($0.id).inserted }; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
