import Foundation

struct ServerProfile: Codable, Equatable, Sendable {
    var baseURL: String
    var username: String
}

enum APIClientError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case server(status: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Die Serveradresse ist ungültig. Beispiel: https://liebe.example.de oder http://192.168.1.20:8765"
        case .invalidResponse:
            "Der Server hat eine ungültige Antwort gesendet."
        case .server(_, let message):
            message
        case .transport(let message):
            "Server nicht erreichbar: \(message)"
        }
    }
}

private struct CompatibilityErrorEnvelope: Decodable {
    let message: String
    let compatibility: ServerCompatibility?
}

final class APIClient: @unchecked Sendable {
    let session: URLSession
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    private let lock = NSLock()
    private var _baseURL: URL?
    private var _token: String?

    init(background: Bool = false) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = background ? 8 : 20
        configuration.timeoutIntervalForResource = background ? 18 : 45
        configuration.waitsForConnectivity = !background
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    func configure(baseURL: URL, token: String?) {
        lock.lock()
        _baseURL = baseURL
        _token = token
        lock.unlock()
    }

    func sessionCopy() -> APIClient {
        let copy = APIClient()
        if let (url, token) = try? snapshot() { copy.configure(baseURL: url, token: token) }
        return copy
    }
    private func snapshot() throws -> (URL, String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let baseURL = _baseURL else { throw APIClientError.invalidServerURL }
        return (baseURL, _token)
    }

