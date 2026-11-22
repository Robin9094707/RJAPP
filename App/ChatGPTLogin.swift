import AuthenticationServices
import CryptoKit
import Foundation
import Network
import UIKit

/// "Mit ChatGPT anmelden": OAuth with PKCE on OpenAI's own sign-in page.
/// Password and two-factor codes are only ever typed on OpenAI's page, never in this app.
/// OpenAI returns to a tiny local server on 127.0.0.1, which only lives during the sign-in.
@MainActor
final class ChatGPTLogin: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var succeeded = false

    private var listener: NWListener?
    private var session: ASWebAuthenticationSession?
    private var verifier = ""
    private var state = ""
    private var nonce = ""
    private var redirectURI = ""
    private var requestedClientID = ""
    private var finished = false

    func start() {
        guard !busy else { return }
        busy = true
        succeeded = false
        finished = false
        status = "Anmeldung wird vorbereitet …"
        verifier = Self.randomURLSafe(48)
        state = Self.randomURLSafe(24)
        nonce = Self.randomURLSafe(24)
        startListener(ports: Array(1455...1462))
    }

    func cancel() {
        guard busy else { return }
        session?.cancel()
        fail("Anmeldung abgebrochen.")
    }

    // MARK: Local callback server

    private func startListener(ports: [UInt16]) {
        guard let port = ports.first, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            fail("Kein freier lokaler Port für die Anmeldung gefunden. Bitte die App kurz schließen und erneut versuchen.")
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        guard let candidate = try? NWListener(using: parameters) else {
            startListener(ports: Array(ports.dropFirst()))
            return
        }
        listener = candidate
        candidate.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.handle(connection) }
        }
        candidate.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in
                guard let self, self.listener === candidate else { return }
                switch update {
                case .ready:
                    self.redirectURI = "http://127.0.0.1:\(port)\(ChatGPTAuth.callbackPath)"
                    self.openBrowser()
                case .failed:
                    candidate.cancel()
                    self.listener = nil
                    self.startListener(ports: Array(ports.dropFirst()))
                default:
                    break
                }
            }
        }
        candidate.start(queue: .main)
    }

    private func openBrowser() {
        let existing = ChatGPTAuth.issuedClientID
        requestedClientID = existing ?? "dynamic_agent_client"
        var items = [
            URLQueryItem(name: "client_id", value: requestedClientID),
            URLQueryItem(name: "ext_agent_host_id", value: ChatGPTAuth.hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ChatGPTAuth.scope),
            URLQueryItem(name: "resource", value: ChatGPTAuth.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if existing == nil { items.append(URLQueryItem(name: "agent_name_hint", value: ChatGPTAuth.appName)) }
        guard var components = URLComponents(string: ChatGPTAuth.authorizeURL) else { fail("Anmelde-Adresse ungültig."); return }
        components.queryItems = items
        // "+" must arrive as a plus sign, not as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { fail("Anmelde-Adresse ungültig."); return }

        status = "Melde dich auf der Seite von OpenAI an …"
        // The custom scheme is never called: the code arrives through 127.0.0.1.
        let web = ASWebAuthenticationSession(url: url, callback: .customScheme("rjlove-auth")) { [weak self] _, error in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                if let issue = error as? ASWebAuthenticationSessionError, issue.code == .canceledLogin {
                    self.fail("Anmeldung abgebrochen.")
                } else {
                    self.fail(error?.localizedDescription ?? "Anmeldung beendet.")
                }
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = false
        session = web
        if !web.start() { fail("Das Anmeldefenster konnte nicht geöffnet werden.") }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { () -> ASPresentationAnchor in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first { return window }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let firstLine = text.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2, let components = URLComponents(string: "http://127.0.0.1" + parts[1]), components.path == ChatGPTAuth.callbackPath else {
                    self.respond(connection, status: "404 Not Found", html: "")
                    return
                }
                let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
                self.callback(query, connection: connection)
            }
        }
    }

    private func callback(_ query: [String: String], connection: NWConnection) {
        guard !finished else { respond(connection, status: "200 OK", html: Self.page("Bereits erledigt", "Du kannst dieses Fenster schließen.")); return }
        guard query["state"] == state else {
            respond(connection, status: "400 Bad Request", html: Self.page("Fehler", "Ungültige Anfrage."))
            return
        }
        if let error = query["error"] {
            respond(connection, status: "200 OK", html: Self.page("Abgebrochen", "Die Anmeldung wurde nicht abgeschlossen."))
            fail(error == "access_denied" ? "Zustimmung abgelehnt. Ohne sie kann das ChatGPT-Abo nicht genutzt werden." : "Anmeldefehler: \(error) \(query["error_description"] ?? "")")
            return
        }
        guard let code = query["code"], !code.isEmpty else {
            respond(connection, status: "400 Bad Request", html: Self.page("Fehler", "Kein Anmelde-Code erhalten."))
            return
        }
        // On the first sign-in OpenAI issues this installation's own client ID (oaiapp_…).
        var clientID = requestedClientID
        if let issued = query["client_id"], !issued.isEmpty, issued != "dynamic_agent_client" {
            if let existing = ChatGPTAuth.issuedClientID, existing != issued {
                respond(connection, status: "400 Bad Request", html: Self.page("Fehler", "Unerwartete Client-ID."))
                fail("Unerwartete Client-ID bei der Anmeldung.")
                return
            }
            clientID = issued
        }
        guard clientID != "dynamic_agent_client" else {
            respond(connection, status: "200 OK", html: Self.page("Fehler", "Registrierung unvollständig."))
            fail("Registrierung bei OpenAI unvollständig (keine Client-ID erhalten).")
            return
        }
        finished = true
        respond(connection, status: "200 OK", html: Self.page("Angemeldet ✓", "Zurück zu RJ Love …"))
        status = "Zugang wird eingerichtet …"
        let verifier = self.verifier, redirect = self.redirectURI, nonce = self.nonce
        Task { @MainActor in
            do {
                let value = try await ChatGPTAuth.exchange(code: code, verifier: verifier, redirectURI: redirect, clientID: clientID, nonce: nonce)
                ChatGPTAuth.issuedClientID = clientID
                ChatGPTAuth.save(value)
                self.session?.cancel()
                self.session = nil
                self.stopListener()
                guard value.planUsageAllowed else { self.fail(ChatGPTAuthError.planUsageMissing.localizedDescription); return }
                self.status = "Modelle werden geladen …"
                await AICompanion.shared.didSignIn(value)
                self.busy = false
                self.succeeded = true
                self.status = "Verbunden ✓ RJ Love nutzt jetzt dein ChatGPT-Abo."
                Haptics.success()
            } catch {
                self.session?.cancel()
                self.fail(error.localizedDescription)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func fail(_ message: String) {
        stopListener()
        session = nil
        busy = false
        succeeded = false
        status = message
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    // MARK: PKCE

    static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func page(_ title: String, _ text: String) -> String {
        """
        <!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>body{font-family:-apple-system,sans-serif;background:#120f1f;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}h1{font-size:30px;font-weight:600}p{opacity:.75}</style></head>
        <body><div><h1>\(title)</h1><p>\(text)</p></div></body></html>
        """
    }
}
