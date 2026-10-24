import Foundation
import Observation

struct PlexConnection: Identifiable {
    let uri: String
    let local: Bool
    var id: String { uri }
}
struct PlexServer: Identifiable {
    let id: String
    let name: String
    let token: String
    let connections: [PlexConnection]
}
struct PlexEntry: Identifiable {
    let id: String
    let title: String
    let type: String
    let key: String
    let duration: Double
    let part: String?
    let container: String?
    init?(_ value: [String: Any]) {
        guard let key = value["key"] as? String else { return nil }
        self.key = key
        id = value["ratingKey"] as? String ?? key
        title = value["title"] as? String ?? "Plex"
        type = value["type"] as? String ?? "directory"
        duration = (value["duration"] as? Double ?? 0) / 1000
        let media = (value["Media"] as? [[String: Any]])?.first
        part = ((media?["Part"] as? [[String: Any]])?.first)?["key"] as? String
        container = media?["container"] as? String
    }
    var playable: Bool { ["movie", "episode", "clip", "track"].contains(type) }
}

@MainActor @Observable final class PlexCinemaClient {
    var servers: [PlexServer] = []
    var server: PlexServer?
    var connection: String?
    var entries: [PlexEntry] = []
    var authenticated = false
    var busy = false
    var error: String?
    var authURL: URL?
    var path = "/library/sections"
    var hasMore = false
    private var offset = 0
    private var pinTask: Task<Void, Never>?
    private var namespace = ""
    private var token: String?
    private var clientID = ""
    private let session = URLSession(configuration: .ephemeral)
    func configure(namespace: String) {
        guard self.namespace != namespace else { return }
        reset(); self.namespace = namespace
        clientID = KeychainStore.get(namespace + ".plex.client") ?? UUID().uuidString
        try? KeychainStore.set(clientID, for: namespace + ".plex.client")
        token = KeychainStore.get(namespace + ".plex.token"); authenticated = token != nil
    }
    func reset() {
        pinTask?.cancel(); pinTask = nil; token = nil; servers = []; server = nil
        entries = []; connection = nil; authenticated = false; authURL = nil; error = nil; busy = false; namespace = ""
    }
    func disconnect() {
        KeychainStore.delete(namespace + ".plex.token"); let space = namespace
        reset(); configure(namespace: space)
    }
    private func call(_ url: URL, token: String? = nil, method: String = "GET", body: Data? = nil) async throws -> Any {
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("RJ Love", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(RJVersion.app, forHTTPHeaderField: "X-Plex-Version")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        if body != nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIClientError.transport("Plex-Anmeldung oder Serverzugriff fehlgeschlagen.")
        }
        return try JSONSerialization.jsonObject(with: data)
    }
    func signIn() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let space = namespace
        do {
            let value = try await call(URL(string: "https://plex.tv/api/v2/pins")!, method: "POST", body: Data("strong=true".utf8)) as? [String: Any]
            guard let pin = value?["id"] as? Int, let code = value?["code"] as? String else { throw APIClientError.invalidResponse }
            var components = URLComponents(string: "https://app.plex.tv/auth")!
            var fragment = URLComponents(); fragment.queryItems = [URLQueryItem(name: "clientID", value: clientID), URLQueryItem(name: "code", value: code), URLQueryItem(name: "context[device][product]", value: "RJ Love")]
            components.percentEncodedFragment = "?" + (fragment.percentEncodedQuery ?? "")
            authURL = components.url
            pinTask?.cancel()
            pinTask = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<150 {
                    do {
                        try await Task.sleep(for: .seconds(2)); try Task.checkCancellation()
                        guard self.namespace == space else { return }
                        let result = try await self.call(URL(string: "https://plex.tv/api/v2/pins/\(pin)")!) as? [String: Any]
                        if let token = result?["authToken"] as? String, !token.isEmpty {
                            guard self.namespace == space else { return }
                            try KeychainStore.set(token, for: space + ".plex.token")
                            self.token = token; self.authenticated = true; self.authURL = nil
                            await self.loadServers(); return
                        }
                    } catch is CancellationError { return }
                    catch { self.error = error.localizedDescription; return }
                }
                self.error = "Die Plex-Anmeldung ist abgelaufen. Bitte erneut verbinden."; self.authURL = nil
            }
        } catch { self.error = error.localizedDescription }
    }
    func loadServers() async {
        guard let token else { return }
        let space = namespace; busy = true; defer { busy = false }
        do {
            let resources = try await call(URL(string: "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1")!, token: token) as? [[String: Any]] ?? []
            guard namespace == space else { return }
            servers = resources.compactMap { item in
                guard (item["provides"] as? String)?.split(separator: ",").contains("server") == true, let id = item["clientIdentifier"] as? String else { return nil }
                let connections = (item["connections"] as? [[String: Any]] ?? []).compactMap { c -> PlexConnection? in
                    guard let uri = c["uri"] as? String, let url = URL(string: uri), ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil else { return nil }
                    return PlexConnection(uri: uri, local: (c["local"] as? Bool) == true || (c["local"] as? Int) == 1)
                }.sorted { a, b in
                    let score: (PlexConnection) -> Int = { ($0.uri.hasPrefix("https:") ? 2 : 0) + ($0.local ? 1 : 0) }
                    return score(a) > score(b)
                }
                return PlexServer(id: id, name: item["name"] as? String ?? "Plex", token: item["accessToken"] as? String ?? token, connections: connections)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func select(_ server: PlexServer) async {
        busy = true; defer { busy = false }
        let space = namespace
        for candidate in server.connections {
            do {
                _ = try await call(URL(string: candidate.uri + "/identity")!, token: server.token)
                guard namespace == space else { return }
                self.server = server; connection = candidate.uri
                await browse("/library/sections"); return
            } catch { continue }
        }
        error = "Keine Plex-Verbindung erreichbar. Im Heimnetz anmelden oder Plex-Fernzugriff prüfen."
    }
    func browse(_ path: String, more: Bool = false, query: String? = nil) async {
        guard let base = connection, let server else { return }
        guard path.hasPrefix("/library/") || path == "/hubs/search" else { return }
        busy = true; defer { busy = false }
        let next = more ? offset : 0
        do {
            var url = URLComponents(string: base + path)!
            url.queryItems = [URLQueryItem(name: "X-Plex-Container-Start", value: String(next)), URLQueryItem(name: "X-Plex-Container-Size", value: "60")]
            if let query { url.queryItems?.append(URLQueryItem(name: "query", value: query)) }
            let value = try await call(url.url!, token: server.token) as? [String: Any]
            guard self.server?.id == server.id else { return }
            let container = value?["MediaContainer"] as? [String: Any] ?? [:]
            var objects = (container["Directory"] as? [[String: Any]] ?? []) + (container["Metadata"] as? [[String: Any]] ?? [])
            for hub in container["Hub"] as? [[String: Any]] ?? [] { objects += hub["Metadata"] as? [[String: Any]] ?? [] }
            if path == "/library/sections" { objects = objects.map { v in var c = v; c["type"] = "directory"; c["key"] = "/library/sections/\(v["key"] ?? "")/all"; return c } }
            let found = objects.compactMap(PlexEntry.init)
            entries = more ? entries + found.filter { item in !entries.contains { $0.id == item.id } } : found
            self.path = path; offset = next + found.count
            hasMore = query == nil && offset < (container["totalSize"] as? Int ?? offset)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func media(_ entry: PlexEntry) async throws -> URL {
        guard let base = connection, let server else { throw APIClientError.invalidResponse }
        var item = entry
        if item.part == nil {
            let value = try await call(URL(string: base + "/library/metadata/" + item.id)!, token: server.token) as? [String: Any]
            let c = value?["MediaContainer"] as? [String: Any]
            guard let first = (c?["Metadata"] as? [[String: Any]])?.first, let full = PlexEntry(first) else { throw APIClientError.invalidResponse }
            item = full
        }
        guard let path = item.part, path.hasPrefix("/library/parts/"), !path.contains("?"), !path.contains("..") else { throw APIClientError.transport("Dieses Plex-Medium ist nicht direkt abspielbar.") }
        var components = URLComponents(string: base + path)!
        // AVPlayer and the AirPlay receiver need the file-scoped URL. Never share this URL with the partner.
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: server.token)]
        return components.url!
    }
    func shareBody() throws -> [String: Any] {
        guard let token, let server, let connection else { throw APIClientError.invalidResponse }
        return ["token": token, "machine_id": server.id, "connection": connection, "seconds": 14400]
    }
}
