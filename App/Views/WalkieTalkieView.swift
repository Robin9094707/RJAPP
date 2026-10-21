import SwiftUI

struct WalkieTalkieView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressed = false
    @State private var text = ""
    @State private var sending = false
    private var radio: WalkieTalkieService { app.radio }
    var body: some View {
        @Bindable var radio = app.radio
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 18) {
                    LoveEyebrow(text: "Eure private Frequenz")
                    Text("Sag’s mir ganz nah.").font(.system(size: 34, weight: .medium, design: .serif)).multilineTextAlignment(.center)
                    Text(radio.status).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ZStack {
                        ForEach(0..<3) { index in
                            Circle().stroke(LovePalette.violet.opacity(0.12), lineWidth: 2)
                                .frame(width: CGFloat(150 + index * 34), height: CGFloat(150 + index * 34))
                                .scaleEffect((radio.transmitting || radio.receiving) && !reduceMotion ? 1.06 : 1)
                        }
                        Circle().fill(LinearGradient(colors: [radio.transmitting ? LovePalette.pink : LovePalette.violet, LovePalette.pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 148, height: 148).shadow(color: LovePalette.violet.opacity(0.28), radius: 25, y: 12)
                            .overlay { Image(systemName: radio.receiving ? "speaker.wave.2.fill" : "mic.fill").font(.system(size: 46)).foregroundStyle(.white).symbolEffect(.variableColor, isActive: radio.transmitting || radio.receiving) }
                            .overlay { Circle().stroke(.white.opacity(0.45), lineWidth: 1.5) }
                            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                                guard !pressed, radio.enabled, !radio.connecting, !radio.receiving else { return }
                                pressed = true; radio.beginTalking()
                            }.onEnded { _ in pressed = false; radio.finishTalking() })
                            .accessibilityElement().accessibilityLabel("Zum Sprechen gedrückt halten")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { if radio.transmitting { radio.finishTalking() } else { radio.beginTalking() } }
                    }.frame(maxWidth: .infinity).frame(height: 245)
                    Text(radio.receiving ? "Hör zu. Dein Lieblingsmensch ist dran." : radio.transmitting ? "Du bist auf Sendung. 💗" : "Gedrückt halten. Sprechen. Loslassen.")
                        .font(.headline).multilineTextAlignment(.center)
                    Text("Bis zu 30 Sekunden pro Durchsage. Audioteile werden während des Sprechens über euren Server übertragen. Bei langsamer Verbindung kann es Verzögerungen geben.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(radio.enabled ? "Kanal verlassen" : "Walkie-Talkie einschalten", systemImage: radio.enabled ? "pause.circle" : "antenna.radiowaves.left.and.right") {
                        Task { if radio.enabled { radio.disable() } else { await radio.enable(api: app.api) } }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(radio.connecting)
                    if radio.transmitting { Button("Sprechen beenden") { pressed = false; radio.finishTalking() }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity).loveCard()
                if let error = radio.errorMessage { Label(error, systemImage: "exclamationmark.bubble").font(.footnote).foregroundStyle(.orange).loveCard() }
                VStack(alignment: .leading, spacing: 16) {
                    Label("Worte mit deiner Nähe", systemImage: "text.bubble.fill").font(.headline)
                    Text("Schick einen Satz. Wenn Vorlesen beim anderen eingeschaltet ist, spricht das iPhone ihn laut aus.").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Ich freu mich auf dich …", text: $text, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Text("\(text.count)/600").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            sending = true
                            Task { if await radio.sendText(text.trimmingCharacters(in: .whitespacesAndNewlines)) { text = "" }; sending = false }
                        } label: { Label(sending ? "Sendet …" : "Zum Vorlesen senden", systemImage: "paperplane.fill") }
                        .buttonStyle(.borderedProminent).disabled(sending || !radio.enabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 600)
                    }
                }.loveCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("So höre ich dich", systemImage: "ear.badge.waveform").font(.headline)
                    Toggle("Eingehendes Audio automatisch abspielen", isOn: $radio.playIncoming)
                    Toggle("Funktexte laut vorlesen", isOn: $radio.speakTexts)
                    Button("Wiedergabe sofort stoppen", systemImage: "speaker.slash.fill") { radio.stopReceiving() }.buttonStyle(.bordered)
                    Text("Das kann auch bei gesperrtem Bildschirm laut werden. Empfang und Vorlesen kannst du jederzeit abschalten; das Mikrofon sendet nur mit der Sprechtaste.").font(.caption).foregroundStyle(.secondary)
                }.loveCard()
                if !radio.lastTexts.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Gerade angekommen").font(.headline)
                        ForEach(radio.lastTexts) { event in VStack(alignment: .leading, spacing: 4) { Text(event.speaker).font(.caption.bold()).foregroundStyle(LovePalette.violet); Text(event.text).font(.subheadline) } }
                    }.loveCard()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Systemkanal & Hintergrund", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
                    Label(radio.joinedSystem ? "iOS-Push-to-Talk-Kanal verbunden" : "Vordergrundbetrieb", systemImage: radio.joinedSystem ? "checkmark.circle.fill" : "info.circle")
                    Label(radio.backgroundPushConfigured ? "Server meldet APNs als konfiguriert" : "APNs auf dem Server noch nicht eingerichtet", systemImage: "server.rack")
                    if let message = radio.systemMessage { Text(message).foregroundStyle(.orange) }
                    Text("Apple zeigt den aktiven Kanal in der Systemsteuerung am oberen Bildschirmrand bzw. auf dem Sperrbildschirm. Verfügbarkeit und Platzierung bestimmt iOS. Hintergrundempfang braucht ein Signierprofil mit Push-to-Talk und Push sowie passende APNs-Schlüssel. Ohne diese bleibt der Funk bei geöffneter App nutzbar.")
                }.font(.footnote).foregroundStyle(.secondary).loveCard()
            }.padding(22)
        }.background(LoveBackground()).navigationTitle("Walkie-Talkie").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .spring(response: 0.4), value: radio.transmitting)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: radio.receiving)
            .onDisappear { pressed = false; radio.finishTalking() }
            .onChange(of: scenePhase) { _, phase in if phase == .inactive { pressed = false; radio.finishTalking() } }
    }
}
