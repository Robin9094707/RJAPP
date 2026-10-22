import Foundation

struct Duftspruch: Decodable {
    let id: String
    let situation: String
    let text: String
}
@MainActor enum DuftspruchDeck {
    static let cards: [Duftspruch] = {
        guard let url = Bundle.main.url(forResource: "Duftsprueche", withExtension: "json"), let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([Duftspruch].self, from: data) else { return [] }
        return result
    }()
    static func next(for situation: FartSituation) -> String {
        let key = "rjlove.quips." + situation.rawValue
        let recent = UserDefaults.standard.stringArray(forKey: key) ?? []
        let candidates = cards.filter { $0.situation == situation.rawValue }
        let available = candidates.filter { !recent.contains($0.id) }
        guard let card = (available.isEmpty ? candidates : available).randomElement() else { return "Für immer. Fürzeinander. Eure Bühne ist bereit." }
        UserDefaults.standard.set(Array((recent + [card.id]).suffix(32)), forKey: key)
        return card.text
    }
    static func suggested(hasDraft: Bool, motion: String?) -> FartSituation {
        if hasDraft { return .zugabe }
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 5 || hour >= 22 { return .nacht }
        if hour < 11 { return .morgen }
        if ["Zu Fuß","Laufen","Auto","Radfahren"].contains(motion ?? "") { return .unterwegs }
        return .alltag
    }
}
