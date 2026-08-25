import SwiftUI
import UIKit

enum LovePalette {
    static let cyan = Color(red: 0.12, green: 0.84, blue: 1.0)
    static let blue = Color(red: 0.18, green: 0.42, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.25, blue: 0.55)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.42)
    static let violet = Color(red: 0.62, green: 0.33, blue: 1.0)
}

struct LoveBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(
                colors: [LovePalette.cyan.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 520
            )
            RadialGradient(
                colors: [LovePalette.pink.opacity(0.15), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func loveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    func loveCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .loveGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
