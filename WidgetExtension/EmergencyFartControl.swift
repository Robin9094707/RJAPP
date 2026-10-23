import AppIntents
import SwiftUI
import WidgetKit
struct EmergencyFartControl: ControlWidget {
    static let kind="eu.rjuhas.rjlove.emergency-fart"
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:Self.kind) {
            ControlWidgetButton(action:EmergencyFartIntent()) {Label("Notfallfurz",systemImage:"cloud.fill")}
        }.displayName("Notfallfurz").description("Öffnet den Recorder und startet nach Mikrofonfreigabe eine Aufnahme. Ein bestehender Entwurf wartet sicher, bis die Notfallaufnahme erledigt ist.")
    }
}
