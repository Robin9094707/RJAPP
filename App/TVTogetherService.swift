import Foundation
import Observation

struct TVStroke: Codable, Identifiable {
    let id: String
    let owner: String
    let points: [[Double]]
    let color: String
    let width: Double
}
struct TVSignal: Codable, Identifiable {
    let id: String
    let owner: String
    let symbol: String
    let created: Double
    var emoji: String { ["heart":"💗","kiss":"😘","hug":"🤗","star":"✨","wave":"👋"][symbol] ?? "💗" }
}
struct TVTogetherState: Codable {
    var epoch = ""
    var strokes: [TVStroke] = []
    var signals: [TVSignal] = []
    var board: [String] = Array(repeating: "",count: 9)
    var turn = "X"
    var players: [String:String] = [:]
    var winner = ""
    var mode = ""
}
struct TVTogetherEnvelope: Decodable { let revision: Int; let state: TVTogetherState?; let serverTime: Double
    enum CodingKeys: String,CodingKey { case revision,state; case serverTime = "server_time" }
}
@MainActor @Observable final class TVTogetherService {
    static let shared = TVTogetherService()
    var state = TVTogetherState()
    var revision = 0
    var error: String?
    var editing = false
    var updating = false
    private var api: APIClient?
    private var namespace = ""
    private var loop: Task<Void,Never>?
    private var clockOffset = 0.0
    var userID = ""
    var recentSignals: [TVSignal] { state.signals.filter { Date.now.timeIntervalSince1970 + clockOffset - $0.created < 25 } }
    func configure(api: APIClient,namespace: String,user: String) {
        guard self.namespace != namespace else { return }
        reset(); self.api = api.sessionCopy(); self.namespace = namespace; userID = user
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.namespace == namespace else { return }
                if CinemaCoordinator.shared.foreground && TVPresentation.shared.sharedEnabled { await self.refresh() }
                do { try await Task.sleep(for: .milliseconds(self.editing ? 700 : 2000)) } catch { return }
            }
        }
    }
    func reset() { loop?.cancel(); loop = nil; api = nil; namespace = ""; state = TVTogetherState(); revision = 0; error = nil; editing = false; userID = ""; clockOffset = 0 }
    private func apply(_ value: TVTogetherEnvelope) {
        guard value.revision >= revision else { return }
        revision = value.revision
        if let state = value.state {
            self.state = state
            if TVPresentation.shared.sharedEnabled,let mode = TVMode.allCases.first(where: { $0.networkID == state.mode }) { TVPresentation.shared.acceptRemote(mode) }
        }
        clockOffset = value.serverTime - Date.now.timeIntervalSince1970
    }
    func refresh() async {
        guard let api else { return }
        let space = namespace
        do {
            var request = try api.request(path: "/v1/cinema/tv",method: "GET")
            var url = URLComponents(url: request.url!,resolvingAgainstBaseURL: false)!
            url.queryItems = [.init(name: "after",value: String(revision))]; request.url = url.url
            let value = try await api.execute(request,as: TVTogetherEnvelope.self)
            guard namespace == space else { return }; apply(value); error = nil
        } catch { if namespace == space { self.error = error.localizedDescription } }
    }
    func action(_ action: String, values: [String:Any] = [:]) async {
        guard let api else { return }
        let space = namespace
        do {
            var body = values
            body["id"] = UUID().uuidString; body["action"] = action; body["revision"] = revision
            if action == "stroke", body["epoch"] == nil { body["epoch"] = state.epoch }
            let value = try await api.cinema("tv/action",body: body,as: TVTogetherEnvelope.self)
            guard namespace == space else { return }; apply(value); error = nil
        } catch { if namespace == space { let message = error.localizedDescription; await refresh(); self.error = message } }
    }
}
