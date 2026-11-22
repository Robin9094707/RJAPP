import CoreLocation
import Foundation
import LocalAuthentication

/// Collects what the iPhone already knows about a diary day: place, time of day, steps,
/// moments, messages and hearts. Nothing is sent anywhere until the page is saved.
@MainActor
enum DiaryContextCapture {
    struct Snapshot: Equatable {
        var place = ""
        var latitude: Double?
        var longitude: Double?
        var summary = ""
    }

    static func capture(app: AppState, day: String, includeLocation: Bool) async -> Snapshot {
        var snapshot = Snapshot()
        let today = day == DiaryDay.key(.now)
        var parts: [String] = []
        if today {
            parts.append(Date.now.formatted(.dateTime.weekday(.wide)) + " · " + timeOfDay(.now) + " " + Date.now.formatted(date: .omitted, time: .shortened))
            if let steps = HealthService.shared.steps, steps > 0 { parts.append("\(steps.formatted()) Schritte") }
            if app.myThoughtCount + app.partnerThoughtCount > 0 { parts.append("\(app.myThoughtCount + app.partnerThoughtCount) Herzgedanken") }
            if let status = app.myStatus?.visibleStatus { parts.append("Status: " + status) }
        }
        let dayRecords = app.records.filter { record in JournalDates.date(record).map { DiaryDay.key($0) == day } ?? false }
        let moments = dayRecords.filter { $0.kind == .moment || $0.kind == .instant }.count
        let messages = dayRecords.filter { $0.kind == .chat }.count
        if moments > 0 { parts.append("\(moments) \(moments == 1 ? "Moment" : "Momente")") }
        if messages > 0 { parts.append("\(messages) Nachrichten") }
        let captions = dayRecords.filter { $0.kind == .moment || $0.kind == .instant }.compactMap { $0.payload.caption ?? $0.payload.title }.filter { !$0.isEmpty }.prefix(3)
        if !captions.isEmpty { parts.append("Momente: " + captions.joined(separator: "; ")) }
        snapshot.summary = parts.joined(separator: " · ")
        if includeLocation, today, let location = LocationService.shared.lastLocation, abs(location.timestamp.timeIntervalSinceNow) < 3600, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1000 {
            snapshot.latitude = (location.coordinate.latitude * 1000).rounded() / 1000
            snapshot.longitude = (location.coordinate.longitude * 1000).rounded() / 1000
            snapshot.place = await placeName(location)
        }
        return snapshot
    }

    static func timeOfDay(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "morgens"
        case 11..<14: "mittags"
        case 14..<18: "nachmittags"
        case 18..<23: "abends"
        default: "nachts"
        }
    }

    private static func placeName(_ location: CLLocation) async -> String {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return "" }
        let local = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        var unique: [String] = []
        for part in local where !unique.contains(part) { unique.append(part) }
        return unique.prefix(2).joined(separator: ", ")
    }
}

/// ChatGPT helpers for Tagebuch 2.0. All optional; without sign-in the editor uses local fallbacks.
@MainActor
enum DiaryAI {
    struct Analysis: Equatable {
        var mood: String?
        var tags: [String] = []
        var title: String?
    }

    static func followUps(text: String, template: DiaryTemplate, visibility: DiaryVisibility, app: AppState) async throws -> [String] {
        let json = try await AICompanion.shared.askJSON("""
        Hier ist mein aktueller Tagebuchentwurf (\(template.title), \(visibility.title)):
        \(String(text.suffix(3000)))

        Stelle mir genau 3 kurze, einfühlsame Rückfragen (je höchstens 14 Wörter), die mir helfen, tiefer und ehrlicher weiterzuschreiben. \
        Wenn im App-Wissen frühere Tagebuchseiten oder Erlebnisse passen, darfst du dich darauf beziehen („Letzte Woche schriebst du …“). Keine Ratschläge, keine Diagnosen.
        Format: {"questions": ["…", "…", "…"]}
        """, system: "Du bist ein warmer, neugieriger Tagebuch-Begleiter wie bei Rosebud.", app: app, includeContext: true)
        let questions = (json["questions"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(questions.prefix(3))
    }

    static func analyze(text: String, app: AppState) async throws -> Analysis {
        let moods = DiaryMood.all.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")
        let json = try await AICompanion.shared.askJSON("""
        Lies diesen Tagebucheintrag und schlage vor:
        - "mood": genau ein Emoji aus dieser Liste, das die Stimmung am besten trifft: \(moods)
        - "tags": 1 bis 4 kurze deutsche Themen-Schlagwörter in Kleinbuchstaben ohne #
        - "title": eine kurze, poetische Überschrift (höchstens 6 Wörter)

        Eintrag:
        \(String(text.prefix(4000)))
        """, system: "Du ordnest Tagebucheinträge behutsam ein.", app: app, includeContext: false)
        var analysis = Analysis()
        if let mood = json["mood"] as? String {
            let trimmed = mood.trimmingCharacters(in: .whitespacesAndNewlines)
            analysis.mood = DiaryMood.all.first { trimmed.hasPrefix($0.emoji) || trimmed == $0.title }?.emoji
        }
        analysis.tags = (json["tags"] as? [String] ?? []).map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }.prefix(4).map { String($0.prefix(30)) }
        if let title = json["title"] as? String, !title.isEmpty { analysis.title = String(title.trimmingCharacters(in: CharacterSet(charactersIn: "\"„“ .\n")).prefix(120)) }
        return analysis
    }

    static func reflection(text: String, app: AppState) async throws -> String {
        try await AICompanion.shared.ask("""
        Lies meinen Tagebucheintrag und spiegle ihn mir in 2–3 warmen Sätzen zurück: was du heraushörst, was gut war, und eine sanfte Frage für morgen. \
        Wenn passend, verbinde es mit Mustern aus meinen früheren Einträgen im App-Wissen. Keine Ratschläge zu Gesundheit, keine Bewertung der Beziehung.

        \(String(text.prefix(5000)))
        """, system: "Du bist ein einfühlsamer Tagebuch-Begleiter.", app: app, includeContext: true)
    }
}

/// Face ID / code lock for the private diary area.
@MainActor
enum DiaryLock {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "rjlove.diary.private-lock") }
        set { UserDefaults.standard.set(newValue, forKey: "rjlove.diary.private-lock") }
    }

    static func unlock() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Dein privates Tagebuch öffnen")) ?? false
    }
}
