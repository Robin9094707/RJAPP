import SwiftUI
import UIKit

// MARK: - Palette

enum LovePalette {
    static let cyan=Color(red:0.12,green:0.51,blue:0.55)
    static let blue=Color(red:0.23,green:0.43,blue:0.78)
    static let pink=Color(red:0.78,green:0.24,blue:0.43)
    static let coral=Color(red:0.87,green:0.46,blue:0.36)
    static let violet=Color(red:0.43,green:0.35,blue:0.64)
    static let blush=Color(red:0.98,green:0.49,blue:0.57)
    static let plum=Color(red:0.60,green:0.16,blue:0.36)
    static let surface=Color(uiColor:.secondarySystemGroupedBackground)
    /// The signature heart gradient used for primary moments.
    static let heart=LinearGradient(colors:[blush,pink,plum],startPoint:.topLeading,endPoint:.bottomTrailing)
    static let dusk=LinearGradient(colors:[pink,violet],startPoint:.topLeading,endPoint:.bottomTrailing)
}

/// Shared spacing and shape tokens, so every screen breathes the same way.
enum LoveMetrics {
    /// 7.0: iOS 26 proportions – generous, concentric corners like system widgets and grouped lists.
    static let cardRadius:CGFloat=26
    static let tileRadius:CGFloat=22
    static let cardPadding:CGFloat=18
    static let screenPadding:CGFloat=18
    static let stackSpacing:CGFloat=14
}

/// Motion tokens. Every animation in the app goes through these so the rhythm stays calm and consistent.
/// 6.0: short, critically damped curves only. Nothing bounces, nothing loops forever.
enum LoveMotion {
    static let spring=Animation.smooth(duration:0.3)
    static let snappy=Animation.easeOut(duration:0.18)
    static let bouncy=Animation.smooth(duration:0.25)
    static let gentle=Animation.easeInOut(duration:0.25)
    static let fade=Animation.easeInOut(duration:0.2)
    static func entrance(_ index:Int)->Animation {fade}
    /// Returns nil while Reduce Motion is active so changes happen without movement.
    static func respecting(_ reduceMotion:Bool,_ animation:Animation=spring)->Animation? {reduceMotion ? nil:animation}
}

/// Opaque surface colors. Content sits on solid, grouped-style cards; Liquid Glass stays reserved for
/// system chrome (navigation bar, tab bar, toolbars), which keeps scrolling smooth on older iPhones.
enum LoveSurface {
    /// Same color iOS uses for grouped list rows, so cards and Forms match (also elevated in sheets).
    static let card=Color(uiColor:.secondarySystemGroupedBackground)
    static let inset=Color(uiColor:.tertiarySystemGroupedBackground)
    static let hairline=Color.primary.opacity(0.06)
}

// MARK: - Backgrounds

/// 7.0: the grouped-list background of iOS Settings with a soft rosé glow behind the top of the
/// screen, like Apple's Health and Fitness apps. Static: drawn once, never animated.
struct LoveBackground:View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        ZStack(alignment:.top) {
            Color(uiColor:.systemGroupedBackground)
            LinearGradient(colors:scheme == .dark
                           ? [LovePalette.plum.opacity(0.34),LovePalette.violet.opacity(0.10),Color.clear]
                           : [LovePalette.blush.opacity(0.22),LovePalette.pink.opacity(0.06),Color.clear],
                           startPoint:.top,endPoint:.bottom)
                .frame(height:420)
        }
        .ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// A slowly drifting aurora for the AirPlay stage. Static on the phone and with Reduce Motion.
struct LoveAurora:View {
    var colors:[Color]=[LovePalette.plum,LovePalette.violet,Color(red:0.10,green:0.06,blue:0.20),LovePalette.pink,Color(red:0.05,green:0.04,blue:0.10),LovePalette.blue,Color(red:0.12,green:0.05,blue:0.14),LovePalette.coral,Color(red:0.06,green:0.05,blue:0.12)]
    var speed:Double=0.12
    var animated=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/15.0,paused:!animated || reduceMotion)) { context in
            MeshGradient(width:3,height:3,points:Self.points(at:animated && !reduceMotion ? context.date.timeIntervalSinceReferenceDate*speed:0),colors:colors)
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
    /// Computed in Double: the reference-date timestamp is far too large for Float precision.
    private static func points(at t:Double)->[SIMD2<Float>] {
        func wave(_ value:Double)->Float {Float(value)}
        return [
            SIMD2<Float>(0,0),SIMD2<Float>(wave(0.5+0.18*sin(t)),0),SIMD2<Float>(1,0),
            SIMD2<Float>(0,wave(0.5+0.16*cos(t*1.1))),SIMD2<Float>(wave(0.5+0.22*sin(t*0.8)),wave(0.5+0.2*cos(t*0.7))),SIMD2<Float>(1,wave(0.5+0.16*sin(t*0.9))),
            SIMD2<Float>(0,1),SIMD2<Float>(wave(0.5+0.18*cos(t*1.2)),1),SIMD2<Float>(1,1)
        ]
    }
}

