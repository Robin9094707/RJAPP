import SwiftUI
import UIKit

enum LovePalette {
    static let cyan=Color(red:0.12,green:0.51,blue:0.55)
    static let blue=Color(red:0.23,green:0.43,blue:0.78)
    static let pink=Color(red:0.78,green:0.24,blue:0.43)
    static let coral=Color(red:0.87,green:0.46,blue:0.36)
    static let violet=Color(red:0.43,green:0.35,blue:0.64)
    static let surface=Color(uiColor:.secondarySystemGroupedBackground)
}

struct LoveBackground:View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        ZStack {
            Color(uiColor:.systemGroupedBackground)
            LinearGradient(colors:[LovePalette.pink.opacity(scheme == .dark ? 0.09:0.045),.clear,LovePalette.violet.opacity(0.025)],startPoint:.topLeading,endPoint:.bottomTrailing)
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct LoveIcon:View {
    let symbol:String
    var tint:Color=LovePalette.pink
    var size:CGFloat=44
    var body:some View {
        Image(systemName:symbol).font(.system(size:size*0.42,weight:.semibold)).foregroundStyle(tint)
            .frame(width:size,height:size).background(tint.opacity(0.1),in:RoundedRectangle(cornerRadius:size*0.31,style:.continuous))
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
private struct LoveCardSurface:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content:Content)->some View {
        content.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .loveGlass(in:RoundedRectangle(cornerRadius:26,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:26,style:.continuous).stroke(Color.primary.opacity(scheme == .dark ? 0.07:0.025),lineWidth:1).allowsHitTesting(false)}
            .shadow(color:.black.opacity(scheme == .dark ? 0:0.025),radius:14,y:5)
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
    @ViewBuilder
    func loveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(LovePalette.violet.opacity(0.035)), in: shape)
                .overlay { shape.stroke(.white.opacity(0.22), lineWidth: 0.7).allowsHitTesting(false) }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    func loveCard()->some View {modifier(LoveCardSurface())}

}

struct LoveSectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
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
                        colors: [LovePalette.pink, LovePalette.violet],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 2)
            Text(initials)
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: LovePalette.pink.opacity(0.12), radius: 8, y: 4)
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
            Image(systemName: symbol)
            Text(level.map { "\($0) %" } ?? "– %")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
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
}

extension View {
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct LoveEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).fixedSize(horizontal: false, vertical: true).font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.8).foregroundStyle(LovePalette.pink)
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
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
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
