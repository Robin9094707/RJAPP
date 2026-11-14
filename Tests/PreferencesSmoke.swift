import Foundation
@main struct PreferencesSmoke {
    static func main() throws {
        let old=Data(#"{"cards":[{"kind":"heart","size":"compact"}],"theme":"ocean","title":"Meine Seite","shortcuts":[]}"#.utf8)
        let migrated=try JSONDecoder().decode(HomeLayout.self,from:old)
        precondition(migrated.cards.contains {$0.kind == .homeKit})
        let companion=migrated.cards.firstIndex {$0.kind == .companion}, journal=migrated.cards.firstIndex {$0.kind == .dailyJournal}
        precondition(companion != nil && companion == journal.map {$0+1} && migrated.layoutVersion == 3)
        precondition(migrated.tabs.count == 4 && !migrated.tabs.contains {$0.action == .cinema})
        var layout=migrated;layout.cards=[];layout.tabs=[HomeShortcut(action:.documents)]
        let saved=try JSONDecoder().decode(HomeLayout.self,from:JSONEncoder().encode(layout))
        precondition(saved.cards.isEmpty && saved.tabs.first?.action == .documents)
        print("Layout migration and empty dashboard passed.")
    }
}
