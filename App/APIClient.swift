import Foundation

struct ServerProfile: Codable, Equatable {
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

final class APIClient: @unchecked Sendable {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var _baseURL: URL?
    private var _token: String?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    func configure(baseURL: URL, token: String?) {
        lock.lock()
        _baseURL = baseURL
        _token = token
        lock.unlock()
    }

    private func snapshot() throws -> (URL, String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let baseURL = _baseURL else { throw APIClientError.invalidServerURL }
        return (baseURL, _token)
    }

    private func request(path: String, method: String, body: Data? = nil, authenticated: Bool = true) throws -> URLRequest {
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
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                throw APIClientError.server(
                    status: http.statusCode,
                    message: envelope?.message ?? "Serverfehler (HTTP \(http.statusCode))."
                )
            }
            let decodableData = data.isEmpty ? Data("{}".utf8) : data
            return try decoder.decode(T.self, from: decodableData)
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
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

    func postPresence(_ payload: PresencePayload) async throws {
        let data = try encoder.encode(payload)
        _ = try await execute(try request(path: "/v1/presence", method: "POST", body: data), as: UpdatedAtResponse.self)
    }

    func sendThought() async throws -> ThoughtResponse {
        try await execute(try request(path: "/v1/thoughts", method: "POST", body: Data("{}".utf8)), as: ThoughtResponse.self)
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
            enum CodingKeys: String, CodingKey {
                case environment
                case deviceToken = "device_token"
                case deviceID = "device_id"
            }
        }
        _ = try await execute(
            try request(path: "/v1/devices", method: "POST", body: encoder.encode(Body(deviceToken: token, deviceID: deviceID, environment: environment))),
            as: EmptyResponse.self
        )
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
