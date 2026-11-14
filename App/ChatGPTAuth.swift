import Foundation

/// "Mit ChatGPT anmelden": tokens for the user's own ChatGPT plan, stored per iPhone in the keychain.
/// Each partner signs in on their own phone; both may use the same ChatGPT account.
struct ChatGPTSession: Codable, Sendable {
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var scope: String
    var email: String
    var subject: String

    var planUsageAllowed: Bool { scope.split(separator: " ").contains("chatgpt.tokens.use.direct") }
}

enum ChatGPTAuthError: LocalizedError {
    case notSignedIn
    case planUsageMissing
    case signInAgain(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Nicht mit ChatGPT angemeldet. Öffne Profil → KI & ChatGPT und tippe auf „Mit ChatGPT anmelden“."
        case .planUsageMissing: return "Die Berechtigung „ChatGPT-Abo nutzen“ wurde nicht erteilt. Bitte erneut anmelden und zustimmen."
        case .signInAgain(let code): return "Die ChatGPT-Anmeldung ist abgelaufen. Bitte unter KI & ChatGPT neu anmelden. (\(code))"
        case .server(let message): return message
        }
    }
}

enum AIRequestError: LocalizedError, Equatable {
    case network(String)
    case http(Int, String, code: String = "", param: String = "")
    case empty

    var errorDescription: String? {
        switch self {
        case .network(let message): return "Keine Verbindung zu ChatGPT: \(message)"
        case .http(_, let message, _, _): return message
        case .empty: return "ChatGPT hat keine Antwort geliefert. Bitte noch einmal versuchen."
        }
    }
    var isModelError: Bool {
        guard case .http(let status, let message, let code, let param) = self else { return false }
        if code.contains("model") || param == "model" { return true }
        return (status == 400 || status == 404) && message.lowercased().contains("model")
    }
    var isReasoningError: Bool {
        guard case .http(let status, let message, _, let param) = self else { return false }
        return status == 400 && (param.hasPrefix("reasoning") || message.lowercased().contains("reasoning"))
    }
}

enum ChatGPTAuth {
    static let authorizeURL = "https://auth.openai.com/api/accounts/authorize"
    static let tokenURL = "https://auth.openai.com/api/accounts/oauth/token"
    static let discoveryURL = "https://auth.openai.com/.well-known/openid-configuration"
    static let resource = "https://api.openai.com/v1"
    static let apiBase = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let callbackPath = "/auth/callback"
    static let appName = "RJ Love"
    static let defaultModel = "gpt-6.1-sol"

    private static let sessionKey = "chatgpt.session.v1"

    // MARK: Stable values

