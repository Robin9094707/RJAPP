import AppIntents
import Foundation
import WidgetKit

struct SendThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "An Schatzi denken"
    static var description = IntentDescription("Merkt einen liebevollen Gedanken vor. RJ Love sendet ihn beim nächsten Sync.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pending = WidgetSharedStore.addPendingThought()
        WidgetCenter.shared.reloadTimelines(ofKind: "RJLoveThoughtWidget")
        let message = pending == 1
            ? "Dein Gedanke ist vorgemerkt."
            : "\(pending) Gedanken warten auf den nächsten Sync."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct RJLoveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendThoughtIntent(),
            phrases: ["Mit \(.applicationName) an Schatzi denken"],
            shortTitle: "An Schatzi denken",
            systemImageName: "heart.fill"
        )
    }
}

struct EmergencyFartIntent: AppIntent {
    static var title: LocalizedStringResource = "Notfallfurz aufnehmen"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        WidgetSharedStore.defaults.set(true,forKey:"rjlove.quick-fart-requested")
        NotificationCenter.default.post(name:Notification.Name("rjEmergencyFartRequested"),object:nil)
        return .result()
    }
}
