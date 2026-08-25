import SwiftUI

struct DebugConsoleView: View {
    @State private var logger = DebugLogger.shared
    @State private var clearConfirmation = false

    var body: some View {
        List {
            if logger.entries.isEmpty {
                ContentUnavailableView("Keine Einträge", systemImage: "checkmark.circle", description: Text("Im Moment sind keine Diagnosemeldungen gespeichert."))
            }
            ForEach(logger.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.category).font(.caption.bold()).foregroundStyle(LovePalette.cyan)
                        Spacer()
                        Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("Debug-Konsole")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                Button(role: .destructive) { clearConfirmation = true } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("Diagnoseeinträge löschen?", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { logger.clear() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var exportText: String {
        logger.entries.map {
            "[\($0.timestamp.formatted(.iso8601))] \($0.category): \($0.message)"
        }.joined(separator: "\n")
    }
}
