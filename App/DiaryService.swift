import Foundation
import Observation

/// Where a diary page lives.
enum DiaryVisibility: String, CaseIterable, Identifiable, Sendable {
    case together, shared, privateOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .together: "Unsere gemeinsame Seite"
        case .shared: "Meine Seite für uns"
        case .privateOnly: "Nur für mich"
        }
    }
    var short: String {
        switch self {
        case .together: "Gemeinsam"
        case .shared: "Für uns"
        case .privateOnly: "Privat"
        }
    }
    var symbol: String {
        switch self {
        case .together: "person.2.fill"
        case .shared: "heart.text.square.fill"
        case .privateOnly: "lock.fill"
        }
    }
    var explanation: String {
        switch self {
        case .together: "Eine Seite pro Tag, die ihr beide weiterschreiben könnt."
        case .shared: "Deine Seite des Tages. Dein Lieblingsmensch kann sie lesen, nur du bearbeitest sie."
        case .privateOnly: "Bleibt ausschließlich auf diesem iPhone. Wird nie zum Server übertragen."
        }
    }
}

/// A diary page that never leaves this iPhone.
struct PrivateDiaryEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID().uuidString
    var day: String
    var title: String
    var text: String
    var mood: String = ""
    var notes: String = ""
    var prompt: String = ""
    var aiAssisted = false
    var createdAt = Date()
    var updatedAt = Date()
    var date: Date? { DiaryDay.date(day) }
}

/// Unified view of a diary page for lists and the editor.
struct DiaryPage: Identifiable, Hashable {
    let id: String
    var day: String
    let visibility: DiaryVisibility
    let ownerID: String?
    var title: String
    var text: String
    var mood: String
    var notes: String
    var prompt: String
    var aiAssisted: Bool
    var updatedAt: Date
    var record: SharedRecord?
    var privateEntry: PrivateDiaryEntry?

    init(record: SharedRecord) {
        id = record.id
        day = record.payload.day ?? JournalDates.key(record.createdAt.rjDate ?? .now)
        visibility = record.payload.entryType == "together" ? .together : .shared
        ownerID = record.ownerID
        title = record.payload.title ?? "Ein Tag"
        text = record.payload.text ?? ""
        mood = record.payload.emoji ?? ""
        notes = record.payload.notes ?? ""
        prompt = record.payload.message ?? ""
        aiAssisted = record.payload.aiAssisted == true
        updatedAt = record.updatedAt.rjDate ?? .distantPast
        self.record = record
    }

    init(entry: PrivateDiaryEntry) {
        id = "private-" + entry.id
        day = entry.day
        visibility = .privateOnly
        ownerID = nil
        title = entry.title
        text = entry.text
        mood = entry.mood
        notes = entry.notes
        prompt = entry.prompt
        aiAssisted = entry.aiAssisted
        updatedAt = entry.updatedAt
        privateEntry = entry
    }

