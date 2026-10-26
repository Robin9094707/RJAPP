import Foundation

enum HomeCardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortcuts, cinema, homeKit, eveningPlayer, dailyJournal, documents, heart, partner, quickActions, studio, messenger, history, planner, instant, milestone, health, live, delivery, relationship, poop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortcuts: "Meine Schnellzugriffe"
        case .cinema: "Unser gemeinsames Kino"
        case .homeKit: "Unser Zuhause & Kameras"
        case .eveningPlayer: "Abendplayer"
        case .dailyJournal: "Unser Tagesrückblick"
        case .documents: "Gemeinsame Dokumente"
        case .heart: "Herzgedanken"
        case .partner: "Mein Lieblingsmensch"
        case .quickActions: "Schnellaktionen"
        case .studio: "Duftstudio"
        case .messenger: "Unser Gespräch"
        case .history: "Herzchronik"
        case .planner: "Unsere Planung"
        case .instant: "Fotowünsche"
        case .milestone: "Jahrestag & Countdowns"
        case .health: "Schlaf & Wohlgefühl"
        case .live: "Live-Aktivität"
        case .delivery: "Push & Wecker"
        case .relationship: "Unsere Beziehungsmonate"
        case .poop: "Drop-Poop"
        }
    }
    var symbol: String {
        switch self {
        case .shortcuts: "square.grid.2x2"
        case .cinema: "play.tv.fill"
        case .homeKit: "house.fill"
        case .eveningPlayer: "play.square.stack.fill"
        case .dailyJournal: "book.closed.fill"
        case .documents: "folder.fill"
        case .heart: "heart.fill"
        case .partner: "person.crop.circle.fill"
        case .quickActions: "square.grid.2x2.fill"
        case .studio: "wind"
        case .messenger: "bubble.left.and.bubble.right.fill"
        case .history: "heart.text.square.fill"
        case .planner: "calendar.badge.clock"
        case .instant: "camera.fill"
        case .milestone: "calendar.badge.heart"
        case .health: "moon.zzz.fill"
        case .live: "livephoto"
        case .delivery: "checkmark.shield.fill"
        case .relationship: "heart.circle.fill"
        case .poop: "toilet.fill"
        }
    }
}
enum HomeCardSize: String, Codable, CaseIterable, Sendable { case compact, large }
struct HomeCard: Codable, Hashable, Identifiable, Sendable {
    var kind: HomeCardKind
    var size: HomeCardSize = .large
    var id: String { kind.rawValue }
}
struct HomeLayout: Codable, Hashable, Sendable {
    var cards: [HomeCard] = HomeCardKind.allCases.map { HomeCard(kind: $0) }
    var theme: String = "rose"
    var title: String = "Euer kleines Wir."
    var shortcuts:[HomeShortcut]=HomeShortcut.standard
    var tabs: [HomeShortcut] = HomeShortcut.standardTabs
    var layoutVersion = 2
    static let standard = HomeLayout()
    enum CodingKeys:String,CodingKey {case cards,theme,title,shortcuts,tabs,layoutVersion}
    init(){}
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        cards=try c.decodeIfPresent([HomeCard].self,forKey:.cards) ?? HomeCardKind.allCases.map{HomeCard(kind:$0)}
        theme=try c.decodeIfPresent(String.self,forKey:.theme) ?? "rose"
        title=try c.decodeIfPresent(String.self,forKey:.title) ?? "Euer kleines Wir."
        tabs=try c.decodeIfPresent([HomeShortcut].self,forKey:.tabs) ?? HomeShortcut.standardTabs
        layoutVersion=try c.decodeIfPresent(Int.self,forKey:.layoutVersion) ?? 0
        if layoutVersion < 2 {
            cards = [HomeCardKind.shortcuts,.cinema,.homeKit,.eveningPlayer,.dailyJournal].filter { kind in !cards.contains { $0.kind == kind } }.map { HomeCard(kind:$0) } + cards
            layoutVersion = 2
        }
        shortcuts=try c.decodeIfPresent([HomeShortcut].self,forKey:.shortcuts) ?? HomeShortcut.standard
    }
}
struct UserPreferences: Codable, Sendable {
    var dashboard: HomeLayout
    var revision: Int
}
