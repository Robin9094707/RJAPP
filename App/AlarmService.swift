import AlarmKit
import Foundation
import Observation

@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorizationState = AlarmManager.shared.authorizationState
    private(set) var lastError: String?
    private let scheduledKey = "rjlove.scheduled-alarm-ids"

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
            return authorizationState == .authorized
        } catch {
            lastError = error.localizedDescription
            DebugLogger.shared.log("AlarmKit: \(error.localizedDescription)", category: "Alarm")
            return false
        }
    }

    func schedule(command: RemoteCommand, senderName: String) async throws {
        guard let id = UUID(uuidString: command.id), !scheduledIDs.contains(command.id) else { return }
        guard await ensureAuthorization() else { throw AlarmServiceError.permissionDenied }
        let date = command.dueAt?.rjDate ?? .now.addingTimeInterval(1)
        try await RJLoveAlarmFactory.schedule(
            id: id,
            title: command.payload.message,
            senderName: senderName,
            fireDate: max(date, .now.addingTimeInterval(1))
        )
        remember(command.id)
        DebugLogger.shared.log("Weckruf \(command.id) geplant", category: "Alarm")
    }

    func schedule(reminder: SharedRecord, senderName: String) async throws {
        guard reminder.kind == .reminder,
              reminder.payload.alarmEnabled ?? false,
              let due = reminder.payload.dueAt?.rjDate,
              due > .now,
              let id = UUID(uuidString: reminder.id),
              !scheduledIDs.contains(reminder.id) else { return }
        guard await ensureAuthorization() else { throw AlarmServiceError.permissionDenied }
        try await RJLoveAlarmFactory.schedule(
            id: id,
            title: reminder.payload.title ?? "Gemeinsame Erinnerung",
            senderName: senderName,
            fireDate: due
        )
        remember(reminder.id)
    }

    func cancel(id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        try? AlarmManager.shared.cancel(id: uuid)
        var values = scheduledIDs
        values.remove(id)
        UserDefaults.standard.set(Array(values), forKey: scheduledKey)
    }

    private func ensureAuthorization() async -> Bool {
        authorizationState = AlarmManager.shared.authorizationState
        switch authorizationState {
        case .authorized: return true
        case .notDetermined: return await requestAuthorization()
        case .denied: return false
        @unknown default: return false
        }
    }

    private var scheduledIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: scheduledKey) ?? [])
    }

    private func remember(_ id: String) {
        var values = scheduledIDs
        values.insert(id)
        UserDefaults.standard.set(Array(values), forKey: scheduledKey)
    }
}

enum AlarmServiceError: LocalizedError {
    case permissionDenied
    var errorDescription: String? {
        "AlarmKit ist nicht erlaubt. Aktiviere die Berechtigung unter Mehr → Berechtigungen."
    }
}