    var date: Date { DiaryDay.date(day) ?? updatedAt }
    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

enum DiaryDay {
    static func key(_ date: Date) -> String { JournalDates.key(date) }
    static func date(_ key: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Moods for a diary page. Kept short; the server accepts up to eight characters.
struct DiaryMoodOption: Hashable, Identifiable, Sendable {
    let emoji: String
    let title: String
    var id: String { emoji }
    init(_ emoji: String, _ title: String) { self.emoji = emoji; self.title = title }
}

enum DiaryMood {
    static let all: [DiaryMoodOption] = [
        DiaryMoodOption("🥰", "Verliebt"), DiaryMoodOption("😊", "Glücklich"), DiaryMoodOption("😌", "Entspannt"), DiaryMoodOption("🤩", "Aufgeregt"), DiaryMoodOption("😴", "Müde"),
        DiaryMoodOption("🤔", "Nachdenklich"), DiaryMoodOption("😢", "Traurig"), DiaryMoodOption("😤", "Gestresst"), DiaryMoodOption("🤒", "Krank"), DiaryMoodOption("🥳", "Gefeiert"),
    ]
    static func title(_ emoji: String) -> String { all.first { $0.emoji == emoji }?.title ?? "" }
}

/// Private diary pages, stored as a protected file on this iPhone only.
@MainActor
@Observable
final class PrivateDiaryStore {
    static let shared = PrivateDiaryStore()
    private(set) var entries: [PrivateDiaryEntry] = []
    private let url: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("rjlove-ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("private-diary.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([PrivateDiaryEntry].self, from: data) {
            entries = saved.sorted { $0.day == $1.day ? $0.updatedAt > $1.updatedAt : $0.day > $1.day }
        }
    }

    func save(_ entry: PrivateDiaryEntry) throws {
        var value = entry
        value.updatedAt = .now
        entries.removeAll { $0.id == value.id }
        entries.append(value)
        entries.sort { $0.day == $1.day ? $0.updatedAt > $1.updatedAt : $0.day > $1.day }
        try write()
    }

    func delete(_ id: String) throws {
        entries.removeAll { $0.id == id }
        try write()
    }

    private func write() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

extension AppState {
    var diaryRecords: [SharedRecord] { records.filter { $0.kind == .diary } }

    /// All diary pages visible on this iPhone: shared pages from the server and private local pages.
    func diaryPages() -> [DiaryPage] {
        let shared = diaryRecords.map(DiaryPage.init(record:))
        let local = PrivateDiaryStore.shared.entries.map(DiaryPage.init(entry:))
        return (shared + local).sorted { $0.day == $1.day ? $0.updatedAt > $1.updatedAt : $0.day > $1.day }
    }

    func diaryPages(on day: String) -> [DiaryPage] { diaryPages().filter { $0.day == day } }

    func togetherPage(on day: String) -> SharedRecord? {
        diaryRecords.filter { $0.payload.day == day && $0.payload.entryType == "together" }.max { $0.updatedAt < $1.updatedAt }
    }

    func saveDiary(_ page: DiaryPage, visibility: DiaryVisibility, existingID: String?) async -> Bool {
        let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = page.text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(60)).trimmingCharacters(in: .whitespaces) } ?? ""
        let cleanTitle = title.isEmpty ? (firstLine.isEmpty ? "Ein Tag für uns" : firstLine) : String(title.prefix(120))
        switch visibility {
        case .privateOnly:
            var entry = page.privateEntry ?? PrivateDiaryEntry(day: page.day, title: cleanTitle, text: page.text)
            entry.day = page.day; entry.title = cleanTitle; entry.text = page.text; entry.mood = page.mood
            entry.notes = page.notes; entry.prompt = page.prompt; entry.aiAssisted = page.aiAssisted
            do { try PrivateDiaryStore.shared.save(entry); Haptics.success(); AICompanion.shared.invalidateContext(); return true }
            catch { alert = AppAlert(title: "Tagebuch", message: error.localizedDescription); return false }
        case .shared, .together:
            var payload = RecordPayload(title: cleanTitle, text: page.text.isEmpty ? nil : String(page.text.prefix(20_000)), message: page.prompt.isEmpty ? nil : String(page.prompt.prefix(1_000)), notes: page.notes.isEmpty ? nil : String(page.notes.prefix(6_000)))
            payload.day = page.day
            payload.emoji = page.mood.isEmpty ? nil : String(page.mood.prefix(8))
            payload.entryType = visibility == .together ? "together" : "personal"
            payload.aiAssisted = page.aiAssisted ? true : nil
            let saved = await saveRecord(id: existingID, kind: .diary, payload: payload) != nil
            if saved { AICompanion.shared.invalidateContext() }
            return saved
        }
    }

    func deleteDiary(_ page: DiaryPage) async -> Bool {
        if let entry = page.privateEntry {
            do { try PrivateDiaryStore.shared.delete(entry.id); return true }
            catch { alert = AppAlert(title: "Tagebuch", message: error.localizedDescription); return false }
        }
        guard let record = page.record else { return false }
        return await deleteRecord(record)
    }
}
