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
    static let cardRadius:CGFloat=28
    static let tileRadius:CGFloat=22
    static let cardPadding:CGFloat=20
    static let screenPadding:CGFloat=20
    static let stackSpacing:CGFloat=18
}

/// Motion tokens. Every animation in the app goes through these so the rhythm stays consistent.
enum LoveMotion {
    static let spring=Animation.spring(response:0.48,dampingFraction:0.86)
    static let snappy=Animation.spring(response:0.32,dampingFraction:0.78)
    static let bouncy=Animation.spring(response:0.42,dampingFraction:0.58)
    static let gentle=Animation.smooth(duration:0.45)
    static let fade=Animation.easeInOut(duration:0.35)
    static func entrance(_ index:Int)->Animation {spring.delay(Double(min(max(index,0),10))*0.05)}
    /// Returns nil while Reduce Motion is active so changes happen without movement.
    static func respecting(_ reduceMotion:Bool,_ animation:Animation=spring)->Animation? {reduceMotion ? nil:animation}
}

// MARK: - Backgrounds

/// A calm, static Liquid-Glass-friendly backdrop. It is rendered once per screen and never animates,
/// which keeps scrolling smooth even with many glass cards above it.
struct LoveBackground:View {
    @Environment(\.colorScheme) private var scheme
    private static let points:[SIMD2<Float>]=[
        SIMD2<Float>(0,0),SIMD2<Float>(0.5,0),SIMD2<Float>(1,0),
        SIMD2<Float>(0,0.5),SIMD2<Float>(0.62,0.42),SIMD2<Float>(1,0.5),
        SIMD2<Float>(0,1),SIMD2<Float>(0.45,1),SIMD2<Float>(1,1)
    ]
    private static let light:[Color]=[
        Color(red:0.99,green:0.93,blue:0.95),Color(red:0.97,green:0.95,blue:0.99),Color(red:0.93,green:0.94,blue:0.99),
        Color(red:0.98,green:0.95,blue:0.97),Color(red:0.96,green:0.96,blue:0.98),Color(red:0.95,green:0.93,blue:0.99),
        Color(red:0.95,green:0.97,blue:0.99),Color(red:0.98,green:0.94,blue:0.96),Color(red:0.99,green:0.95,blue:0.93)
    ]
    private static let dark:[Color]=[
        Color(red:0.15,green:0.05,blue:0.10),Color(red:0.07,green:0.06,blue:0.10),Color(red:0.08,green:0.07,blue:0.15),
        Color(red:0.06,green:0.05,blue:0.08),Color(red:0.04,green:0.04,blue:0.06),Color(red:0.09,green:0.06,blue:0.13),
        Color(red:0.04,green:0.06,blue:0.09),Color(red:0.09,green:0.04,blue:0.08),Color(red:0.11,green:0.06,blue:0.05)
    ]
    var body:some View {
        MeshGradient(width:3,height:3,points:Self.points,colors:scheme == .dark ? Self.dark:Self.light)
            .ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// A slowly drifting aurora for immersive moments (splash screen, TV). Static with Reduce Motion.
struct LoveAurora:View {
    var colors:[Color]=[LovePalette.plum,LovePalette.violet,Color(red:0.10,green:0.06,blue:0.20),LovePalette.pink,Color(red:0.05,green:0.04,blue:0.10),LovePalette.blue,Color(red:0.12,green:0.05,blue:0.14),LovePalette.coral,Color(red:0.06,green:0.05,blue:0.12)]
    var speed:Double=0.12
    var animated=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/24.0,paused:!animated || reduceMotion)) { context in
            MeshGradient(width:3,height:3,points:Self.points(at:context.date.timeIntervalSinceReferenceDate*speed),colors:colors)
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

struct LoveIcon:View {
    let symbol:String
    var tint:Color=LovePalette.pink
    var size:CGFloat=44
    var body:some View {
        let shape=RoundedRectangle(cornerRadius:size*0.32,style:.continuous)
        Image(systemName:symbol).font(.system(size:size*0.42,weight:.semibold)).symbolRenderingMode(.hierarchical).foregroundStyle(tint)
            .frame(width:size,height:size)
            .background{shape.fill(LinearGradient(colors:[tint.opacity(0.22),tint.opacity(0.08)],startPoint:.topLeading,endPoint:.bottomTrailing))}
            .overlay{shape.strokeBorder(tint.opacity(0.16),lineWidth:0.6)}
            .accessibilityHidden(true)
    }
}
struct LoveSettingsRow:View {
    let title:String
    var subtitle:String?=nil
    let symbol:String
    var tint:Color=LovePalette.pink
    var body:some View {
        HStack(spacing:14){LoveIcon(symbol:symbol,tint:tint);VStack(alignment:.leading,spacing:4){Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary);if let subtitle{Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}};Spacer(minLength:8);Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)}.padding(.vertical,4).contentShape(Rectangle())
    }
}

