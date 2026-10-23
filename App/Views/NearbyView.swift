import SwiftUI
import ARKit

struct NearbyView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                LoveEyebrow(text: "Einander finden")
                Text("Ein Stück näher.").font(.system(size: 36, weight: .medium, design: .serif))
                ZStack {
                    ForEach(0..<4) { i in
                        Circle().stroke(LovePalette.cyan.opacity(0.18), lineWidth: 1).frame(width: CGFloat(110 + 46 * i), height: CGFloat(110 + 46 * i))
                    }
                    Image(systemName: appState.nearby.angle == nil ? "heart.fill" : "location.north.fill")
                        .font(.system(size: 68)).foregroundStyle(LovePalette.cyan.gradient)
                        .rotationEffect(.degrees(appState.nearby.angle ?? 0))
                        .animation(.easeOut(duration: 0.25), value: appState.nearby.angle)
                }.frame(height: 270)
                if appState.nearby.cameraActive,let session=appState.nearby.arSession {NearbyCameraPreview(session:session).frame(height:190).clipShape(RoundedRectangle(cornerRadius:22)).accessibilityLabel("Sichtbare Kamera zur Raumkalibrierung")}
                if !appState.nearby.coaching.isEmpty {Label(appState.nearby.coaching,systemImage:appState.nearby.cameraActive ? "viewfinder":"info.circle").font(.subheadline).foregroundStyle(.secondary)}
                HStack{Label("Gegenüber",systemImage:appState.nearby.peerDiscovered ? "checkmark.circle.fill":"clock");Spacer();Label("Messsignal",systemImage:appState.nearby.distance != nil ? "checkmark.circle.fill":"dot.radiowaves.left.and.right")}.font(.caption).foregroundStyle(.secondary)
                if let distance = appState.nearby.distance {
                    Text(String(format: "%.1f m", distance)).font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                    Text("zu \(appState.partner?.displayName ?? "deinem Lieblingsmenschen")").foregroundStyle(.secondary)
                }
                if let elevation=appState.nearby.elevation,abs(elevation)>20 {Label(elevation>0 ? "Etwas höher suchen":"Etwas tiefer suchen",systemImage:elevation>0 ? "arrow.up":"arrow.down").font(.headline)}
                if appState.nearby.running,appState.nearby.angle == nil {Text("Noch kein Richtungswert von iOS. Ein Pfeil erscheint erst bei einem echten Signal.").font(.caption).foregroundStyle(.secondary)}
                Text(appState.nearby.message).multilineTextAlignment(.center).font(.headline).frame(minHeight: 60)
                Toggle("Mit Live-Aktivität im Hintergrund weitersuchen", isOn: Binding(get: { appState.nearby.backgroundSearch }, set: { appState.nearby.backgroundSearch = $0 })).disabled(appState.nearby.running)
                Text("Startet die Suche einmal auf beiden iPhones. Danach kann die bereits aktive Suche bis zu 15 Minuten mit sichtbarer Live-Aktivität beim Sperren oder App-Wechsel weiterlaufen. Bei beendeter App oder beendetem Signal bitte beide wieder öffnen.").font(.caption).foregroundStyle(.secondary)
                Toggle("Kamera-Unterstützung für den Richtungspfeil",isOn:Binding(get:{appState.nearby.cameraAssistance},set:{appState.nearby.cameraAssistance=$0})).disabled(appState.nearby.running)
                Text("Optional: Sichtbare Kamera für die Raumkalibrierung. Ein iPhone ruhig halten und das suchende Gerät langsam bewegen. Bei Problemen wird ohne Kamera weitergesucht. Keine Bilder werden gespeichert oder geteilt.").font(.caption).foregroundStyle(.secondary)
                Button(appState.nearby.running ? "Suche beenden" : "Nahbereichssuche starten", systemImage: "dot.radiowaves.left.and.right") {
                    if appState.nearby.running { appState.nearby.stop(api: appState.api) }
                    else { Task {await appState.nearby.start(api: appState.api)} }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!appState.nearby.supported)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Öffnet beide diese Ansicht und startet die Suche.", systemImage: "person.2.fill")
                    Label("Die Suche nutzt Ultra-Breitband im Nahbereich. Haltet beide iPhones aufrecht und richtet ihre Rückseiten zueinander.", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Ohne Hintergrundoption endet die Suche beim Verlassen der Ansicht. Mit Live-Aktivität enden Suche und Suchfreigabe spätestens nach 15 Minuten.", systemImage: "hand.raised.fill")
                }.font(.footnote).foregroundStyle(.secondary).loveCard()
            }.padding(24)
        }.background(LoveBackground()).navigationTitle("Dich finden").navigationBarTitleDisplayMode(.inline)
        .onAppear{appState.nearby.setVisible(true)}
        .onDisappear{appState.nearby.setVisible(false)}
    }
}

private struct NearbyCameraPreview:UIViewRepresentable {
    let session:ARSession
    func makeUIView(context:Context)->ARSCNView {let view=ARSCNView(frame:.zero);view.session=session;view.scene=SCNScene();view.automaticallyUpdatesLighting=true;return view}
    func updateUIView(_ view:ARSCNView,context:Context){if view.session !== session {view.session=session}}
}
