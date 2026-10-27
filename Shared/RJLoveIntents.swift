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
        if pending==0 {return .result(dialog:"Widget nicht verbunden. Bitte App-Group-Signierung prüfen und RJ Love öffnen.")}
        let message = pending == 1
            ? "Dein Gedanke ist vorgemerkt."
            : "\(pending) Gedanken warten auf den nächsten Sync."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct RJLoveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:EmergencyFartIntent(),phrases:["Notfallfurz mit \(.applicationName)"],shortTitle:"Notfallfurz",systemImageName:"cloud.fill")
        AppShortcut(intent:LogPoopIntent(),phrases:["Drop-Poop mit \(.applicationName)"],shortTitle:"Drop setzen",systemImageName:"toilet.fill")
        AppShortcut(intent:OpenMomentsIntent(),phrases:["Momente in \(.applicationName) öffnen"],shortTitle:"Unsere Momente",systemImageName:"photo.stack.fill")
        AppShortcut(intent:OpenPartnerMapIntent(),phrases:["Schatzi in \(.applicationName) finden"],shortTitle:"Partnerkarte",systemImageName:"location.fill")
        AppShortcut(intent:SetLoveStatusIntent(),phrases:["Status in \(.applicationName) setzen"],shortTitle:"Status setzen",systemImageName:"face.smiling")
        AppShortcut(
            intent: SendThoughtIntent(),
            phrases: ["Mit \(.applicationName) an Schatzi denken"],
            shortTitle: "An Schatzi denken",
            systemImageName: "heart.fill"
        )
    }
}

struct EmergencyFartIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Notfallfurz aufnehmen"
    static var supportedModes: IntentModes { .foreground }
    @MainActor func perform() async throws -> some IntentResult {
        QuickCaptureRequests.enqueue()
        return .result()
    }
}

private func requestLoveRoute(_ route:String) {
    WidgetSharedStore.defaults?.set(route,forKey:"rjlove.route-requested")
    NotificationCenter.default.post(name:Notification.Name("rjEmergencyFartRequested"),object:nil)
}
struct OpenMomentsIntent:AppIntent {
    static var title:LocalizedStringResource="Unsere Momente öffnen"
    static var openAppWhenRun=true
    @MainActor func perform() async throws -> some IntentResult {requestLoveRoute("rjlove://moments");return .result()}
}
struct OpenPartnerMapIntent:AppIntent {
    static var title:LocalizedStringResource="Partnerkarte öffnen"
    static var openAppWhenRun=true
    @MainActor func perform() async throws -> some IntentResult {requestLoveRoute("rjlove://map");return .result()}
}
struct SetLoveStatusIntent:AppIntent {
    static var title:LocalizedStringResource="Meinen Status setzen"
    static var description=IntentDescription("Öffnet RJ Love und teilt deinen Status mit Schatzi. Anmeldung und Serververbindung erforderlich.")
    static var openAppWhenRun=true
    @Parameter(title:"Status") var text:String
    @Parameter(title:"Stunden (0 = bis zur Änderung)",default:2) var hours:Int
    @Parameter(title:"Bitte nicht stören",default:false) var quiet:Bool
    @MainActor func perform() async throws -> some IntentResult {
        WidgetSharedStore.defaults?.set(["text":String(text.prefix(120)),"hours":min(8,max(0,hours)),"quiet":quiet],forKey:"rjlove.status-requested")
        NotificationCenter.default.post(name:Notification.Name("rjEmergencyFartRequested"),object:nil)
        return .result()
    }
}

struct LogPoopIntent:AppIntent {
    static var title:LocalizedStringResource="Drop-Poop eintragen"
    static var description=IntentDescription("Öffnet euren privaten Thronbericht. Erst nach deiner Bestätigung wird etwas geteilt.")
    static var openAppWhenRun=true
    @MainActor func perform() async throws -> some IntentResult {requestLoveRoute("rjlove://poop-log");return .result()}
}

