import AppIntents
import SwiftUI
import WidgetKit
struct EmergencyFartControl: ControlWidget {
    static let kind="eu.rjuhas.rjlove.emergency-fart"
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:Self.kind) {
            ControlWidgetButton(action:EmergencyFartIntent()) {Label("Notfallfurz",systemImage:"mic.fill")}
        }.displayName("Notfallfurz").description("Öffnet den Recorder und startet nach Mikrofonfreigabe eine Aufnahme. Vorhandene Entwürfe bleiben erhalten.")
    }
}
