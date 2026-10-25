import Observation
import SwiftUI

@MainActor @Observable final class MomentDeletion {
    var record: SharedRecord?
    var busy = false
    var error: String?
    func request(_ record: SharedRecord) { guard !busy else { return }; self.record = record }
    func delete(_ record: SharedRecord, app: AppState, completed: @escaping (SharedRecord) -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await app.removeRecord(record); completed(record) }
        catch { self.error = error.localizedDescription }
    }
}
private struct MomentDeletionPrompt: ViewModifier {
    @Environment(AppState.self) private var app
    let deletion: MomentDeletion
    let completed: (SharedRecord) -> Void
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Moment für euch beide löschen?",isPresented: Binding(get: { deletion.record != nil },set: { if !$0 { deletion.record = nil } }),titleVisibility: .visible,presenting: deletion.record) { record in
                Button("Moment für beide löschen",role: .destructive) { Task { await deletion.delete(record,app: app,completed: completed) } }
                Button("Behalten",role: .cancel) { deletion.record = nil }
            } message: { record in
                Text("Dieser Moment wird aus eurer gemeinsamen Galerie und den Alben entfernt. Bereits in Apple Fotos gesicherte Kopien bleiben erhalten. Das lässt sich nicht rückgängig machen.")
            }
            .alert("Moment konnte nicht gelöscht werden",isPresented: Binding(get: { deletion.error != nil },set: { if !$0 { deletion.error = nil } })) {
                Button("OK",role: .cancel) { deletion.error = nil }
            } message: { Text(deletion.error ?? "Bitte erneut versuchen.") }
            .overlay(alignment: .top) {
                if deletion.busy { ProgressView("Moment wird gelöscht …").padding(14).background(.regularMaterial,in: Capsule()).padding() }
            }
            .interactiveDismissDisabled(deletion.busy)
    }
}
extension View {
    func momentDeletionPrompt(_ deletion: MomentDeletion, completed: @escaping (SharedRecord) -> Void = { _ in }) -> some View { modifier(MomentDeletionPrompt(deletion: deletion,completed: completed)) }
}