    /// Stable identifier of this installation (requested by the service as "host"). Not a secret.
    static var hostID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "rjlove.ai.host-id"), !id.isEmpty { return id }
        let id = "urn:uuid:" + UUID().uuidString.lowercased()
        defaults.set(id, forKey: "rjlove.ai.host-id")
        return id
    }

    /// Client ID issued by OpenAI on the first sign-in (oaiapp_…). Reused for every later sign-in.
    static var issuedClientID: String? {
        get { UserDefaults.standard.string(forKey: "rjlove.ai.client-id") }
        set { UserDefaults.standard.set(newValue, forKey: "rjlove.ai.client-id") }
    }

    // MARK: Keychain

    static func load() -> ChatGPTSession? {
        guard let raw = KeychainStore.get(sessionKey), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatGPTSession.self, from: data)
    }

    static func save(_ session: ChatGPTSession) {
        guard let data = try? JSONEncoder().encode(session), let raw = String(data: data, encoding: .utf8) else { return }
        do { try KeychainStore.set(raw, for: sessionKey) }
        catch {
            let message = error.localizedDescription
            Task { @MainActor in DebugLogger.shared.log("ChatGPT-Sitzung nicht gespeichert: \(message)", category: "KI") }
        }
    }

    static func clear() { KeychainStore.delete(sessionKey) }

    // MARK: Token exchange

    static func exchange(code: String, verifier: String, redirectURI: String, clientID: String, nonce: String) async throws -> ChatGPTSession {
        let json = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": resource,
        ])
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw ChatGPTAuthError.server("Unerwartete Antwort beim Anmelden.")
        }
        let idToken = json["id_token"] as? String ?? ""
        let claims = decodeJWT(idToken)
        if let value = claims["nonce"] as? String, value != nonce {
            throw ChatGPTAuthError.server("Sicherheitsprüfung fehlgeschlagen (nonce).")
        }
        if let exp = claims["exp"] as? Double, Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(-300) {
            throw ChatGPTAuthError.server("Das Anmelde-Token ist bereits abgelaufen. Bitte Uhrzeit des iPhones prüfen.")
        }
        return ChatGPTSession(
            clientID: clientID,
            accessToken: access,
            refreshToken: refresh,
            idToken: idToken,
            expiresAt: Date().addingTimeInterval(number(json["expires_in"]) ?? 3600),
            scope: json["scope"] as? String ?? scope,
            email: claims["email"] as? String ?? "",
            subject: claims["sub"] as? String ?? ""
        )
    }

    /// A valid access token; refreshed automatically shortly before it expires (tokens last about an hour).
    static func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        try await ChatGPTTokenBroker.shared.accessToken(forceRefresh: forceRefresh)
    }

    static let fatalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]

    static func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncode(fields).data(using: .utf8)
        let pair: (Data, URLResponse)
        do { pair = try await URLSession.shared.data(for: request) }
        catch { throw AIRequestError.network(error.localizedDescription) }
        let (data, response) = pair
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let nested = json["error"] as? [String: Any]
            let code = (json["error"] as? String) ?? (nested?["code"] as? String) ?? ""
            let detail = (json["error_description"] as? String) ?? (nested?["message"] as? String) ?? (json["detail"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            if fatalRefreshErrors.contains(code) { throw ChatGPTAuthError.signInAgain(code) }
            throw ChatGPTAuthError.server("Anmeldefehler \(status): \(code.isEmpty ? detail : code + " – " + detail)")
        }
        return json
    }

    // MARK: Sign out

    static func signOut() async {
        let session = load()
        clear()
        guard let session else { return }
        var endpoint = "https://auth.openai.com/oauth/revoke"
        if let (data, _) = try? await URLSession.shared.data(from: URL(string: discoveryURL)!),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json["revocation_endpoint"] as? String {
            endpoint = value
        }
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(["token": session.refreshToken, "token_type_hint": "refresh_token", "client_id": session.clientID]).data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Models

    /// Models unlocked by the plan, as (slug, display name) in server order.
    static func fetchModels() async throws -> [AIModelOption] {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: apiBase + "/models")!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatGPTAuthError.server("Modelle konnten nicht geladen werden (\(status)).")
        }
        let list = (json["models"] as? [[String: Any]]) ?? (json["data"] as? [[String: Any]]) ?? []
        return list.compactMap { item in
            guard let slug = (item["slug"] as? String) ?? (item["id"] as? String) else { return nil }
            if let visibility = item["visibility"] as? String, visibility != "list" { return nil }
            return AIModelOption(id: slug, name: (item["display_name"] as? String) ?? slug)
        }
    }

    // MARK: Friendly errors

    static func message(forCode code: String, fallback: String) -> String {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            return "Dein ChatGPT-Nutzungslimit ist erreicht. Später erneut versuchen (ChatGPT → Einstellungen → Nutzung)."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return "Der ChatGPT-Abo-Zugang ist gerade nicht verfügbar. Bitte gleich nochmal versuchen."
        case "subscription_sharing_user_not_eligible":
            return "Für dieses Konto ist die Abo-Nutzung in anderen Apps nicht freigeschaltet (Plan oder Region)."
        case "subscription_sharing_unsupported_capability":
            return "Diese Funktion wird über das ChatGPT-Abo nicht unterstützt. (\(fallback))"
        case "subscription_sharing_invalid_user":
            return "Die ChatGPT-Anmeldung ist ungültig. Bitte unter KI & ChatGPT neu anmelden."
        default:
            return fallback
        }
    }

    // MARK: Helpers

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)" }.joined(separator: "&")
    }

    /// Reads a JWT payload without verifying the signature (display and nonce check only).
    static func decodeJWT(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var base = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let data = Data(base64Encoded: base), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

/// Refresh tokens are single-use: only one refresh may run at a time.
actor ChatGPTTokenBroker {
    static let shared = ChatGPTTokenBroker()
    private var refreshTask: Task<ChatGPTSession, Error>?

    func accessToken(forceRefresh: Bool) async throws -> String {
        guard let session = ChatGPTAuth.load() else { throw ChatGPTAuthError.notSignedIn }
        guard session.planUsageAllowed else { throw ChatGPTAuthError.planUsageMissing }
        if !forceRefresh, session.expiresAt.timeIntervalSinceNow > 120 { return session.accessToken }
        return try await refreshed(stale: session.accessToken).accessToken
    }

    private func refreshed(stale: String) async throws -> ChatGPTSession {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<ChatGPTSession, Error> {
            guard let current = ChatGPTAuth.load() else { throw ChatGPTAuthError.notSignedIn }
            if current.accessToken != stale, current.expiresAt.timeIntervalSinceNow > 120 { return current }
            let json = try await ChatGPTAuth.tokenRequest([
                "grant_type": "refresh_token",
                "client_id": current.clientID,
                "refresh_token": current.refreshToken,
                "resource": ChatGPTAuth.resource,
            ])
            guard let access = json["access_token"] as? String else { throw ChatGPTAuthError.server("Token-Erneuerung fehlgeschlagen.") }
            var next = current
            next.accessToken = access
            if let value = json["refresh_token"] as? String, !value.isEmpty { next.refreshToken = value }
            if let value = json["id_token"] as? String, !value.isEmpty { next.idToken = value }
            if let value = json["scope"] as? String, !value.isEmpty { next.scope = value }
            next.expiresAt = Date().addingTimeInterval(ChatGPTAuth.number(json["expires_in"]) ?? 3600)
            ChatGPTAuth.save(next)
            return next
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

struct AIModelOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}
