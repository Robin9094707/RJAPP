import Foundation

/// A short voice message for the walkie-talkie ("Funk"). Audio lives as a normal server asset.
struct WalkieMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let senderID: String
    let targetID: String
    let assetID: String
    let duration: Double
    let createdAt: String
    var playedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, duration
        case senderID = "sender_id", targetID = "target_id", assetID = "asset_id", createdAt = "created_at", playedAt = "played_at"
    }
}

struct DailyAnswer: Codable, Hashable, Sendable {
    let userID: String
    let question: String
    let answer: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey { case question, answer; case userID = "user_id"; case updatedAt = "updated_at" }
}

/// The partner's answer is only sent by the server once you answered yourself.
struct DailyQuestionState: Codable, Hashable, Sendable {
    let day: String
    let mine: DailyAnswer?
    let partner: DailyAnswer?
    let partnerAnswered: Bool
    enum CodingKeys: String, CodingKey { case day, mine, partner; case partnerAnswered = "partner_answered" }
}

enum DailyQuestions {
    static let all: [String] = [
        "Was war heute dein schönster Moment mit mir – oder in Gedanken an mich?",
        "Wofür bist du mir heute dankbar?",
        "Welche kleine Geste von mir magst du besonders?",
        "Wohin würdest du morgen spontan mit mir reisen?",
        "Welches Lied erinnert dich gerade an uns?",
        "Was hat dich heute zum Lachen gebracht?",
        "Welche Erinnerung an uns schaust du dir im Kopf am liebsten an?",
        "Was möchtest du diese Woche unbedingt mit mir machen?",
        "Wann hast du dich zuletzt so richtig geborgen gefühlt?",
        "Was ist ein Traum, den wir gemeinsam erfüllen sollten?",
        "Welches Essen verbindest du mit uns beiden?",
        "Wie sähe unser perfekter fauler Sonntag aus?",
        "Was bewunderst du an mir, ohne es oft zu sagen?",
        "Welcher Moment unseres Kennenlernens fällt dir zuerst ein?",
        "Was gibt dir gerade Kraft?",
        "Welches kleine Ritual sollen wir neu einführen?",
        "Was würdest du mir heute gern ins Ohr flüstern?",
        "Wo siehst du uns in fünf Jahren an einem ganz normalen Abend?",
        "Welche Eigenschaft von mir hat dich überrascht?",
        "Was war heute anstrengend – und wie kann ich dir helfen?",
        "Welcher Film passt gerade zu unserer Stimmung?",
        "Was ist dein liebstes Foto von uns und warum?",
        "Wenn wir heute ein Date hätten: was, wo, wann?",
        "Was hast du heute über dich gelernt?",
        "Welches Kompliment möchtest du heute von mir hören?",
        "Was ist für dich echte Nähe?",
        "Welcher Duft erinnert dich an mich?",
        "Worauf freust du dich gerade am meisten?",
        "Was war unser lustigster gemeinsamer Fail?",
        "Welche drei Wörter beschreiben uns heute?",
        "Was möchtest du mir schon lange mal sagen?",
        "Welche Jahreszeit passt am besten zu uns – und warum?",
        "Was macht für dich einen perfekten Kuss aus?",
        "Welchen Ort sollten wir unbedingt wieder besuchen?",
        "Was hat dich heute an mich denken lassen?",
        "Wie möchtest du heute Abend einschlafen?",
        "Welche Kleinigkeit macht deinen Tag sofort besser?",
        "Was war dein erster Gedanke heute Morgen?",
        "Welches Abenteuer sollen wir dieses Jahr noch erleben?",
        "Was liebst du an unserem Alltag?",
        "Welcher Song soll auf unsere gemeinsame Playlist?",
        "Wie hast du dich heute gefühlt – in einem Emoji und einem Satz?",
        "Was würdest du an unserem Zuhause gern ändern?",
        "Welcher Moment heute verdient ein Foto, das niemand gemacht hat?",
        "Was ist dein geheimer Wunsch für unser nächstes Wochenende?",
        "Welches Talent von mir unterschätze ich?",
        "Was war das Netteste, das heute jemand zu dir gesagt hat?",
        "Wann warst du zuletzt richtig stolz auf uns?",
        "Welche Frage möchtest du mir einmal stellen?",
        "Was möchtest du morgen anders machen als heute?",
        "Welches Spiel sollen wir mal wieder zusammen spielen?",
        "Was ist dein liebster Spitzname für mich – und warum?",
        "Welche Gewohnheit von mir findest du heimlich süß?",
        "Was war heute dein Highlight in einem Wort?",
        "Was möchtest du mit mir zum ersten Mal ausprobieren?",
        "Welcher Augenblick mit mir hat sich wie Zuhause angefühlt?",
        "Wenn heute ein Kapitel in unserem Buch wäre: wie hieße es?",
        "Was kann ich dir morgen Gutes tun?",
        "Wovon hast du zuletzt geträumt?",
        "Was ist für dich das Schönste an uns beiden?"
    ]
    /// Both iPhones pick the same question for the same server day.
    static func question(for day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return all[0] }
        var components = DateComponents(); components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return all[0] }
        let days = Int(date.timeIntervalSince1970 / 86400)
        return all[((days % all.count) + all.count) % all.count]
    }
}
