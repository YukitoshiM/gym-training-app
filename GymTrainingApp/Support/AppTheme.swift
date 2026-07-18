import SwiftUI
import UIKit

enum AppTheme {
    static var pageBackground: Color {
        themed(
            cobaltLight: 0xE9EFF7,
            cobaltDark: 0x061225,
            champagneLight: 0xF5F0E2,
            champagneDark: 0x080808
        )
    }

    static var cardBackground: Color {
        themed(
            cobaltLight: 0xF5F7FA,
            cobaltDark: 0x0B1B35,
            champagneLight: 0xFFFCF4,
            champagneDark: 0x12100C
        )
    }

    static var elevatedBackground: Color {
        themed(
            cobaltLight: 0xFFFFFF,
            cobaltDark: 0x102444,
            champagneLight: 0xFFF9E8,
            champagneDark: 0x1A1710
        )
    }

    static var ink: Color {
        themed(
            cobaltLight: 0x08172E,
            cobaltDark: 0xF2F5F7,
            champagneLight: 0x16120C,
            champagneDark: 0xF4DF9E
        )
    }

    static var mutedInk: Color {
        themed(
            cobaltLight: 0x53647D,
            cobaltDark: 0xAAB8CF,
            champagneLight: 0x665B43,
            champagneDark: 0xB7A36B
        )
    }

    static var accent: Color {
        themed(
            cobaltLight: 0x1749D7,
            cobaltDark: 0x5B82FF,
            champagneLight: 0xB8172D,
            champagneDark: 0xFF3448
        )
    }

    static var onAccent: Color {
        themed(
            cobaltLight: 0xF2F5F7,
            cobaltDark: 0x08172E,
            champagneLight: 0xFFF9E8,
            champagneDark: 0x080808
        )
    }

    static var foregroundOnDark: Color {
        switch currentTheme {
        case .royalCobalt: Color(hex: 0xF2F5F7)
        case .blackChampagne: Color(hex: 0xF4DF9E)
        }
    }

    static var darkBase: Color {
        switch currentTheme {
        case .royalCobalt: Color(hex: 0x061225)
        case .blackChampagne: Color(hex: 0x080808)
        }
    }

    static var cardBorder: Color { ink.opacity(0.18) }
    static var shadow: Color { darkBase.opacity(0.22) }
    static var gymFloor: Color { ink }

    // Status is communicated by icon and text. Color remains inside the selected three-color system.
    static var positive: Color { accent }
    static var warning: Color { accent.opacity(0.82) }
    static var critical: Color { accent }
    static var info: Color { accent }
    static var secondaryAccent: Color { ink.opacity(0.68) }
    static var tertiaryAccent: Color { mutedInk }

    // Compatibility aliases for older views while direct color names are removed.
    static var blue: Color { info }
    static var orange: Color { warning }
    static var purple: Color { secondaryAccent }

    static let cardRadius: CGFloat = 8

    static var currentTheme: AppColorTheme {
        AppAppearanceSettings.load().colorTheme
    }

    static func preferredColorScheme(for mode: AppAppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func previewSwatches(for theme: AppColorTheme) -> [Color] {
        switch theme {
        case .royalCobalt:
            [Color(hex: 0x08172E), Color(hex: 0xF2F5F7), Color(hex: 0x2457FF)]
        case .blackChampagne:
            [Color(hex: 0x080808), Color(hex: 0xE2C77B), Color(hex: 0xED2E38)]
        }
    }

    private static func themed(
        cobaltLight: UInt32,
        cobaltDark: UInt32,
        champagneLight: UInt32,
        champagneDark: UInt32
    ) -> Color {
        let light = currentTheme == .royalCobalt ? cobaltLight : champagneLight
        let dark = currentTheme == .royalCobalt ? cobaltDark : champagneDark
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

struct TrainingBackground: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground

            GeometryReader { proxy in
                Path { path in
                    let spacing: CGFloat = 28
                    var x: CGFloat = -proxy.size.height
                    while x < proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + proxy.size.height, y: proxy.size.height))
                        x += spacing
                    }
                }
                .stroke(AppTheme.ink.opacity(0.045), lineWidth: 1)
            }

            VStack {
                Rectangle()
                    .fill(AppTheme.ink.opacity(0.035))
                    .frame(height: 220)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
    }
}

struct IconBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
    }
}
