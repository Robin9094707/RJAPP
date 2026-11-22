import Foundation

/// One message for the Responses API. System text goes into `instructions`.
struct AIPromptMessage: Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: String
}

/// A web page ChatGPT cited while searching the internet.
struct AISource: Codable, Hashable, Identifiable, Sendable {
    var title: String
    var url: String
    var id: String { url }
    var host: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url }
}

struct AIAnswer: Sendable {
    var text: String
    var sources: [AISource] = []
    var searched = false
}

/// Requests over the user's ChatGPT plan: always `store: false` and streaming, as OpenAI requires.
enum ChatGPTClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 400
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static let webBlockedKey = "rjlove.ai.web-blocked-until"

    /// Internet search is only offered while the plan has not rejected it (checked again after a day).
    static var webSearchBlocked: Bool {
        (UserDefaults.standard.object(forKey: webBlockedKey) as? Date ?? .distantPast) > .now
    }
    static func resetWebSearchCheck() { UserDefaults.standard.removeObject(forKey: webBlockedKey) }

    /// Streams an answer. `onPartial` receives the whole text so far (throttled) on the main actor,
    /// `onStatus` short progress notes such as "Sucht im Internet …".
    /// Tries the chosen model first and falls back to other unlocked models if it is unavailable.
    static func respond(
        instructions: String,
        messages: [AIPromptMessage],
        model preferred: String,
        alternatives: [String],
        effort: String?,
        webSearch: Bool = false,
        onStatus: (@MainActor @Sendable (String) -> Void)? = nil,
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> AIAnswer {
        var candidates: [String] = []
        for model in [preferred] + alternatives + [ChatGPTAuth.defaultModel] where !model.isEmpty && !candidates.contains(model) {
            candidates.append(model)
        }
        var useWeb = webSearch && !webSearchBlocked
        var useEffort = effort
        var lastError: Error = AIRequestError.empty
        var index = 0
        let models = Array(candidates.prefix(4))
        while index < models.count {
            let model = models[index]
            do {
                let answer = try await request(instructions: instructions, messages: messages, model: model, effort: useEffort, web: useWeb, onStatus: onStatus, onPartial: onPartial)
                guard !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIRequestError.empty }
                return answer
            } catch let error as AIRequestError where useWeb && error.isToolError {
                // The plan does not allow web search (or not for this model): remember it and answer without.
                UserDefaults.standard.set(Date.now.addingTimeInterval(24 * 3600), forKey: webBlockedKey)
                useWeb = false
                if let onStatus { await onStatus("Internetsuche ist mit deinem Abo gerade nicht verfügbar. Antwort ohne Suche …") }
            } catch let error as AIRequestError where error.isReasoningError && useEffort != nil {
                useEffort = nil
            } catch let error as AIRequestError where error.isModelError {
                lastError = error
                index += 1
            }
        }
        throw lastError
    }

    private static func request(
        instructions: String,
        messages: [AIPromptMessage],
        model: String,
        effort: String?,
        web: Bool,
        onStatus: (@MainActor @Sendable (String) -> Void)?,
        onPartial: (@MainActor @Sendable (String) -> Void)?,
        retried: Bool = false
    ) async throws -> AIAnswer {
        let token = try await ChatGPTAuth.validAccessToken(forceRefresh: retried)
        var body: [String: Any] = [
            "model": model,
            "input": messages.map { ["type": "message", "role": $0.role.rawValue, "content": $0.content] },
            "store": false,
            "stream": true,
        ]
        if !instructions.isEmpty { body["instructions"] = instructions }
        if let effort, !effort.isEmpty, effort != "auto" { body["reasoning"] = ["effort": effort] }
        if web { body["tools"] = [["type": "web_search"]] }
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
                return try await self.request(instructions: instructions, messages: messages, model: model, effort: effort, web: web, onStatus: onStatus, onPartial: onPartial, retried: true)
            }
            throw failure(status: http.statusCode, data: data)
        }

        var answer = AIAnswer(text: "")
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
                    answer.text += piece
                    if let onPartial, Date().timeIntervalSince(lastEmit) > 0.06 {
                        lastEmit = Date()
                        let snapshot = answer.text
                        await onPartial(snapshot)
                    }
                }
            case "response.output_text.annotation.added":
                if let annotation = json["annotation"] as? [String: Any] { collect(annotation, into: &answer) }
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                answer.searched = true
                if let onStatus { await onStatus("Sucht im Internet …") }
            case "response.web_search_call.completed":
                if let onStatus { await onStatus("Quellen gefunden, schreibt …") }
            case "response.completed":
                completed = true
                if let output = (json["response"] as? [String: Any])?["output"] as? [[String: Any]] {
                    for item in output {
                        if (item["type"] as? String) == "web_search_call" { answer.searched = true }
                        for content in item["content"] as? [[String: Any]] ?? [] {
                            for annotation in content["annotations"] as? [[String: Any]] ?? [] { collect(annotation, into: &answer) }
                        }
                    }
                }
            case "response.incomplete":
                completed = !answer.text.isEmpty
            case "response.failed", "error":
                let error = ((json["response"] as? [String: Any])?["error"] as? [String: Any]) ?? (json["error"] as? [String: Any]) ?? json
                let code = error["code"] as? String ?? ""
                let message = error["message"] as? String ?? "Die Anfrage ist fehlgeschlagen."
                let param = error["param"] as? String ?? ""
                throw AIRequestError.http(code == "subscription_sharing_usage_limit_exceeded" ? 429 : 400, ChatGPTAuth.message(forCode: code, fallback: message), code: code, param: param)
            default:
                continue
            }
            if completed { break }
        }
        if !completed && answer.text.isEmpty { throw AIRequestError.network("Die Verbindung zu ChatGPT wurde unterbrochen.") }
        if let onPartial { let snapshot = answer.text; await onPartial(snapshot) }
        answer.text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return answer
    }

    private static func collect(_ annotation: [String: Any], into answer: inout AIAnswer) {
        guard (annotation["type"] as? String) == "url_citation", let url = annotation["url"] as? String, !answer.sources.contains(where: { $0.url == url }) else { return }
        let title = (annotation["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (URL(string: url)?.host() ?? url)
        answer.sources.append(AISource(title: title, url: url))
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
