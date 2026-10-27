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
                    ForEach($draft.tabs) { $tab in
                        VStack(alignment:.leading,spacing:8) {
                            TextField("Beschriftung",text:$tab.title)
                            Picker("Öffnet",selection:$tab.action) {
                                ForEach(HomeQuickAction.allCases.filter { action in action == tab.action || !draft.tabs.contains { $0.action == action } }) { action in Label(action.title,systemImage:action.symbol).tag(action) }
                            }
                        }
                    }.onMove { draft.tabs.move(fromOffsets:$0,toOffset:$1) }.onDelete { offsets in if draft.tabs.count-offsets.count > 0 { draft.tabs.remove(atOffsets:offsets) } }
                    if draft.tabs.count < 5 {
                        Menu("Schaltfläche hinzufügen",systemImage:"plus.circle") {
                            ForEach(HomeQuickAction.allCases.filter { action in !draft.tabs.contains { $0.action == action } }) { action in
                                Button(action.title,systemImage:action.symbol) { draft.tabs.append(HomeShortcut(action:action)) }
                            }
                        }
                    }
                } header: { Text("Navigation unten · bis zu fünf") } footer: { Text("Eine bis fünf Schaltflächen für beliebige Bereiche. Kino bleibt über Schnellzugriffe, Karten und die Einstellungen erreichbar. Profil und Einstellungen findest du auch über das Personensymbol.") }
                Section {
                    ForEach($draft.shortcuts) { $shortcut in
                        VStack(alignment:.leading,spacing:8){
                            TextField("Name des Buttons",text:$shortcut.title).accessibilityIdentifier("shortcut-title-"+shortcut.id)
                            Picker("Öffnet",selection:$shortcut.action){ForEach(HomeQuickAction.allCases){action in Label(action.title,systemImage:action.symbol).tag(action)}}
                        }.padding(.vertical,4)
                    }.onMove{draft.shortcuts.move(fromOffsets:$0,toOffset:$1)}.onDelete{draft.shortcuts.remove(atOffsets:$0)}
                    if draft.shortcuts.count<12 {Menu("Schnellzugriff hinzufügen",systemImage:"plus.circle"){ForEach(HomeQuickAction.allCases){action in Button(action.title,systemImage:action.symbol){draft.shortcuts.append(HomeShortcut(action:action))}}}}
                } header:{Text("Kleine Schnellzugriffe")} footer:{Text("Bis zu zwölf Buttons direkt oben auf deiner Startseite. Namen frei ändern, verschieben oder entfernen. Jeder von euch hat seine eigene Auswahl.")}
                Section {
                    ForEach($draft.actions) { $shortcut in
                        VStack(alignment:.leading,spacing:8) {
                            TextField("Name des Buttons",text:$shortcut.title)
                            Picker("Öffnet",selection:$shortcut.action) {ForEach(HomeQuickAction.allCases) {action in Label(action.title,systemImage:action.symbol).tag(action)}}
                        }
                    }.onMove {draft.actions.move(fromOffsets:$0,toOffset:$1)}.onDelete {draft.actions.remove(atOffsets:$0)}
                    if draft.actions.count < 12 {Menu("Schnellaktion hinzufügen",systemImage:"plus.circle") {ForEach(HomeQuickAction.allCases) {action in Button(action.title,systemImage:action.symbol) {draft.actions.append(HomeShortcut(action:action))}}}}
                } header:{Text("Buttons in der Schnellaktionen-Karte")} footer:{Text("Auch die bisherigen vier festen Aktionen sind jetzt frei bearbeitbar. Die gesamte Karte lässt sich unten entfernen oder verschieben.")}
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
                            .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.title.count > 80 || (draft.shortcuts + draft.tabs + draft.actions).contains{$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || $0.title.count>24})
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
