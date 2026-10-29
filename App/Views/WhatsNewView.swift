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
        WhatsNewFeature(id: "calm", symbol: "rectangle.stack.fill", tint: LovePalette.pink, title: "Ruhig und klar",
                        detail: "Feste Karten statt durchsichtiger Flächen, ein ruhiger Hintergrund und überall dieselben Abstände. Liquid Glass bleibt dort, wo es hingehört: in Tab- und Navigationsleiste."),
        WhatsNewFeature(id: "fluid", symbol: "speedometer", tint: LovePalette.violet, title: "Spürbar flüssiger",
                        detail: "Keine Endlos-Animationen, kein Wackeln beim Scrollen. Die App zeichnet deutlich weniger und schont Akku und ältere iPhones."),
        WhatsNewFeature(id: "emergency", symbol: "cloud.fill", tint: LovePalette.blush, title: "Notfallaufnahme repariert",
                        detail: "Der Recorder öffnet sich ohne Springen, der Aufnahmeknopf bleibt an seinem Platz und der Pegel reagiert sauber."),
        WhatsNewFeature(id: "splash", symbol: "heart.fill", tint: LovePalette.coral, title: "Neuer Startbildschirm",
                        detail: "Ein ruhiger, nahtloser Start mit eurem Bild, bis eure Sitzung bereit ist."),
        WhatsNewFeature(id: "update", symbol: "arrow.down.app.fill", tint: LovePalette.cyan, title: "Gemeinsam mit Server 6.0",
                        detail: "Eure Daten, Anmeldungen, Aufnahmen und Einstellungen bleiben unverändert. Ältere Apps erinnern freundlich an das Update.")
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
                Text("Ruhiger. Schneller.\nNur für euch zwei.")
                    .font(.loveDisplay(34)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Eine gründliche Überarbeitung: klareres Design, weniger Bewegung und viele kleine Fehler behoben.")
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
            .buttonStyle(.borderedProminent).tint(LovePalette.pink).controlSize(.large)
            .accessibilityIdentifier("whats-new-continue")
            Text("Gemeinsam mit Server 6.0 · einmalig angezeigt").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, LoveMetrics.screenPadding).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// The splash content. The mark sits exactly where the system launch screen draws `LaunchMark`
/// on the same `LaunchBackground` color, so the hand-over from iOS to the app is seamless.
struct LoveSplashContent: View {
    var message: String?
    var showsTitle = true
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchMark").shadow(color: .black.opacity(0.2), radius: 18, y: 10).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("RJ Love").font(.loveDisplay(28))
                Text("Nur für euch zwei").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .offset(y: 112)
            .opacity(showsTitle ? 1 : 0)
            VStack {
                Spacer()
                if let message {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(message).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                    }.padding(.horizontal, 32).padding(.bottom, 40)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RJ Love lädt. " + (message ?? ""))
    }
}

/// Covers the first moments after launch, then fades away once: as soon as the session is restored,
/// or right away when an emergency recording was requested from a widget or the Control Center.
struct LoveSplashOverlay: View {
    @Environment(AppState.self) private var app
    @State private var visible = true
    @State private var titleShown = false
    var body: some View {
        ZStack {
            if visible {
                LoveSplashContent(message: nil, showsTitle: titleShown).transition(.opacity)
            }
        }
        .allowsHitTesting(visible)
        .task {
            withAnimation(.easeOut(duration: 0.35)) { titleShown = true }
            let start = Date.now
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(start)
                if app.pendingQuickCapture != nil && elapsed > 0.1 { break }
                if app.phase != .restoring && elapsed > 0.7 { break }
                if elapsed > 4 { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
        }
    }
}

/// Shown while a slow session restore continues after the splash: the same calm picture plus progress.
struct LoveLaunchView: View {
    let message: String
    var body: some View { LoveSplashContent(message: message) }
}