// MARK: - Icons and rows

/// 7.0: the iOS Settings icon tile – a solid, softly lit color square with a white glyph.
struct LoveIcon:View {
    let symbol:String
    var tint:Color=LovePalette.pink
    var size:CGFloat=44
    var body:some View {
        let shape=RoundedRectangle(cornerRadius:size*0.27,style:.continuous)
        Image(systemName:symbol).font(.system(size:size*0.46,weight:.semibold)).symbolRenderingMode(.monochrome).foregroundStyle(.white)
            .frame(width:size,height:size)
            .background{shape.fill(tint.gradient)}
            .overlay{shape.strokeBorder(.white.opacity(0.14),lineWidth:0.5)}
            .accessibilityHidden(true)
    }
}
struct LoveSettingsRow:View {
    let title:String
    var subtitle:String?=nil
    let symbol:String
    var tint:Color=LovePalette.pink
    var body:some View {
        HStack(spacing:14){LoveIcon(symbol:symbol,tint:tint,size:32);VStack(alignment:.leading,spacing:2){Text(title).font(.body).foregroundStyle(.primary);if let subtitle{Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}};Spacer(minLength:8);Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)}.padding(.vertical,3).contentShape(Rectangle())
    }
}

/// A classic grouped section: a quiet header above one solid card, like iOS Settings.
struct LoveGroup<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: () -> Content
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.footer = footer; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).foregroundStyle(.primary).padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 10) { content() }.loveCard()
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
/// Row separator aligned with the row text, not the icon.
struct LoveRowDivider: View {
    var body: some View { Divider().padding(.leading, 46) }
}

// MARK: - Glass surfaces

private struct LoveCardSurface:ViewModifier {
    func body(content:Content)->some View {
        content.padding(LoveMetrics.cardPadding).frame(maxWidth:.infinity,alignment:.leading)
            .loveGlass(in:RoundedRectangle(cornerRadius:LoveMetrics.cardRadius,style:.continuous))
    }
}

/// Opaque card fill with a hairline edge and, in light mode, a whisper of depth.
private struct LoveSolidSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background {
                ZStack { shape.fill(LoveSurface.card); shape.fill(tint) }
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 10, y: 3)
            }
            .overlay { shape.stroke(LoveSurface.hairline, lineWidth: 0.5).allowsHitTesting(false) }
    }
}

/// A row that becomes a column when text or available width needs more space.
struct AdaptiveLoveRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content
    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) { self.spacing = spacing; self.content = content }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content().fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: spacing) { content() }.frame(maxWidth: .infinity)
        }
    }
}

extension View {
    /// A solid card surface in any shape. Kept under its 5.0 name so every screen switches at once;
    /// the optional tint is laid over the card as a faint wash.
    func loveGlass<S: Shape>(in shape: S, tint: Color = .clear) -> some View {
        modifier(LoveSolidSurface(shape: shape, tint: tint))
    }
    /// Small floating controls (round header buttons, chips) get real Liquid Glass, lightly tinted
    /// so they never turn into see-through blobs over busy content.
    func loveInteractiveGlass<S: Shape>(in shape: S, tint: Color = .clear) -> some View {
        self.glassEffect(.regular.tint(tint == .clear ? LovePalette.pink.opacity(0.08) : tint).interactive(), in: shape)
    }
    /// Dark, readable backing for text over photos and video (AirPlay stage, camera).
    func loveScrim<S: Shape>(in shape: S, opacity: Double = 0.42) -> some View {
        self.background(.black.opacity(opacity), in: shape)
    }

    func loveCard()->some View {modifier(LoveCardSurface())}

    /// 6.0: screens appear at once. Kept as a no-op so callers stay unchanged.
    func loveReveal(_ shown:Bool,index:Int=0)->some View {self}

    /// 6.0: no scroll-driven scaling; plain, fast scrolling.
    func loveScrollEffect()->some View {self}
}

// MARK: - Buttons

/// Quiet press feedback for custom tappable surfaces (cards, tiles, chips).
struct LovePressStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        LovePressBody(configuration:configuration)
    }
    private struct LovePressBody:View {
        let configuration:Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        var body:some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98:1)
                .opacity(enabled ? (configuration.isPressed ? 0.75:1):0.45)
                .animation(reduceMotion ? nil:.easeOut(duration:0.12),value:configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}
