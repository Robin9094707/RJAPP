import Foundation

/// Notification links only select screens. They never send, delete or confirm.
struct NotificationRoute: Hashable, Identifiable, Sendable {
    let target: String
    var identifier: String?
    var commentID: String?
    var account: String?
    var id: String { [target, identifier ?? "", commentID ?? "", account ?? ""].joined(separator: ":") }
    static let targets: Set<String> = ["documents", "home", "feed", "partner", "planner", "alarms", "chat", "moments", "farts", "poop", "countdowns", "record", "fart", "fart-comments"]

    init(target: String, identifier: String? = nil, commentID: String? = nil, account: String? = nil) {
        self.target = target; self.identifier = identifier; self.commentID = commentID; self.account = account
    }
    init?(url: URL) {
        guard url.scheme?.lowercased() == "rjlove", url.host?.lowercased() == "open",
              url.path.isEmpty || url.path == "/", url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        let names = items.map(\.name)
        guard Set(names).count == names.count, Set(names).isSubset(of: ["target", "id", "comment", "account"]) else { return nil }
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
        guard let target = value("target"), Self.targets.contains(target) else { return nil }
        let identifier = value("id"), comment = value("comment"), account = value("account")
        if ["record", "fart", "fart-comments"].contains(target), identifier == nil { return nil }
        if let identifier, UUID(uuidString: identifier) == nil { return nil }
        if let comment, UUID(uuidString: comment) == nil { return nil }
        if let account, account.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) == nil { return nil }
        self.init(target: target, identifier: identifier, commentID: comment, account: account)
    }
}