// MARK: - Glass surfaces

private struct LoveCardSurface:ViewModifier {
    func body(content:Content)->some View {
        content.padding(LoveMetrics.cardPadding).frame(maxWidth:.infinity,alignment:.leading)
            .loveGlass(in:RoundedRectangle(cornerRadius:LoveMetrics.cardRadius,style:.continuous))
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

private struct LoveGlassHighlight<S:Shape>:ViewModifier {
    let shape:S
    @Environment(\.colorScheme) private var scheme
    func body(content:Content)->some View {
        content.overlay {
            shape.stroke(LinearGradient(colors:[.white.opacity(scheme == .dark ? 0.22:0.55),.white.opacity(scheme == .dark ? 0.03:0.12)],startPoint:.top,endPoint:.bottom),lineWidth:0.8)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Native iOS 26 Liquid Glass with a soft specular rim.
    func loveGlass<S: Shape>(in shape: S, tint: Color = LovePalette.violet.opacity(0.03)) -> some View {
        self.glassEffect(.regular.tint(tint), in: shape).modifier(LoveGlassHighlight(shape:shape))
    }
    /// Interactive glass for tappable surfaces: it reacts to touches with the system shimmer.
    func loveInteractiveGlass<S: Shape>(in shape: S, tint: Color = LovePalette.violet.opacity(0.03)) -> some View {
        self.glassEffect(.regular.tint(tint).interactive(), in: shape).modifier(LoveGlassHighlight(shape:shape))
    }

    func loveCard()->some View {modifier(LoveCardSurface())}

    /// Staggered first appearance. Driven by a flag owned by the screen, so lazily recreated rows never re-animate.
    func loveReveal(_ shown:Bool,index:Int=0)->some View {modifier(LoveReveal(shown:shown,index:index))}

    /// Cards gently settle as they scroll into view and recede at the edges.
    func loveScrollEffect()->some View {modifier(LoveScrollEffect())}
}

private struct LoveReveal:ViewModifier {
    let shown:Bool
    let index:Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content:Content)->some View {
        let visible=shown || reduceMotion
        content.opacity(visible ? 1:0).offset(y:visible ? 0:22).scaleEffect(visible ? 1:0.97,anchor:.top)
            .animation(reduceMotion ? nil:LoveMotion.entrance(index),value:shown)
    }
}

private struct LoveScrollEffect:ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content:Content)->some View {
        let still=reduceMotion
        content.scrollTransition(.interactive,axis:.vertical) { effect,phase in
            effect.scaleEffect(still || phase.isIdentity ? 1:0.955).opacity(still || phase.isIdentity ? 1:0.62)
        }
    }
}

// MARK: - Buttons

/// Springy press feedback for custom tappable surfaces (cards, tiles, chips).
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
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965:1)
                .opacity(enabled ? (configuration.isPressed ? 0.88:1):0.45)
                .animation(reduceMotion ? nil:LoveMotion.snappy,value:configuration.isPressed)
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
            .glassEffect(.regular.tint(tint.opacity(0.12)), in: Capsule())
            .accessibilityLabel(title)
    }
}

/// A small glowing status dot that softly breathes while active.
struct LovePulseDot: View {
    var color: Color = .green
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.25 : 0.5).opacity(pulsing ? 0 : 0.9)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear { if active && !reduceMotion { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true } } }
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
            .background(LinearGradient(colors: [tint.opacity(0.11), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: LoveMetrics.tileRadius, style: .continuous))
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
            let burst = Burst(particles: (0..<10).map { _ in Particle(x: .random(in: -80...80), rise: .random(in: 120...210), size: .random(in: 12...26), delay: .random(in: 0...0.16), spin: .random(in: -30...30)) })
            bursts.append(burst)
            if bursts.count > 4 { bursts.removeFirst(bursts.count - 4) }
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
                withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(particle.delay)) { flying = true }
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