extension ButtonStyle where Self == LovePressStyle {
    static var lovePress:LovePressStyle {LovePressStyle()}
}

// MARK: - Typography helpers

extension Font {
    static func loveDisplay(_ size:CGFloat,weight:Font.Weight = .medium)->Font {.system(size:size,weight:weight,design:.serif)}
}

struct LoveSectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatusChip: View {
    let title: String
    let symbol: String
    var tint: Color = LovePalette.cyan

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityLabel(title)
    }
}

/// A small status dot with a soft halo. Static: a looping pulse costs a frame every refresh.
struct LovePulseDot: View {
    var color: Color = .green
    var active = true
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(active ? 0.25 : 0.12)).frame(width: 13, height: 13)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct PartnerAvatar: View {
    let name: String
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [LovePalette.blush, LovePalette.pink, LovePalette.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: size * 0.8))
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: max(1, size * 0.03))
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Profilbild von \(name)")
    }

    private var initials: String {
        let values = name.split(separator: " ").prefix(2).compactMap(\.first)
        return values.map(String.init).joined().uppercased()
    }
}

struct BatteryBadge: View {
    let level: Int?
    let state: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
            Text(level.map { "\($0) %" } ?? "– %")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(level ?? 0)))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .animation(LoveMotion.gentle, value: level)
        .accessibilityLabel("Akku \(level.map(String.init) ?? "unbekannt") Prozent")
    }

    private var color: Color {
        guard let level else { return .secondary }
        if state == "charging" || state == "full" { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }

    private var symbol: String {
        if state == "charging" { return "battery.100percent.bolt" }
        guard let level else { return "battery.0percent" }
        if level >= 88 { return "battery.100percent" }
        if level >= 63 { return "battery.75percent" }
        if level >= 38 { return "battery.50percent" }
        if level >= 13 { return "battery.25percent" }
        return "battery.0percent"
    }
}

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension View {
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct LoveEyebrow: View {
    let text: String
    var tint: Color = LovePalette.pink
    var body: some View {
        Text(text.uppercased()).fixedSize(horizontal: false, vertical: true).font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(1.8).foregroundStyle(tint)
    }
}
struct LoveMetric: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = LovePalette.pink
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LoveIcon(symbol:symbol,tint:tint,size:34)
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: LoveMetrics.tileRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: LoveMetrics.tileRadius, style: .continuous).strokeBorder(tint.opacity(0.12), lineWidth: 0.6) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Celebration

/// A burst of hearts that float up and fade. Each change of `trigger` releases a new burst.
struct LoveHeartBurst: View {
    let trigger: Int
    var tint: Color = LovePalette.pink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [Burst] = []
    struct Particle: Identifiable { let id = UUID(); let x: CGFloat; let rise: CGFloat; let size: CGFloat; let delay: Double; let spin: Double }
    struct Burst: Identifiable { let id = UUID(); let particles: [Particle] }
    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                ForEach(burst.particles) { particle in LoveFloatingHeart(particle: particle, tint: tint) }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let burst = Burst(particles: (0..<7).map { _ in Particle(x: .random(in: -80...80), rise: .random(in: 120...210), size: .random(in: 12...26), delay: .random(in: 0...0.16), spin: .random(in: -30...30)) })
            bursts.append(burst)
            if bursts.count > 2 { bursts.removeFirst(bursts.count - 2) }
            let id = burst.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                bursts.removeAll { $0.id == id }
            }
        }
    }
}
private struct LoveFloatingHeart: View {
    let particle: LoveHeartBurst.Particle
    let tint: Color
    @State private var flying = false
    @State private var faded = false
    var body: some View {
        Image(systemName: "heart.fill").font(.system(size: particle.size))
            .foregroundStyle(LinearGradient(colors: [LovePalette.blush, tint], startPoint: .top, endPoint: .bottom))
            .rotationEffect(.degrees(flying ? particle.spin : 0))
            .scaleEffect(flying ? 1 : 0.25)
            .offset(x: flying ? particle.x : particle.x * 0.15, y: flying ? -particle.rise : 0)
            .opacity(faded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(particle.delay)) { flying = true }
                withAnimation(.easeIn(duration: 0.55).delay(particle.delay + 0.75)) { faded = true }
            }
    }
}

extension View {
    @ViewBuilder func previewAccessibilityEnvironment() -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-accessibility") { self.dynamicTypeSize(.accessibility2) } else { self }
        #else
        self
        #endif
    }
}
