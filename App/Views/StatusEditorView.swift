import SwiftUI

struct StatusEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var hours = 2
    @State private var quiet = false
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("So geht es mir gerade") {
                    TextField("Dein Status", text:$text, axis:.vertical).lineLimit(2...4)
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack {
                            preset("😴", "Schlafe gerade")
                            preset("💗", "Denke an dich")
                            preset("🤗", "Brauche eine Umarmung")
                            preset("🎮", "Bin am Spielen")
                        }
                    }
                }
                Section("Für eine kleine Weile") {
                    Picker("Dauer", selection:$hours) {
                        Text("Bis ich es ändere").tag(0)
                        ForEach([1,2,4,8],id:\.self) { Text("\($0) Stunden").tag($0) }
                    }
                    Toggle("Bitte nicht stören",isOn:$quiet)
                        .onChange(of:quiet) { _,value in if value && hours == 0 { hours=8 } }
                    Text("Bis zu acht Stunden Ruhe vor normalen RJ-Love-Mitteilungen. Bewusst gesendete Weckrufe bleiben möglich. Dein iOS-Fokus wird nicht verändert.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Status entfernen",role:.destructive) { save(clear:true) }.disabled(saving)
                }
            }.navigationTitle("Mein Status").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button(saving ? "Speichert …":"Teilen") { save() }.disabled(saving || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>120) }
                }
        }.presentationDetents([.medium,.large])
            .onAppear {
                text=app.myStatus == nil ? app.statusMessage:(app.myStatus?.visibleStatus ?? "")
                quiet=app.myStatus?.isQuiet ?? false
            }
    }
    private func preset(_ emoji:String,_ value:String)->some View {
        Button(emoji+" "+value) { text=emoji+" "+value }.buttonStyle(.bordered)
    }
    private func save(clear:Bool=false) {
        saving=true
        Task { if await app.setStatus(text:clear ? "":text,hours:clear ? 0:hours,quiet:clear ? false:quiet) { dismiss() }; saving=false }
    }
}
