import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

struct RJLoveAlarmMetadata: AlarmMetadata {
    var commandID: String
    var title: String
    var senderName: String
}

enum RJLoveAlarmFactory {
    static func attributes(id: UUID, title: String, senderName: String) -> AlarmAttributes<RJLoveAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let countdown = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: title),
            pauseButton: nil
        )
        let paused = AlarmPresentation.Paused(
            title: LocalizedStringResource(stringLiteral: "Weckruf pausiert"),
            resumeButton: AlarmButton(
                text: "Fortsetzen",
                textColor: .pink,
                systemImageName: "play.fill"
            )
        )
        return AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: RJLoveAlarmMetadata(commandID: id.uuidString, title: title, senderName: senderName),
            tintColor: .pink
        )
    }

    static func schedule(id: UUID, title: String, senderName: String, fireDate: Date) async throws {
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(fireDate),
            attributes: attributes(id: id, title: title, senderName: senderName),
            stopIntent: StopLoveAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}

struct StopLoveAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Weckruf stoppen"

    @Parameter(title: "Alarm-ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        return .result()
    }
}

struct ConnectionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var battery: Int?
        var motion: String
        var lastUpdate: Date
        var myThoughts: Int
        var partnerThoughts: Int
    }

    var partnerName: String
}

struct NearbySearchAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var active: Bool }
    var until: Date
}
