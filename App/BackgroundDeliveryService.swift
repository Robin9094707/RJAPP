import AlarmKit
import Foundation
import UIKit

struct BackgroundSnapshot: Decodable {
    let userID: String
    let senderName: String
    let commands: [RemoteCommand]
    let reminders: [SharedRecord]
    enum CodingKeys: String, CodingKey { case commands, reminders; case userID = "user_id"; case senderName = "sender_name" }
}
struct CommandDelivery: Decodable, Identifiable {
    let id: String
    let dueAt: String
    let message: String
    let status: String
    let reason: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey { case id, message, status, reason; case dueAt = "due_at"; case updatedAt = "updated_at" }
    var title: String {
        switch status { case "scheduled": "Auf dem iPhone eingeplant"; case "expired": "Abgelaufen · wird nicht verspätet ausgelöst"; case "failed": "Zustellung meldet ein Problem"; case "acknowledged": "Empfänger ist wach · bestätigt"; case "suppressed": "Ruhezeit · Weckruf gesperrt"; case "sent": "An Push-Dienst übergeben"; default: "Warte auf Bestätigung des iPhones" }
    }
}
struct PushAttempt: Decodable, Identifiable {
    let id: String
    let kind: String
    let status: String
    let reason: String
    let createdAt: String
    enum CodingKeys: String, CodingKey { case id, kind, status, reason; case createdAt = "created_at" }
}
struct PushReadiness: Decodable {
    let ready: Bool
    let issues: [String]
    let bundleID: String
    let registeredDevices: Int
    let attempts: [PushAttempt]
    let automaticSetup: String?
    enum CodingKeys: String, CodingKey { case ready, issues, attempts; case bundleID = "bundle_id"; case registeredDevices = "registered_devices"; case automaticSetup = "automatic_setup" }
}

/// Shared foreground/background command pipeline. Completion means AlarmKit accepted
/// the schedule; it never claims that the device has actually sounded the alarm.
@MainActor final class CommandDeliveryProcessor {
    static let shared = CommandDeliveryProcessor()
    private var processing = Set<String>()
    func process(_ commands: [RemoteCommand], api: APIClient, senderName: String) async {
        for command in commands {
            guard !Task.isCancelled else { return }
            if ["bark", "ntfy"].contains(command.payload.transport ?? "") { continue }
            guard !processing.contains(command.id) else { continue }
            processing.insert(command.id)
            if let due = command.dueAt?.rjDate, Date.now.timeIntervalSince(due) > 300 {
                try? await api.commandReceipt(id: command.id, status: "expired", reason: "Mehr als fünf Minuten nach der Weckzeit empfangen. Kein verspäteter Alarm.")
            } else {
                do {
                    try await AlarmService.shared.schedule(command: command, senderName: senderName)
                    try await api.commandReceipt(id: command.id, status: "scheduled", reason: "AlarmKit hat die Planung auf diesem iPhone angenommen.")
                } catch {
                    let value = error as NSError
                    let reason = "\(value.domain) (\(value.code)): \(value.localizedDescription)"
                    try? await api.commandReceipt(id: command.id, status: "failed", reason: reason)
                    DebugLogger.shared.log("Weckruf bleibt unbestätigt: " + reason, category: "Alarm")
                }
            }
            processing.remove(command.id)
        }
    }
}

/// Cold-launch background entry point. Does not depend on RootView, Face ID, UI
/// observers, the foreground poller, cached Health data, or downloading photos.
@MainActor final class BackgroundDeliveryService {
    static let shared = BackgroundDeliveryService()
    private var work: Task<Bool, Never>?
    private var needsAnotherPass = false
    private init() {}
    func run(source: String) async -> Bool {
        if let work {
            needsAnotherPass = true
            return await work.value
        }
        let task = Task { @MainActor in
            var success = false
            repeat {
                self.needsAnotherPass = false
                success = await self.perform(source: source)
            } while self.needsAnotherPass && !Task.isCancelled
            return success
        }
        work = task
        let result = await task.value
        work = nil
        return result
    }
    func cancel() { work?.cancel() }
    private func perform(source: String) async -> Bool {
        UserDefaults.standard.set(Date.now.rjISO8601, forKey: "rjlove.last-background-at")
        UserDefaults.standard.set(source, forKey: "rjlove.last-background-source")
        guard let bytes = UserDefaults.standard.data(forKey: AppState.profileKey),
              let profile = try? JSONDecoder().decode(ServerProfile.self, from: bytes),
              let url = AppState.normalizedServerURL(profile.baseURL),
              let token = KeychainStore.get(AppState.tokenKey) else {
            UserDefaults.standard.set("Keine zugängliche Sitzung. Nach einem Neustart das iPhone einmal entsperren und anmelden.", forKey: "rjlove.last-background-result")
            return false
        }
        let api = APIClient(background: true)
        api.configure(baseURL: url, token: token)
        do {
            try await api.checkCompatibility()
            let snapshot = try await api.backgroundSnapshot()
            guard !Task.isCancelled else { return false }
            await CommandDeliveryProcessor.shared.process(snapshot.commands, api: api, senderName: snapshot.senderName)
            guard !Task.isCancelled else { return false }
            await AlarmService.shared.reconcile(reminders: snapshot.reminders, myID: snapshot.userID, senderName: snapshot.senderName)
            if UIApplication.shared.applicationState != .active {
                try await api.reportActivity(mode:"background",source:source)
                UserDefaults.standard.set(Date.now.rjISO8601,forKey:"rjlove.last-successful-background-at")
            }
            UserDefaults.standard.set("Hintergrundabruf abgeschlossen; \(snapshot.commands.count) Weckauftrag/-aufträge geprüft.", forKey: "rjlove.last-background-result")
            return true
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "rjlove.last-background-result")
            DebugLogger.shared.log("Hintergrund: " + error.localizedDescription, category: "Push")
            return false
        }
    }
}

