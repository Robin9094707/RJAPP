import SwiftUI

struct WhatsNewFeature: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
}

/// One-time welcome for a new app version. Shown once per installed version (`rjlove.changelog-seen`).
struct WhatsNewView: View {
    @Environment(AppState.self) private var app

    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(id: "design", symbol: "sparkles", tint: LovePalette.pink, title: "Neues Design",
                        detail: "Klar wie die iOS-Einstellungen: deckende Karten, farbige Symbolkacheln und Liquid Glass für Leisten und Bedienelemente. Hochwertig, aber nie durchsichtig."),
        WhatsNewFeature(id: "walkie", symbol: "antenna.radiowaves.left.and.right", tint: LovePalette.coral, title: "Funk",
                        detail: "Gedrückt halten, sprechen, loslassen. Sind beide in der App, kommt es sofort an – sonst wird es laut abgespielt, sobald dein Lieblingsmensch RJ Love öffnet. Außer im Ruhemodus."),
        WhatsNewFeature(id: "question", symbol: "bubble.left.and.text.bubble.right.fill", tint: LovePalette.violet, title: "Frage des Tages",
                        detail: "Jeden Tag eine neue Frage für euch beide. Die Antwort des anderen seht ihr erst, wenn ihr selbst geantwortet habt."),
        WhatsNewFeature(id: "photo", symbol: "camera.badge.ellipsis", tint: LovePalette.blue, title: "Fotowünsche repariert",
                        detail: "Offene Wünsche erscheinen jetzt immer auf der Startseite, laufen nach 12 Stunden ab und lassen sich sanft erinnern. Niemand hängt mehr fest."),
        WhatsNewFeature(id: "location", symbol: "location.fill", tint: LovePalette.cyan, title: "Zuverlässiger Hintergrundstandort",
                        detail: "Kein automatisches Pausieren mehr, Neustart nach Ortswechseln und Besuchen und ein sofortiger, sparsamer Upload im Hintergrund."),
        WhatsNewFeature(id: "launch", symbol: "heart.fill", tint: LovePalette.plum, title: "Neue Öffnungsanimation",
                        detail: "Euer Bild schlägt einmal wie ein Herz und öffnet euch den Raum. Mit „Bewegung reduzieren“ ganz ruhig.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero
                VStack(spacing: 10) {
                    ForEach(Self.features) { featureRow($0) }
                }
                Label("Eure Daten, Anmeldungen, Aufnahmen und Einstellungen bleiben unverändert erhalten.", systemImage: "lock.shield.fill")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, LoveMetrics.screenPadding).padding(.top, 36).padding(.bottom, 24)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { continueButton }
        .background(LoveBackground())
        .interactiveDismissDisabled()
        .accessibilityIdentifier("rj-whats-new")
    }

    private var hero: some View {
        VStack(spacing: 18) {
            Image("LaunchMark").shadow(color: .black.opacity(0.18), radius: 16, y: 8).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("RJ LOVE \(RJVersion.app)")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).tracking(3)
                    .foregroundStyle(LovePalette.pink)
                Text("Schöner. Näher.\nNur für euch zwei.")
                    .font(.loveDisplay(34)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ein komplettes Redesign im Stil einer echten Apple-App, mit Funk, Frage des Tages und vielen Verbesserungen.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            LoveIcon(symbol: feature.symbol, tint: feature.tint, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title).font(.headline)
                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .loveCard()
        .accessibilityElement(children: .combine)
    }

    private var continueButton: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.impact(.soft)
                app.didReadChangelog()
            } label: {
                Text("Los geht’s").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent).tint(LovePalette.pink).controlSize(.large)
            .accessibilityIdentifier("whats-new-continue")
            Text("Gemeinsam mit Server 7.0 · einmalig angezeigt").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, LoveMetrics.screenPadding).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// The splash content. The mark sits exactly where the system launch screen draws `LaunchMark`
/// on the same `LaunchBackground` color (full screen, ignoring safe areas), so the hand-over is seamless.
struct LoveSplashContent: View {
    var message: String?
    var showsTitle = true
    var beat: CGFloat = 1
    var glow: Double = 0
    var ring: CGFloat = 1
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Circle()
                .fill(RadialGradient(colors: [LovePalette.blush.opacity(0.55), LovePalette.pink.opacity(0.18), .clear], center: .center, startRadius: 20, endRadius: 190))
                .frame(width: 380, height: 380)
                .opacity(glow)
            Circle()
                .strokeBorder(LovePalette.pink.opacity(0.45), lineWidth: 2)
                .frame(width: 150, height: 150)
                .scaleEffect(ring)
                .opacity(glow * Double(max(0, 2.2 - ring)) / 1.2)
            Image("LaunchMark")
                .shadow(color: LovePalette.plum.opacity(0.28), radius: 22, y: 12)
                .scaleEffect(beat)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("RJ Love").font(.loveDisplay(30, weight: .semibold))
                Text("Nur für euch zwei").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .offset(y: showsTitle ? 120 : 132)
            .opacity(showsTitle ? 1 : 0)
            VStack {
                Spacer()
                if let message {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(message).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                    }.padding(.horizontal, 32).padding(.bottom, 56)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RJ Love lädt. " + (message ?? ""))
    }
}

/// 7.0 opening: the mark beats once like a heart (with a soft glow and a ring of light), the name
/// rises underneath, then the whole splash opens towards you and reveals the app.
/// Skipped at once for an emergency recording; a plain fade with Reduce Motion.
struct LoveSplashOverlay: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    @State private var titleShown = false
    @State private var beat: CGFloat = 1
    @State private var glow = 0.0
    @State private var ring: CGFloat = 1
    @State private var opening = false
    @State private var hearts = 0
    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    LoveSplashContent(message: nil, showsTitle: titleShown, beat: beat, glow: glow, ring: ring)
                    LoveHeartBurst(trigger: hearts, tint: LovePalette.pink).offset(y: -20)
                }
                .scaleEffect(opening ? 1.18 : 1)
                .opacity(opening ? 0 : 1)
                .transition(.identity)
            }
        }
        .allowsHitTesting(visible && !opening)
        .task {
            let start = Date.now
            if app.pendingQuickCapture != nil { visible = false; return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { titleShown = true }
            } else {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.16)) { beat = 1.08; glow = 1 }
                withAnimation(.easeOut(duration: 0.9)) { ring = 2.2 }
                Haptics.impact(.soft)
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.14)) { beat = 0.97 }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.14)) { beat = 1.045 }
                hearts += 1
                Haptics.impact(.light)
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { beat = 1; titleShown = true }
            }
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(start)
                if app.pendingQuickCapture != nil { break }
                if app.phase != .restoring && elapsed > 1.05 { break }
                if elapsed > 4 { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if reduceMotion || app.pendingQuickCapture != nil {
                withAnimation(.easeOut(duration: 0.25)) { visible = false }
            } else {
                withAnimation(.easeIn(duration: 0.42)) { opening = true }
                try? await Task.sleep(for: .milliseconds(440))
                visible = false
            }
        }
    }
}

/// Shown while a slow session restore continues after the splash: the same calm picture plus progress.
struct LoveLaunchView: View {
    let message: String
    var body: some View { LoveSplashContent(message: message) }
}
