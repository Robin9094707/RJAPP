import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            DebugLogger.shared.log("Kalender: \(error.localizedDescription)", category: "Kalender")
            return false
        }
    }

    func addToCalendar(_ record: SharedRecord) async throws {
        guard record.kind == .calendar,
              let start = record.payload.startAt?.rjDate,
              let end = record.payload.endAt?.rjDate else { throw CalendarError.invalidEvent }
        if authorizationStatus != .fullAccess, !(await requestAccess()) {
            throw CalendarError.permissionDenied
        }
        let event = EKEvent(eventStore: store)
        event.title = record.payload.title ?? "Gemeinsamer Termin"
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(60))
        event.notes = record.payload.notes
        event.location = record.payload.location
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
    }
}

enum CalendarError: LocalizedError {
    case invalidEvent
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidEvent: "Der Termin ist unvollständig."
        case .permissionDenied: "Kalenderzugriff wurde nicht erlaubt."
        }
    }
}
