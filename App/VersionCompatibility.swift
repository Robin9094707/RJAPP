import Foundation
import SwiftUI

struct ServerCompatibility: Decodable {
    let version: String
    let minimumAppVersion: String?
    let minimumProtocol: Int?
    let maximumProtocol: Int?
    enum CodingKeys: String, CodingKey {
        case version
        case minimumAppVersion = "minimum_app_version", minimumProtocol = "minimum_protocol", maximumProtocol = "maximum_protocol"
    }
}
struct UpdateRequirement: Error, LocalizedError, Equatable {
    let target: String
    let message: String
    var errorDescription: String? { message }
}
enum RJVersion {
    static let minimumServer = "5.0.0"
    static let protocolVersion = 5
    static var app: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0" }
    static func older(_ lhs: String, than rhs: String) -> Bool {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        guard a.count == 3, b.count == 3 else { return true }
        return a.lexicographicallyPrecedes(b)
    }
    static func requirement(_ info: ServerCompatibility) -> UpdateRequirement? {
        if older(info.version, than: minimumServer) || info.minimumProtocol == nil || info.maximumProtocol == nil {
            return UpdateRequirement(target: "server", message: "Dein Python-Server ist \(info.version). Diese App \(app) benötigt mindestens Server \(minimumServer). Ersetze die Python-Datei aus dem aktuellen Komplettpaket und starte den Server neu. Konfiguration und Datenordner behalten.")
        }
        if older(app, than: info.minimumAppVersion ?? minimumServer) || (info.minimumProtocol ?? 0) > protocolVersion {
            return UpdateRequirement(target: "app", message: "Bitte die App aktualisieren. Der Server \(info.version) benötigt mindestens App \(info.minimumAppVersion ?? info.version). Lade die neue IPA und signiere sie wie bisher in Feather.")
        }
        if (info.maximumProtocol ?? 0) < protocolVersion {
            return UpdateRequirement(target: "server", message: "Der Server unterstützt diese App-Generation noch nicht. Bitte die Python-Datei aus demselben Komplettpaket verwenden.")
        }
        return nil
    }
}
@MainActor final class UpdateCoordinator: ObservableObject {
    static let shared = UpdateCoordinator()
    @Published var requirement: UpdateRequirement?
}
struct UpdateRequiredView: View {
    @Environment(AppState.self) private var app
    @ObservedObject private var update = UpdateCoordinator.shared
    @State private var showingUpdater=false
    @State private var checking = false
    @State private var error: String?
    private var serverUpdate: Bool { update.requirement?.target == "server" }
    var body: some View {
        ZStack {
            LoveBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: serverUpdate ? "server.rack" : "arrow.down.app.fill")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(LovePalette.dusk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .symbolEffect(.bounce, value: checking)
                    LoveEyebrow(text: "Gemeinsam auf dem neuesten Stand")
                    Text(serverUpdate ? "Ein Update für euren Server." : "Zeit für die neue App.").font(.loveDisplay(32))
                    Text(update.requirement?.message ?? "App und Server bitte gemeinsam aktualisieren.").font(.body)
                    Label("Eure Aufnahmen und Anmeldungen bleiben erhalten. Währenddessen werden keine inkompatiblen Änderungen gesendet.", systemImage: "lock.shield.fill").font(.footnote).foregroundStyle(.secondary)
                    if !serverUpdate {
                        Button("IPA abrufen & mit Feather aktualisieren",systemImage:"arrow.down.app.fill"){showingUpdater=true}
                            .buttonStyle(.glassProminent).controlSize(.large).frame(maxWidth: .infinity)
                    }
                    Link(destination: URL(string: "https://github.com/Robin9094707/RJAPP/actions")!) {
                        Label("Aktuelles Komplettpaket auf GitHub", systemImage: "shippingbox.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                    Button {
                        checking = true
                        Task {
                            do { try await app.api.checkCompatibility(); update.requirement = nil; _ = await app.syncNow() }
                            catch { self.error = error.localizedDescription }
                            checking = false
                        }
                    } label: {
                        HStack { if checking { ProgressView().controlSize(.small) }; Text(checking ? "Prüfe …" : "Nach dem Update erneut prüfen") }.frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).disabled(checking)
                    if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }.loveCard().padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }.accessibilityIdentifier("rj-update-required").sheet(isPresented:$showingUpdater){NavigationStack{AppUpdateView().toolbar{ToolbarItem(placement:.cancellationAction){Button("Zurück"){showingUpdater=false}}}}}
    }
}
