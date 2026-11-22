import SwiftUI

/// "Funk": hold the big button, speak, let go. The other iPhone plays it out loud as soon as
/// RJ Love is open and quiet mode is off. Works with any sideloaded build; no special entitlement.
struct WalkieView: View {
    @Environment(AppState.self) private var app
    @State private var walkie = WalkieService.shared
    @State private var holding = false
    @State private var cancelZone = false
    @State private var deleting: WalkieMessage?
    private var partnerName: String { app.partner?.displayName ?? "Dein Lieblingsmensch" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    header
                    if walkie.messages.isEmpty {
                        ContentUnavailableView("Noch kein Funk", systemImage: "antenna.radiowaves.left.and.right",
                                               description: Text("Halte unten die Taste gedrückt und sag etwas Liebes. \(partnerName) hört es, sobald RJ Love offen ist."))
                            .padding(.top, 30)
                    }
                    ForEach(walkie.messages) { message in
                        WalkieBubble(message: message, mine: message.senderID == app.me?.id, partnerName: partnerName)
                            .id(message.id)
                            .contextMenu {
                                Button("Abspielen", systemImage: "play.fill") { Task { await walkie.play(message) } }
                                if message.senderID == app.me?.id {
                                    Button("Für beide zurückrufen", systemImage: "trash", role: .destructive) { deleting = message }
                                }
                            }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, LoveMetrics.screenPadding).padding(.vertical, 12)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: walkie.messages.count) { _, _ in withAnimation(LoveMotion.gentle) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { talkBar }
        .background(LoveBackground())
        .navigationTitle("Funk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Beim Öffnen automatisch abspielen", systemImage: "play.circle", isOn: Binding(get: { walkie.autoplay }, set: { walkie.autoplay = $0 }))
                    Toggle("Laut abspielen", systemImage: "speaker.wave.3.fill", isOn: Binding(get: { walkie.loud }, set: { walkie.loud = $0 }))
                    Toggle("Funk-Klick beim Sprechen", systemImage: "waveform", isOn: Binding(get: { walkie.roger }, set: { walkie.roger = $0 }))
                } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Funk einstellen")
            }
        }
        .task { walkie.attach(app); walkie.refresh() }
        .confirmationDialog("Funknachricht zurückrufen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Für beide zurückrufen", role: .destructive) { if let deleting { Task { await walkie.delete(deleting) } }; deleting = nil }
            Button("Behalten", role: .cancel) { deleting = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                PartnerAvatar(name: partnerName, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(partnerName).font(.headline)
                    HStack(spacing: 6) {
                        LovePulseDot(color: walkie.connected ? .green : .orange)
                        Text(walkie.connected ? (partnerOnline ? "Gerade in RJ Love · hört sofort" : "Live verbunden") : "Verbinde …")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if app.myStatus?.isQuiet == true {
                    Label("Ruhe", systemImage: "moon.fill").font(.caption.weight(.semibold)).foregroundStyle(LovePalette.violet)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(LovePalette.violet.opacity(0.12), in: Capsule())
                }
            }
            Text(walkie.autoplay ? "Neue Nachrichten spielen laut, sobald die App offen ist – außer im Ruhemodus." : "Automatisches Abspielen ist aus. Tippe eine Nachricht an, um sie zu hören.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .loveCard()
        .padding(.bottom, 6)
    }

    private var partnerOnline: Bool {
        guard let presence = app.partner?.presence, presence.appState == "foreground",
              let seen = (presence.updatedAt ?? presence.reportedAt)?.rjDate else { return false }
        return Date.now.timeIntervalSince(seen) < 120
    }

    private var talkBar: some View {
        VStack(spacing: 10) {
            if let error = walkie.error {
                Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .onTapGesture { walkie.error = nil }
            }
            Text(statusLine).font(.footnote.weight(.semibold)).foregroundStyle(cancelZone ? .red : .secondary)
                .monospacedDigit().contentTransition(.numericText())
            talkButton
        }
        .padding(.horizontal, LoveMetrics.screenPadding).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var statusLine: String {
        if walkie.sending { return "Wird gefunkt …" }
        if walkie.recording {
            if cancelZone { return "Loslassen zum Verwerfen" }
            let seconds = Int(walkie.recordDuration)
            return String(format: "%d:%02d · nach oben ziehen zum Abbrechen", seconds / 60, seconds % 60)
        }
        return "Gedrückt halten und sprechen"
    }

    private var talkButton: some View {
        let active = walkie.recording
        return ZStack {
            Circle().fill(LovePalette.pink.opacity(0.18))
                .frame(width: 112, height: 112)
                .scaleEffect(active ? 1 + walkie.level * 0.35 : 1)
                .animation(.easeOut(duration: 0.08), value: walkie.level)
            Image(systemName: active ? "waveform" : "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Circle().fill(cancelZone ? AnyShapeStyle(Color.red) : AnyShapeStyle(LovePalette.heart)))
                .glassEffect(.regular.tint(LovePalette.pink.opacity(0.25)).interactive(), in: Circle())
                .shadow(color: LovePalette.pink.opacity(0.35), radius: active ? 18 : 10, y: 6)
                .scaleEffect(holding ? 0.94 : 1)
                .animation(LoveMotion.snappy, value: holding)
        }
        .frame(height: 118)
        .contentShape(Circle())
        .opacity(walkie.sending ? 0.5 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !holding {
                        holding = true; cancelZone = false
                        Task {
                            await walkie.beginRecording()
                            if !holding { await walkie.finishRecording() }
                        }
                    }
                    let shouldCancel = value.translation.height < -90
                    if shouldCancel != cancelZone { cancelZone = shouldCancel; Haptics.selection() }
                }
                .onEnded { _ in
                    holding = false
                    if cancelZone { walkie.cancelRecording(); cancelZone = false }
                    else if walkie.recording { Task { await walkie.finishRecording() } }
                }
        )
        .disabled(walkie.sending)
        .accessibilityElement()
        .accessibilityLabel(active ? "Aufnahme läuft. Doppeltippen zum Senden" : "Funk aufnehmen")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Task { if walkie.recording { await walkie.finishRecording() } else { await walkie.beginRecording() } }
        }
        .accessibilityIdentifier("walkie-talk")
    }
}

private struct WalkieBubble: View {
    @State private var walkie = WalkieService.shared
    let message: WalkieMessage
    let mine: Bool
    let partnerName: String
    private var playing: Bool { walkie.playingID == message.id }
    var body: some View {
        HStack {
            if mine { Spacer(minLength: 48) }
            Button { Task { await walkie.play(message) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(mine ? LovePalette.pink : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(mine ? AnyShapeStyle(Color.white) : AnyShapeStyle(LovePalette.pink)))
                    WalkieWave(seed: message.id, progress: playing ? walkie.playProgress : 0, tint: mine ? .white : LovePalette.pink)
                        .frame(height: 26)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(durationText).font(.caption.weight(.semibold)).monospacedDigit()
                        Text(statusText).font(.caption2).opacity(0.8)
                    }
                    .foregroundStyle(mine ? .white : .secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: 300)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(mine ? AnyShapeStyle(LovePalette.heart) : AnyShapeStyle(LoveSurface.card))
                }
                .overlay(alignment: .topTrailing) {
                    if !mine && message.playedAt == nil && !playing {
                        Circle().fill(LovePalette.pink).frame(width: 10, height: 10).offset(x: 2, y: -2)
                            .accessibilityLabel("Neu")
                    }
                }
            }
            .buttonStyle(.lovePress)
            .accessibilityLabel((mine ? "Deine Funknachricht" : "Funk von \(partnerName)") + ", " + durationText + ", " + statusText)
            if !mine { Spacer(minLength: 48) }
        }
    }
    private var durationText: String {
        let seconds = max(1, Int(message.duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private var statusText: String {
        let time = message.createdAt.rjDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        if mine { return time + (message.playedAt != nil ? " · gehört" : " · gesendet") }
        return time
    }
}

/// A calm, deterministic waveform per message (no audio analysis needed).
private struct WalkieWave: View {
    let seed: String
    let progress: Double
    let tint: Color
    var body: some View {
        let bars = Self.bars(for: seed)
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(Double(index) / Double(bars.count) <= progress && progress > 0 ? 1 : 0.45))
                        .frame(width: max(2, (geometry.size.width - CGFloat(bars.count - 1) * 2.5) / CGFloat(bars.count)),
                               height: max(4, geometry.size.height * bars[index]))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
    static func bars(for seed: String) -> [CGFloat] {
        var value: UInt64 = 1469598103934665603
        for byte in seed.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return (0..<22).map { index in
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let random = CGFloat((value >> 33) % 1000) / 1000
            let envelope = sin(CGFloat(index) / 21 * .pi) * 0.55 + 0.35
            return min(1, max(0.15, envelope * (0.5 + random * 0.7)))
        }
    }
}

/// Compact home card: unheard count, last message and a quick way in.
struct WalkieHomeCard: View {
    @Environment(AppState.self) private var app
    @State private var walkie = WalkieService.shared
    var compact = false
    var body: some View {
        NavigationLink { WalkieView() } label: {
            HStack(spacing: 14) {
                LoveIcon(symbol: "antenna.radiowaves.left.and.right", tint: LovePalette.pink, size: compact ? 40 : 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Funk").font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !walkie.unheard.isEmpty {
                    Text("\(walkie.unheard.count)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(LovePalette.pink, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 14 : 18)
            .loveGlass(in: RoundedRectangle(cornerRadius: LoveMetrics.tileRadius + 2, style: .continuous))
        }
        .buttonStyle(.lovePress)
        .task { walkie.attach(app) }
    }
    private var subtitle: String {
        if !walkie.unheard.isEmpty { return walkie.unheard.count == 1 ? "Eine neue Nachricht wartet auf dich" : "\(walkie.unheard.count) neue Nachrichten warten" }
        if let last = walkie.messages.last, let date = last.createdAt.rjDate {
            return (last.senderID == app.me?.id ? "Du hast gefunkt · " : "Zuletzt gehört · ") + date.formatted(.relative(presentation: .named))
        }
        return "Gedrückt halten, sprechen, loslassen – wird laut abgespielt"
    }
}
