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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var bounce = 0
    @State private var hearts = 0
    @State private var breathe = false

    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(id: "glass", symbol: "sparkles", tint: LovePalette.pink, title: "Liquid Glass, überall",
                        detail: "Neue Glas-Tasten, Glaskarten und ein ruhiger, farbiger Hintergrund. Die Tableiste wird beim Scrollen schmal und schenkt euch mehr Platz."),
        WhatsNewFeature(id: "motion", symbol: "wand.and.stars", tint: LovePalette.violet, title: "Flüssige Animationen",
                        detail: "Karten gleiten sanft herein, Tasten federn bei jeder Berührung und Zahlen zählen weich hoch. Mit „Bewegung reduzieren“ bleibt alles ruhig."),
        WhatsNewFeature(id: "heart", symbol: "heart.fill", tint: LovePalette.blush, title: "Herzgedanken mit Gefühl",
                        detail: "Jedes Herz steigt sichtbar auf. Die Startseite begrüßt dich passend zur Tageszeit und zeigt euren Verbindungsstatus live."),
        WhatsNewFeature(id: "studio", symbol: "waveform", tint: LovePalette.violet, title: "Duftstudio neu inszeniert",
                        detail: "Der Aufnahmeknopf atmet mit deinem Pegel, Wiedergabe und Reaktionen antworten sofort und die Sammlung filtert schneller."),
        WhatsNewFeature(id: "airplay", symbol: "airplay.video", tint: LovePalette.blue, title: "AirPlay wie im Kino",
                        detail: "Weiche Überblendungen, Diashow mit Kamerafahrt und Bildhintergrund, eine neue Ambient-Uhr und eure Herz-Signale groß auf dem Fernseher. Dazu eine Live-Vorschau auf dem iPhone."),
        WhatsNewFeature(id: "speed", symbol: "bolt.fill", tint: LovePalette.coral, title: "Spürbar flüssiger",
                        detail: "Der Offline-Speicher schreibt im Hintergrund, Widgets laden nur bei echten Änderungen neu und Server 5.0 komprimiert seine Antworten."),
        WhatsNewFeature(id: "update", symbol: "arrow.down.app.fill", tint: LovePalette.cyan, title: "Einfacher aktualisieren",
                        detail: "Server 5.0 stellt eine neben der Serverdatei abgelegte IPA automatisch für Feather bereit. Ältere Apps erinnern freundlich an das Update.")
    ]

    var body: some View {
        ZStack {
            LoveAurora()
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            ScrollView {
                VStack(spacing: 26) {
                    hero
                    VStack(spacing: 12) {
                        ForEach(Array(Self.features.enumerated()), id: \.element.id) { index, feature in
                            featureRow(feature).loveReveal(revealed, index: index + 3)
                        }
                    }
                    Label("Eure Daten, Anmeldungen, Aufnahmen und Einstellungen bleiben unverändert erhalten.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .loveReveal(revealed, index: Self.features.count + 3)
                }
                .padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 24)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { continueButton }
        }
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: revealed)
        .task {
            revealed = true
            if !reduceMotion { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true } }
            try? await Task.sleep(for: .milliseconds(450))
            hearts += 1
            try? await Task.sleep(for: .milliseconds(500))
            bounce += 1
        }
        .accessibilityIdentifier("rj-whats-new")
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(LovePalette.pink.opacity(0.45)).frame(width: 170, height: 170).blur(radius: 46)
                    .scaleEffect(breathe ? 1.12 : 0.92)
                Image("BrandMark").resizable().scaledToFit().frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .padding(10)
                    .glassEffect(.regular.tint(.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
                    .scaleEffect(breathe ? 1.025 : 1)
                    .accessibilityHidden(true)
                LoveHeartBurst(trigger: hearts).offset(y: -40)
            }
            .frame(height: 180)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.8).opacity(revealed || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.7), value: revealed)
            VStack(spacing: 10) {
                Text("RJ LOVE \(RJVersion.app)")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).tracking(3.2)
                    .foregroundStyle(LinearGradient(colors: [LovePalette.blush, Color(red: 0.80, green: 0.72, blue: 1)], startPoint: .leading, endPoint: .trailing))
                Text("Neu gestaltet.\nNur für euch zwei.")
                    .font(.loveDisplay(38)).multilineTextAlignment(.center).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Das größte Update eures kleinen Wir: hochwertiger, ruhiger und spürbar flüssiger.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .loveReveal(revealed, index: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: feature.symbol)
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(LinearGradient(colors: [feature.tint, feature.tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.7) }
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title).font(.headline).foregroundStyle(.white)
                Text(feature.detail).font(.subheadline).foregroundStyle(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .loveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), tint: .white.opacity(0.03))
        .accessibilityElement(children: .combine)
    }

    private var continueButton: some View {
        VStack(spacing: 9) {
            Button {
                Haptics.impact(.soft)
                app.didReadChangelog()
            } label: {
                Text("Los geht’s").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent).tint(LovePalette.pink).controlSize(.large)
            .accessibilityIdentifier("whats-new-continue")
            Text("Gemeinsam mit Server 5.0 · einmalig angezeigt").font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 10)
        .frame(maxWidth: 620)
        .opacity(revealed || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : LoveMotion.spring.delay(0.5), value: revealed)
    }
}

/// Branded state while a stored session is restored, instead of a bare spinner.
struct LoveLaunchView: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    var body: some View {
        VStack(spacing: 22) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .scaleEffect(breathe ? 1.04 : 0.98)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("RJ Love").font(.loveDisplay(26))
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
            }
        }
        .padding(30)
        .animation(LoveMotion.gentle, value: message)
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true } } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RJ Love lädt. " + message)
    }
}
