import Foundation

/// One message for the Responses API. System text goes into `instructions`.
struct AIPromptMessage: Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: String
}

/// Requests over the user's ChatGPT plan: always `store: false` and streaming, as OpenAI requires.
enum ChatGPTClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Streams an answer. `onPartial` receives the whole text so far (throttled) on the main actor.
    /// Tries the chosen model first and falls back to other unlocked models if it is unavailable.
    static func respond(
        instructions: String,
        messages: [AIPromptMessage],
        model preferred: String,
        alternatives: [String],
        effort: String?,
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        var candidates: [String] = []
        for model in [preferred] + alternatives + [ChatGPTAuth.defaultModel] where !model.isEmpty && !candidates.contains(model) {
            candidates.append(model)
        }
        var lastError: Error = AIRequestError.empty
        for model in candidates.prefix(4) {
            do {
                let text = try await request(instructions: instructions, messages: messages, model: model, effort: effort, onPartial: onPartial)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.empty }
                return text
            } catch let error as AIRequestError where error.isReasoningError && effort != nil {
                return try await request(instructions: instructions, messages: messages, model: model, effort: nil, onPartial: onPartial)
            } catch let error as AIRequestError where error.isModelError {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func request(
        instructions: String,
        messages: [AIPromptMessage],
        model: String,
        effort: String?,
        onPartial: (@MainActor @Sendable (String) -> Void)?,
        retried: Bool = false
    ) async throws -> String {
        let token = try await ChatGPTAuth.validAccessToken(forceRefresh: retried)
        var body: [String: Any] = [
            "model": model,
            "input": messages.map { ["type": "message", "role": $0.role.rawValue, "content": $0.content] },
            "store": false,
            "stream": true,
        ]
        if !instructions.isEmpty { body["instructions"] = instructions }
        if let effort, !effort.isEmpty, effort != "auto" { body["reasoning"] = ["effort": effort] }
        var request = URLRequest(url: URL(string: ChatGPTAuth.apiBase + "/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let pair: (URLSession.AsyncBytes, URLResponse)
        do { pair = try await session.bytes(for: request) }
        catch { throw AIRequestError.network(error.localizedDescription) }
        let (bytes, response) = pair
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 64_000 { break } }
            if http.statusCode == 401, !retried {
                return try await self.request(instructions: instructions, messages: messages, model: model, effort: effort, onPartial: onPartial, retried: true)
            }
            throw failure(status: http.statusCode, data: data)
        }

        var text = ""
        var lastEmit = Date.distantPast
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                if let piece = json["delta"] as? String {
                    text += piece
                    if let onPartial, Date().timeIntervalSince(lastEmit) > 0.06 {
                        lastEmit = Date()
                        let snapshot = text
                        await onPartial(snapshot)
                    }
                }
            case "response.completed":
                completed = true
            case "response.incomplete":
                completed = !text.isEmpty
            case "response.failed", "error":
                let error = ((json["response"] as? [String: Any])?["error"] as? [String: Any]) ?? (json["error"] as? [String: Any]) ?? json
                let code = error["code"] as? String ?? ""
                let message = error["message"] as? String ?? "Die Anfrage ist fehlgeschlagen."
                throw AIRequestError.http(code == "subscription_sharing_usage_limit_exceeded" ? 429 : 400, ChatGPTAuth.message(forCode: code, fallback: message), code: code)
            default:
                continue
            }
            if completed { break }
        }
        if !completed && text.isEmpty { throw AIRequestError.network("Die Verbindung zu ChatGPT wurde unterbrochen.") }
        if let onPartial { let snapshot = text; await onPartial(snapshot) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func failure(status: Int, data: Data) -> Error {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let error = json["error"] as? [String: Any]
        let code = error?["code"] as? String ?? ""
        let param = error?["param"] as? String ?? ""
        var message = (error?["message"] as? String) ?? (json["detail"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
        if !param.isEmpty { message += " (\(param))" }
        if status == 401 { return ChatGPTAuthError.signInAgain(code.isEmpty ? "401" : code) }
        if status == 429 && code.isEmpty { message = "ChatGPT ist gerade ausgelastet oder dein Limit ist erreicht. Bitte kurz warten." }
        return AIRequestError.http(status, ChatGPTAuth.message(forCode: code, fallback: message), code: code, param: param)
    }
}