    func request(path: String, method: String, body: Data? = nil, authenticated: Bool = true) throws -> URLRequest {
        let (base, token) = try snapshot()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidServerURL
        }
        let normalizedBasePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = normalizedBasePath + (path.hasPrefix("/") ? path : "/\(path)")
        guard let url = components.url else { throw APIClientError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RJVersion.app, forHTTPHeaderField: "X-RJ-App-Version")
        request.setValue(String(RJVersion.protocolVersion), forHTTPHeaderField: "X-RJ-Protocol")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 426 {
                    let value = try? decoder.decode(CompatibilityErrorEnvelope.self, from: data)
                    let issue = value?.compatibility.flatMap { RJVersion.requirement($0) } ?? UpdateRequirement(target: "app", message: value?.message ?? "App und Python-Server gemeinsam aktualisieren.")
                    await MainActor.run { UpdateCoordinator.shared.requirement = issue }
                    throw issue
                }
                let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                throw APIClientError.server(
                    status: http.statusCode,
                    message: envelope?.message ?? "Serverfehler (HTTP \(http.statusCode))."
                )
            }
            let decodableData = data.isEmpty ? Data("{}".utf8) : data
            return try decoder.decode(T.self, from: decodableData)
        } catch let error as UpdateRequirement {
            throw error
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
    }

    func checkCompatibility() async throws {
        let info = try await execute(try request(path: "/health", method: "GET", authenticated: false), as: ServerCompatibility.self)
        if let issue = RJVersion.requirement(info) {
            await MainActor.run { UpdateCoordinator.shared.requirement = issue }
            throw issue
        }
        await MainActor.run { UpdateCoordinator.shared.requirement = nil }
    }
    func loadFartArchive() async throws -> [FartClip] {
        try await checkCompatibility()
        struct Page: Decodable {
            let clips: [FartClip]
            let hasMore: Bool
            let nextOffset: Int
            let before: String
            enum CodingKeys: String, CodingKey { case clips, before; case hasMore = "has_more", nextOffset = "next_offset" }
        }
        var all: [FartClip] = []
        var offset = 0
        var before: String?
        repeat {
            try Task.checkCancellation()
            // URLComponents query belongs in queryItems, not the encoded path.
            var req = try request(path: "/v1/farts", method: "GET")
            var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "offset", value: String(offset))]
            if let before { url.queryItems?.append(URLQueryItem(name: "before", value: before)) }
            req.url = url.url
            let page = try await execute(req, as: Page.self)
            all += page.clips
            if !page.hasMore { break }
            guard page.nextOffset > offset else { throw APIClientError.invalidResponse }
            offset = page.nextOffset; before = page.before
        } while true
        return all
    }
    func removeFartLocation(id: String) async throws -> FartClip {
        try await execute(try request(path: "/v1/farts/\(id)/location",method: "DELETE"), as: FartClip.self)
    }
    func automaticPushSetup() async throws {
        _ = try await execute(try request(path: "/v1/push/setup", method: "POST", body: Data("{}".utf8)), as: EmptyResponse.self)
    }

    func login(username: String, password: String, deviceID: String) async throws -> LoginResponse {
        struct Body: Encodable {
            let username: String
            let password: String
            let deviceID: String
            enum CodingKeys: String, CodingKey { case username, password; case deviceID = "device_id" }
        }
        let data = try encoder.encode(Body(username: username, password: password, deviceID: deviceID))
        return try await execute(try request(path: "/v1/auth/login", method: "POST", body: data, authenticated: false), as: LoginResponse.self)
    }

    func bootstrap() async throws -> BootstrapResponse {
        try await execute(try request(path: "/v1/bootstrap", method: "GET"), as: BootstrapResponse.self)
    }

    func backgroundSnapshot() async throws -> BackgroundSnapshot {
        try await execute(try request(path: "/v1/background", method: "GET"), as: BackgroundSnapshot.self)
    }
    func commandReceipt(id: String, status: String, reason: String) async throws {
        do {
            _ = try await execute(try request(path: "/v1/commands/\(id)/receipt", method: "POST", body: encoder.encode(["status": status, "reason": reason])), as: EmptyResponse.self)
        } catch let error as APIClientError {
            if case .server(let code, _) = error, code == 404, status == "scheduled" || status == "expired" { try await acknowledgeCommand(id: id) }
            else { throw error }
        }
    }
    func commandDeliveries() async throws -> [CommandDelivery] {
        struct Response: Decodable { let deliveries: [CommandDelivery] }
        return try await execute(try request(path: "/v1/commands/delivery", method: "GET"), as: Response.self).deliveries
    }
    func pushReadiness() async throws -> PushReadiness {
        try await execute(try request(path: "/v1/push/status", method: "GET"), as: PushReadiness.self)
    }
    func testPush() async throws {
        _ = try await execute(try request(path: "/v1/push/test", method: "POST", body: Data("{}".utf8)), as: EmptyResponse.self)
    }

    func postPresence(_ payload: PresencePayload) async throws {
        let data = try encoder.encode(payload)
        _ = try await execute(try request(path: "/v1/presence", method: "POST", body: data), as: UpdatedAtResponse.self)
    }

    func sendThought(id: String = UUID().uuidString, occurredAt: String? = nil) async throws -> ThoughtResponse {
        try await execute(try request(path: "/v1/thoughts", method: "POST", body: encoder.encode(["id":id,"occurred_at":occurredAt])), as: ThoughtResponse.self)
    }

    func upsertRecord(id: String = UUID().uuidString, kind: RecordKind, payload: RecordPayload) async throws -> SharedRecord {
        struct Body: Encodable { let id: String; let kind: RecordKind; let payload: RecordPayload }
        let data = try encoder.encode(Body(id: id, kind: kind, payload: payload))
        return try await execute(try request(path: "/v1/records", method: "POST", body: data), as: SharedRecord.self)
    }

    func deleteRecord(id: String) async throws {
        _ = try await execute(try request(path: "/v1/records/\(id)", method: "DELETE"), as: EmptyResponse.self)
    }

    func sendWake(targetID: String, message: String, dueAt: Date = .now.addingTimeInterval(2)) async throws -> CreatedCommandResponse {
        struct Body: Encodable {
            let targetID: String
            let kind: String
            let message: String
            let dueAt: String
            enum CodingKeys: String, CodingKey {
                case kind, message
                case targetID = "target_id"
                case dueAt = "due_at"
            }
        }
        let body = Body(targetID: targetID, kind: "wake", message: message, dueAt: dueAt.rjISO8601)
        return try await execute(
            try request(path: "/v1/commands", method: "POST", body: encoder.encode(body)),
            as: CreatedCommandResponse.self
        )
    }

    func acknowledgeCommand(id: String) async throws {
        _ = try await execute(
            try request(path: "/v1/commands/\(id)/ack", method: "POST", body: Data("{}".utf8)),
            as: EmptyResponse.self
        )
    }

    func acknowledgeEvent(id: String) async throws {
        _ = try await execute(
            try request(path: "/v1/events/\(id)/ack", method: "POST", body: Data("{}".utf8)),
            as: EmptyResponse.self
        )
    }

    func sendGeofenceEvent(id: String, name: String, event: String) async throws {
        struct Body: Encodable {
            let geofenceID: String
            let name: String
            let event: String
            enum CodingKeys: String, CodingKey { case name, event; case geofenceID = "geofence_id" }
        }
        _ = try await execute(
            try request(path: "/v1/geofence-events", method: "POST", body: encoder.encode(Body(geofenceID: id, name: name, event: event))),
            as: EmptyResponse.self
        )
    }

    func registerDevice(token: String, deviceID: String, environment: String) async throws {
        struct Body: Encodable {
            let deviceToken: String
            let deviceID: String
            let environment: String
            let bundleID: String
            let teamID: String?
            enum CodingKeys: String, CodingKey {
                case environment
                case bundleID = "bundle_id"
                case teamID = "team_id"
                case deviceToken = "device_token"
                case deviceID = "device_id"
            }
        }
        _ = try await execute(
            try request(path: "/v1/devices", method: "POST", body: encoder.encode(Body(deviceToken: token, deviceID: deviceID, environment: environment, bundleID: SigningProfile.current.bundleID, teamID: SigningProfile.current.teamID))),
            as: EmptyResponse.self
        )
    }

    func changeCredentials(currentPassword: String, username: String, password: String) async throws {
        let body = ["current_password": currentPassword, "username": username, "password": password]
        _ = try await execute(try request(path: "/v1/auth/credentials", method: "POST", body: encoder.encode(body)), as: EmptyResponse.self)
    }

    func publishNearbyToken(_ token: String) async throws {
        _ = try await execute(try request(path: "/v1/nearby", method: "POST", body: encoder.encode(["token": token])), as: EmptyResponse.self)
    }

    func partnerNearbyToken() async throws -> String? {
        struct Response: Decodable { let token: String? }
        return try await execute(try request(path: "/v1/nearby", method: "GET"), as: Response.self).token
    }

    func registerLiveActivity(id: String, token: String, environment: String) async throws {
        let body = ["activity_id": id, "token": token, "environment": environment]
        _ = try await execute(try request(path: "/v1/live-activities", method: "POST", body: encoder.encode(body)), as: EmptyResponse.self)
    }

    func uploadFart(_ body: FartUpload) async throws -> FartClip {
        try await checkCompatibility()
        return try await execute(try request(path: "/v1/farts", method: "POST", body: encoder.encode(body)), as: FartClip.self)
    }
    func editFart(_ body: FartUpload) async throws -> FartClip {
        try await checkCompatibility()
        return try await execute(try request(path: "/v1/farts/\(body.id)/edit", method: "POST", body: encoder.encode(body)), as: FartClip.self)
    }
    func rateFart(id: String, overall: Int, power: Int, style: Int, comment: String) async throws -> FartClip {
        struct Body: Encodable { let overall: Int; let power: Int; let style: Int; let comment: String }
        return try await execute(try request(path: "/v1/farts/\(id)/rating", method: "POST", body: encoder.encode(Body(overall: overall, power: power, style: style, comment: comment))), as: FartClip.self)
    }
    func reactToFart(id: String, emoji: String) async throws -> FartClip {
        try await execute(try request(path: "/v1/farts/\(id)/reaction", method: "POST", body: encoder.encode(["emoji": emoji])), as: FartClip.self)
    }
    func deleteFart(id: String) async throws {
        _ = try await execute(try request(path: "/v1/farts/\(id)", method: "DELETE"), as: EmptyResponse.self)
    }
    func fartAudio(id: String) async throws -> Data {
        var value = try request(path: "/v1/farts/\(id)/audio", method: "GET")
        value.setValue("audio/mp4", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: value)
        guard let response = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard response.statusCode == 200 else {
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(status: response.statusCode, message: envelope?.message ?? "Aufnahme konnte nicht geladen werden.")
        }
        guard data.count <= 4 * 1024 * 1024 else { throw APIClientError.invalidResponse }
        return data
    }


    func logout() async {
        guard let request = try? request(path: "/v1/auth/logout", method: "POST", body: Data("{}".utf8)) else { return }
        _ = try? await execute(request, as: EmptyResponse.self)
    }
}

private struct UpdatedAtResponse: Codable {
    let updatedAt: String
    enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" }
}
