import SwiftUI
import UIKit

enum LovePalette {
    static let cyan = Color(red: 0.15, green: 0.61, blue: 0.64)
    static let blue = Color(red: 0.18, green: 0.42, blue: 1.0)
    static let pink = Color(red: 0.88, green: 0.20, blue: 0.46)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.42)
    static let violet = Color(red: 0.48, green: 0.34, blue: 0.78)
}

/// Decorative shapes must never participate in the intrinsic width of a screen.
/// GeometryReader follows the actual window, including small iPhones and split view.
struct LoveBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                (scheme == .dark ? Color(red: 0.065, green: 0.055, blue: 0.085) : Color(red: 0.985, green: 0.965, blue: 0.95))
                RadialGradient(colors: [LovePalette.cyan.opacity(scheme == .dark ? 0.11 : 0.07), .clear], center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 1.1)
                Ellipse().fill(LovePalette.pink.opacity(scheme == .dark ? 0.23 : 0.13))
                    .frame(width: geometry.size.width * 1.05, height: geometry.size.height * 0.6)
                    .blur(radius: 70).offset(x: geometry.size.width * 0.34, y: -geometry.size.height * 0.3)
                Ellipse().fill(LovePalette.violet.opacity(0.14))
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.65)
                    .blur(radius: 75).offset(x: -geometry.size.width * 0.35, y: geometry.size.height * 0.3)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().accessibilityHidden(true)
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

    func loveCard() -> some View {
        padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .loveGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: LovePalette.violet.opacity(0.07), radius: 22, y: 12)
    }
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
                        colors: [LovePalette.cyan, LovePalette.violet, LovePalette.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: 3)
            Text(initials)
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: LovePalette.pink.opacity(0.28), radius: 15, y: 6)
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
            .tracking(2.4).foregroundStyle(LovePalette.pink)
    }
}
struct LoveMetric: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = LovePalette.pink
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
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
