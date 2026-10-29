import SwiftUI

struct NotificationTargetResponse: Decodable {
    let record: SharedRecord?
    let clip: FartClip?
    let folderID:String?
    let documentID:String?
    enum CodingKeys:String,CodingKey {case record,clip;case folderID="folder_id",documentID="document_id"}
}
extension APIClient {
    func notificationTarget(_ route: NotificationRoute) async throws -> NotificationTargetResponse {
        var req = try request(path: "/v1/navigation", method: "GET")
        guard var components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false) else { throw APIClientError.invalidServerURL }
        components.queryItems = [URLQueryItem(name: "target", value: route.target)]
        if let id = route.identifier { components.queryItems?.append(URLQueryItem(name: "id", value: id)) }
        if let account = route.account { components.queryItems?.append(URLQueryItem(name: "account", value: account)) }
        req.url = components.url
        return try await execute(req, as: NotificationTargetResponse.self)
    }
}

struct NotificationDestinationView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let route: NotificationRoute
    @State private var content: NotificationTargetResponse?
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        Group {
            if let clip = content?.clip, route.target == "fart-comments" {
                FartCommentsView(clip: clip, initialCommentID: route.commentID)
            } else if let record = content?.record, [.moment, .instant].contains(record.kind) {
                MomentGalleryViewer(records: [record], initialID: record.id)
            } else {
                NavigationStack {
                    destination
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zurück zur App") { dismiss() } } }
                }
            }
        }
        .background(LoveBackground())
        .task(id: route.id) { await load() }
    }
    @ViewBuilder private var destination: some View {
        if loading { ProgressView("Deinen Beitrag laden …").frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let error {
            VStack(spacing: 20) {
                ContentUnavailableView("Beitrag gerade nicht verfügbar", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text(error))
                Button("Erneut versuchen") { Task { await load() } }.buttonStyle(.bordered)
            }
        } else if let clip = content?.clip {
            ScrollView { FartClipCard(clip: app.farts.first { $0.id == clip.id } ?? clip).padding(20) }
                .navigationTitle("Deine Duftpost")
        } else if let record = content?.record, record.kind != .chat {
            NotificationRecordDetail(original: record)
        } else {
            switch route.target {
            case "documents": DocumentsView(folderID:content?.folderID,highlightID:content?.documentID)
            case "chat": MessengerView(initialMessageID: route.identifier)
            case "partner": PartnerProfileView()
            case "planner": PlannerView()
            case "alarms": DeliveryCenterView()
            case "moments": MomentsView()
            case "farts": FartStudioView()
            case "poop": DropPoopView()
            case "countdowns": CountdownHubView()
            default: SharedJournalView(showFeed: true)
            }
        }
    }
    private func load() async {
        loading = true; error = nil; content = nil
        do {
            content = try await app.api.notificationTarget(route)
            if let record = content?.record { app.retainNotificationRecord(record) }
            loading = false
        } catch { self.error = error.localizedDescription; loading = false }
    }
}

private struct NotificationRecordDetail: View {
    @Environment(AppState.self) private var app
    let original: SharedRecord
    @State private var editing = false
    private var record: SharedRecord { app.records.first { $0.id == original.id } ?? original }
    private var editable: Bool { [.note, .reminder, .calendar, .milestone].contains(record.kind) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                JournalRecordDetail(record: record)
                if let message = record.payload.message, !message.isEmpty, record.kind != .ritual { Text(message).textSelection(.enabled) }
                if let notes = record.payload.notes, !notes.isEmpty, record.kind != .ritual { Text(notes).textSelection(.enabled) }
                if editable { Button("Bearbeiten", systemImage: "pencil") { editing = true }.buttonStyle(.borderedProminent) }
            }.padding(20)
        }.navigationTitle(record.kind == .poop ? "Drop-Poop" : record.payload.title ?? "Für euch")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) {
                switch record.kind {
                case .note: NoteEditorView(record: record)
                case .reminder: ReminderEditorView(record: record)
                case .calendar: CalendarEditorView(record: record)
                default: PlannerEditor(initial: record, initialDate: .now)
                }
            }
    }
}
