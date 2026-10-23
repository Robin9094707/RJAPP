import Foundation

enum HomeQuickAction:String,Codable,CaseIterable,Identifiable,Sendable {
    case moments,captureMoment,instant,studio,recordFart,playlist,journal,feed,messenger,status,partner,nearby,map,health,countdowns,planner,ritual,notes,live,profile,updates,aiSummary
    var id:String{rawValue}
    var title:String {switch self {
    case .moments:"Momente";case .captureMoment:"Aufnehmen";case .instant:"BeReal";case .studio:"Duftstudio";case .recordFart:"Notfallfurz";case .playlist:"Unser Abend";case .journal:"Unser Tag";case .feed:"Neuigkeiten";case .messenger:"Nachrichten";case .status:"Mein Status";case .partner:"Lieblingsmensch";case .nearby:"Nahsuche";case .map:"Karte";case .health:"Health & Schlaf";case .countdowns:"Countdowns";case .planner:"Planung";case .ritual:"Abendritual";case .notes:"Notizen";case .live:"Live-Aktivität";case .profile:"Mein Profil";case .updates:"App-Update";case .aiSummary:"KI-Rückblick"
    }}
    var symbol:String {switch self {
    case .moments:"photo.stack";case .captureMoment:"camera.fill";case .instant:"camera.on.rectangle.fill";case .studio:"waveform";case .recordFart:"cloud.fill";case .playlist:"play.square.stack.fill";case .journal:"book.closed.fill";case .feed:"sparkles.rectangle.stack";case .messenger:"bubble.left.and.bubble.right.fill";case .status:"person.crop.circle.badge.clock";case .partner:"heart.fill";case .nearby:"dot.radiowaves.left.and.right";case .map:"map.fill";case .health:"heart.text.square.fill";case .countdowns:"calendar.badge.heart";case .planner:"calendar";case .ritual:"moon.stars.fill";case .notes:"note.text";case .live:"livephoto";case .profile:"person.crop.circle";case .updates:"arrow.down.app";case .aiSummary:"sparkles"
    }}
    var immediate:Bool {[.recordFart,.status,.partner,.profile].contains(self)}
}
struct HomeShortcut:Codable,Hashable,Identifiable,Sendable {
    var id:String=UUID().uuidString
    var action:HomeQuickAction
    var title:String
    init(action:HomeQuickAction){self.action=action;title=action.title}
    static let standard:[Self]=[HomeQuickAction.moments,.captureMoment,.playlist,.instant,.status,.journal].map{Self(action:$0)}
}
