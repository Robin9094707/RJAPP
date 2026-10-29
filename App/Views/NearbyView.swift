import SwiftUI

struct NearbyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .animation(reduceMotion ? nil:.easeOut(duration: 0.25), value: appState.nearby.angle)
                }.frame(height: 270)
                if appState.nearby.cameraRequested {
                    HStack(spacing:14){Image(systemName:"viewfinder").font(.largeTitle).foregroundStyle(LovePalette.cyan);VStack(alignment:.leading,spacing:6){Text(appState.nearby.cameraActive ? "iOS kalibriert euren Pfeil":"Kamera-Unterstützung wird gestartet").font(.headline);Text("Ein Gerät ruhig halten. Das suchende iPhone langsam bewegen. Die Kamera dient nur der Raumkalibrierung; es werden keine Bilder gespeichert oder geteilt.").font(.caption).foregroundStyle(.secondary)}}.loveCard()
                }
                if !appState.nearby.supportsDirectDirection {Label(appState.nearby.supportsCamera ? "Dieses iPhone nutzt für den Pfeil die Kamera-Unterstützung.":"Dieses Gerät kann nur die Entfernung anzeigen.",systemImage:"info.circle").font(.caption).foregroundStyle(.secondary)}
                if !appState.nearby.coaching.isEmpty {Label(appState.nearby.coaching,systemImage:appState.nearby.cameraActive ? "viewfinder":"info.circle").font(.subheadline).foregroundStyle(.secondary)}
                HStack{Label("Gegenüber",systemImage:appState.nearby.peerDiscovered ? "checkmark.circle.fill":"clock");Spacer();Label("Messsignal",systemImage:appState.nearby.distance != nil ? "checkmark.circle.fill":"dot.radiowaves.left.and.right")}.font(.caption).foregroundStyle(.secondary)
                if let distance = appState.nearby.distance {
                    Text(String(format: "%.1f m", distance)).font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                    Text("zu \(appState.partner?.displayName ?? "deinem Lieblingsmenschen")").foregroundStyle(.secondary)
                }
                if !appState.nearby.heightHint.isEmpty {Label(appState.nearby.heightHint,systemImage:"arrow.up.arrow.down").font(.headline)}
                else if let elevation=appState.nearby.elevation,abs(elevation)>20 {Label(elevation>0 ? "Etwas höher suchen":"Etwas tiefer suchen",systemImage:elevation>0 ? "arrow.up":"arrow.down").font(.headline)}
                if appState.nearby.running,appState.nearby.angle == nil {Text("Noch kein Richtungswert von iOS. Ein Pfeil erscheint erst bei einem echten Signal.").font(.caption).foregroundStyle(.secondary)}
                Text(appState.nearby.stage).font(.caption.bold()).foregroundStyle(LovePalette.violet)
                Text(appState.nearby.message).multilineTextAlignment(.center).font(.headline).frame(minHeight: 60)
                Toggle("Automatisch bereit, wenn RJ Love geöffnet ist",isOn:Binding(get:{appState.nearby.automaticSearch},set:{value in appState.nearby.automaticSearch=value;if value{Task{await appState.refreshNearbySearch()}}else{appState.nearby.stop(api:appState.api)}}))
                Toggle("Mit Live-Aktivität im Hintergrund weitersuchen", isOn: Binding(get: { appState.nearby.backgroundSearch }, set: { appState.nearby.backgroundSearch = $0 }))
                Text("Öffnet RJ Love auf beiden iPhones: Die automatische Nahsuche ist auch außerhalb dieser Ansicht bereit. Eine bestehende Verbindung kann beim Sperren oder App-Wechsel bis zu 15 Minuten mit sichtbarer Live-Aktivität weiterlaufen. Nach vollständigem Beenden der App beide Apps wieder öffnen.").font(.caption).foregroundStyle(.secondary)
                Toggle("Kamera-Unterstützung für den Richtungspfeil",isOn:Binding(get:{appState.nearby.cameraAssistance},set:{appState.nearby.setCameraAssistance($0)})).disabled(!appState.nearby.supportsCamera)
                Text("iOS übernimmt die Kamerakalibrierung direkt. Ein iPhone bleibt ruhig, das suchende Gerät langsam seitlich und auf/ab bewegen. Bei Kamerafehlern wird nur die Entfernung weitergesucht; es werden keine Bilder gespeichert oder geteilt.").font(.caption).foregroundStyle(.secondary)
                Button(appState.nearby.running ? "Suche beenden" : "Nahbereichssuche starten", systemImage: "dot.radiowaves.left.and.right") {
                    if appState.nearby.running { appState.nearby.pauseAutomaticSearch(api: appState.api) }
                    else { Task {await appState.nearby.start(api: appState.api)} }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!appState.nearby.supported)
                DisclosureGroup("Verbindung prüfen & Diagnose") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Die Standortkarte und UWB sind getrennte Funktionen. Ein fehlender Token beweist keine verweigerte Freigabe. Für den Pfeil Kamera-Unterstützung aktivieren; zuerst ohne Hintergrundoption auf beiden Geräten testen.").font(.subheadline)
                        Text("Bluetooth einschalten, Flugmodus ausschalten und beide Apps sichtbar halten. UWB hängt zusätzlich von Hardware, Region und iOS-Systemzustand ab.").font(.caption).foregroundStyle(.secondary)
                        Text(appState.nearby.diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item:appState.nearby.diagnostics){Label("Diagnose teilen",systemImage:"square.and.arrow.up")}
                        Button("App-Einstellungen öffnen"){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
                    }.padding(.top,10)
                }.loveCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Öffnet beide RJ Love. Bei aktivierter Automatik müsst ihr diese Ansicht nicht extra öffnen.", systemImage: "person.2.fill")
                    Label("Die Suche nutzt Ultra-Breitband im Nahbereich. Haltet beide iPhones aufrecht und richtet ihre Rückseiten zueinander.", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Ohne Hintergrundoption pausiert die Suche beim App-Wechsel. Hintergrundsuche und Token-Freigabe sind auf ein kurzes Suchfenster ausgelegt. Die automatische Bereitschaft lässt sich jederzeit ausschalten.", systemImage: "hand.raised.fill")
                }.font(.footnote).foregroundStyle(.secondary).loveCard()
            }.padding(24)
        }.background(LoveBackground()).navigationTitle("Dich finden").navigationBarTitleDisplayMode(.inline)
        .onAppear{appState.nearby.setVisible(true);Task{await appState.refreshNearbySearch()}}
        .onDisappear{appState.nearby.setVisible(false)}
    }
}

