import SwiftUI

struct HomeEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HomeLayout.standard
    @State private var revision = 0
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Deine Startseite") {
                    TextField("Überschrift", text: $draft.title).accessibilityIdentifier("home-edit-title")
                    Picker("Farbwelt", selection: $draft.theme) {
                        Text("Rosé").tag("rose"); Text("Lavendel").tag("violet"); Text("Meer").tag("ocean")
                    }
                }
                Section {
                    ForEach($draft.cards) { $card in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(card.kind.title, systemImage: card.kind.symbol).font(.headline)
                            Picker("Größe für \(card.kind.title)", selection: $card.size) {
                                Text("Kompakt").tag(HomeCardSize.compact)
                                Text("Groß").tag(HomeCardSize.large)
                            }.pickerStyle(.segmented)
                        }.padding(.vertical, 5)
                    }.onMove { draft.cards.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { draft.cards.remove(atOffsets: $0) }
                } header: { Text("Deine Karten") } footer: { Text("Mit dem Griff rechts verschieben. Mit Minus ausblenden. Die Reihenfolge und Größen gehören nur zu deinem Zugang.") }
                Section("Karten hinzufügen") {
                    ForEach(HomeCardKind.allCases.filter { kind in !draft.cards.contains { $0.kind == kind } }) { kind in
                        Button { draft.cards.append(HomeCard(kind: kind)) } label: { Label(kind.title, systemImage: "plus.circle.fill") }
                            .accessibilityIdentifier("home-add-" + kind.rawValue)
                    }
                }
                Section {
                    Button("Standardanordnung wiederherstellen") { draft = .standard }
                    Text("Speichern überträgt deine Startseite auf euren eigenen Server. Beim erneuten Anmelden wird sie wiederhergestellt.").font(.footnote).foregroundStyle(.secondary)
                    if let error {
                        Text(error).foregroundStyle(.orange)
                        Button("Gespeicherte Startseite neu laden") { Task { await reload() } }
                    }
                }
            }.environment(\.editMode, .constant(.active)).disabled(saving)
                .navigationTitle("Meine Startseite").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Speichert …" : "Speichern") { Task { await save() } }
                            .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.title.count > 80)
                            .accessibilityIdentifier("home-layout-save")
                    }
                }.interactiveDismissDisabled(saving)
                .onAppear { draft = app.homeLayout; revision = app.homeRevision }
        }
    }
    private func reload() async {
        do { let value = try await app.api.preferences(); app.applyPreferences(value); draft = value.dashboard; revision = value.revision; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let value = try await app.api.savePreferences(draft, revision: revision)
            app.applyPreferences(value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
extension APIClient {
    func preferences() async throws -> UserPreferences {
        try await execute(try request(path: "/v1/preferences", method: "GET"), as: UserPreferences.self)
    }
    func savePreferences(_ layout: HomeLayout, revision: Int) async throws -> UserPreferences {
        try await execute(try request(path: "/v1/preferences", method: "POST", body: encoder.encode(UserPreferences(dashboard: layout, revision: revision))), as: UserPreferences.self)
    }
}
