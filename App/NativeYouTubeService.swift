import Foundation
import Observation
import WebKit
import YouTubeKit

/// YouTubeKit is pinned to a fixed revision. Account cookies never leave the device.
@MainActor @Observable final class NativeYouTubeService {
    static let shared = NativeYouTubeService()
    var results: [YouTubeResult] = []
    var busy = false
    var error: String?
    var signedIn = false
    var hasMore = false
    private let model = YouTubeModel()
    private var namespace = ""
    private var continuation: String?
    private var feed = false
    private var requestID = UUID()
    var dataStore: WKWebsiteDataStore = .nonPersistent()
    func configure(namespace: String) {
        guard self.namespace != namespace else { return }
        self.namespace = namespace; requestID = UUID(); results = []; model.cookies = ""; signedIn = false; continuation = nil; hasMore = false
        let key = "rjlove.youtube.webstore."+namespace
        let id = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        dataStore = WKWebsiteDataStore(forIdentifier: id)
    }
    func refreshCookies() async {
        let space = namespace
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard space == namespace else { return }
        let values = cookies.filter { $0.domain == ".youtube.com" || $0.domain == "youtube.com" || $0.domain == "m.youtube.com" || $0.domain == "www.youtube.com" }
        var unique: [String:String] = [:]
        for cookie in values { unique[cookie.name] = cookie.value }
        model.cookies = unique.map { $0.key+"="+$0.value }.joined(separator: "; ")
        signedIn = unique["SAPISID"] != nil || unique["__Secure-1PSID"] != nil
        model.alwaysUseCookies = signedIn
    }
    private func request<T: YouTubeResponse>(_ type: T.Type, data: [HeadersList.AddQueryInfo.ContentTypes:String]) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            model.sendRequest(responseType: type, data: data) { result in continuation.resume(with: result) }
        }
    }
    func search(_ query: String) async {
        guard !busy else { return }
        busy = true; let id = UUID(); requestID = id
        defer { if requestID == id { busy = false } }
        await refreshCookies()
        do {
            let page = try await request(SearchResponse.self,data: [.query:query])
            guard requestID == id else { return }
            model.visitorData = page.visitorData ?? model.visitorData
            results = map(page.results.compactMap { $0 as? YTVideo }); continuation = page.continuationToken; feed = false; hasMore = continuation != nil
            error = results.isEmpty ? "Keine Videos gefunden. Du kannst die Suche auch direkt in YouTube öffnen." : nil
        } catch { if requestID == id { self.error = "YouTube-Suche momentan nicht erreichbar. Bitte erneut versuchen oder YouTube direkt in der App öffnen." } }
    }
    func subscriptions() async {
        guard !busy else { return }; busy = true; let id = UUID(); requestID = id
        defer { if requestID == id { busy = false } }
        await refreshCookies()
        guard signedIn else { error = "Bitte zuerst in der YouTube-Ansicht anmelden, dann Abos erneut laden."; return }
        do {
            let page = try await request(AccountSubscriptionsFeedResponse.self,data: [:])
            guard requestID == id else { return }
            if page.isDisconnected { error = "Die YouTube-Anmeldung ist abgelaufen. Bitte erneut anmelden."; signedIn = false; return }
            results = map(page.results); continuation = page.continuationToken; feed = true; hasMore = continuation != nil; error = nil
        } catch { if requestID == id { self.error = "Deine Abos konnten gerade nicht geladen werden. In der YouTube-Ansicht kannst du es erneut versuchen." } }
    }
    func more() async {
        guard !busy, let token = continuation else { return }; busy = true; let id = requestID
        defer { if requestID == id { busy = false } }
        do {
            let videos: [YTVideo]
            if feed {
                let page = try await request(AccountSubscriptionsFeedResponse.Continuation.self,data: [.continuation:token]); videos = page.results; continuation = page.continuationToken
            } else {
                let page = try await request(SearchResponse.Continuation.self,data: [.continuation:token]); videos = page.results.compactMap { $0 as? YTVideo }; continuation = page.continuationToken
            }
            guard requestID == id else { return }
            var ids = Set(results.map(\.id)); results += map(videos).filter { ids.insert($0.id).inserted }; hasMore = continuation != nil
        } catch { self.error = "Weitere Videos konnten gerade nicht geladen werden." }
    }
    func signOut() async {
        requestID = UUID(); busy = false; model.cookies = ""; model.alwaysUseCookies = false; signedIn = false; results = []; continuation = nil; hasMore = false
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
    private func map(_ videos: [YTVideo]) -> [YouTubeResult] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.videoId).inserted }.map { YouTubeResult(id:$0.videoId,title:$0.title ?? "YouTube",channel:$0.channel?.name ?? "") }
    }
}
