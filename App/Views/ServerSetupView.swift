import SwiftUI

struct ServerSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image("BrandMark").resizable().scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: LovePalette.pink.opacity(0.25), radius: 20, y: 8)
                    Text("RJ Love")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Euer privater Ort für Nähe, Momente und Alltag.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    TextField("Server · z. B. https://liebe.example.de", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    TextField("Benutzername", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)

                    if normalizedPreview.hasPrefix("http://") {
                        Label("HTTP ist nur im vertrauenswürdigen Heimnetz sinnvoll. Für Internetzugriff bitte HTTPS verwenden.", systemImage: "exclamationmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        isWorking = true
                        Task {
                            await appState.login(server: server, username: username, password: password)
                            isWorking = false
                        }
                    } label: {
                        HStack {
                            if isWorking { ProgressView().tint(.white) }
                            Label("Privat verbinden", systemImage: "lock.heart.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty || isWorking)
                }
                .loveCard()

                Label("Passwort und Sitzungstoken bleiben im iOS-Schlüsselbund. Eure Inhalte liegen ausschließlich auf deinem eigenen Server.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            server = appState.profile?.baseURL ?? ""
            username = appState.profile?.username ?? ""
        }
    }

    private var normalizedPreview: String {
        server.contains("://") ? server.lowercased() : "http://\(server.lowercased())"
    }
}
