import AlarmKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorizationState = AlarmManager.shared.authorizationState
    private(set) var lastError: String?
    private let scheduledKey = "rjlove.scheduled-alarm-ids"
    private let reminderFingerprintsKey = "rjlove.reminder-alarm-fingerprints"

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
        guard reminder.kind == .reminder, let id = UUID(uuidString: reminder.id) else { return }
        if reminder.payload.recurrence == "yearly" { cancel(id:reminder.id); return }
        guard reminder.payload.alarmEnabled ?? false,
              reminder.payload.completed != true,
              let due = reminder.payload.dueAt?.rjDate,
              due > .now else {
            cancel(id: reminder.id)
            return
        }
        let fingerprint = reminderFingerprint(reminder, senderName: senderName)
        guard reminderFingerprints[reminder.id] != fingerprint else { return }
        if scheduledIDs.contains(reminder.id) {
            cancel(id: reminder.id)
        }
        guard await ensureAuthorization() else { throw AlarmServiceError.permissionDenied }
        try await RJLoveAlarmFactory.schedule(
            id: id,
            title: reminder.payload.title ?? "Gemeinsame Erinnerung",
            senderName: senderName,
            fireDate: due
        )
        remember(reminder.id, reminderFingerprint: fingerprint)
    }

    func reconcile(reminders: [SharedRecord], myID: String, senderName: String) async {
        // The server is authoritative for receiver quiet hours. Remove alarms
        // installed by older app versions so they cannot bypass those rules.
        for id in Array(scheduledIDs) { cancel(id: id) }
    }

    func cancel(id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        try? AlarmManager.shared.cancel(id: uuid)
        var values = scheduledIDs
        values.remove(id)
        UserDefaults.standard.set(Array(values), forKey: scheduledKey)
        var fingerprints = reminderFingerprints
        fingerprints.removeValue(forKey: id)
        UserDefaults.standard.set(fingerprints, forKey: reminderFingerprintsKey)
    }

    private func ensureAuthorization() async -> Bool {
        authorizationState = AlarmManager.shared.authorizationState
        switch authorizationState {
        case .authorized: return true
        case .notDetermined:
            guard UIApplication.shared.applicationState == .active else { return false }
            return await requestAuthorization()
        case .denied: return false
        @unknown default: return false
        }
    }

    private var scheduledIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: scheduledKey) ?? [])
    }

    private var reminderFingerprints: [String: String] {
        UserDefaults.standard.dictionary(forKey: reminderFingerprintsKey) as? [String: String] ?? [:]
    }

    private func reminderFingerprint(_ reminder: SharedRecord, senderName: String) -> String {
        [
            reminder.payload.dueAt ?? "",
            reminder.payload.title ?? "",
            reminder.payload.targetID ?? "both",
            senderName,
        ].joined(separator: "|")
    }

    private func remember(_ id: String, reminderFingerprint: String? = nil) {
        var values = scheduledIDs
        values.insert(id)
        UserDefaults.standard.set(Array(values), forKey: scheduledKey)
        if let reminderFingerprint {
            var fingerprints = self.reminderFingerprints
            fingerprints[id] = reminderFingerprint
            UserDefaults.standard.set(fingerprints, forKey: reminderFingerprintsKey)
        }
    }
}

enum AlarmServiceError: LocalizedError {
    case permissionDenied
    var errorDescription: String? {
        "AlarmKit ist nicht erlaubt. Aktiviere die Berechtigung unter Mehr → Berechtigungen."
    }
}

