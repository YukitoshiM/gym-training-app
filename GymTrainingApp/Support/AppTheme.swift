import SwiftUI
import UIKit

enum AppTheme {
    static let pageBackground = adaptive(
        light: UIColor(red: 0.92, green: 0.94, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.07, blue: 0.06, alpha: 1)
    )
    static let cardBackground = adaptive(
        light: UIColor(red: 0.99, green: 0.99, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.12, blue: 0.105, alpha: 1)
    )
    static let elevatedBackground = adaptive(
        light: UIColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 0.96),
        dark: UIColor(red: 0.12, green: 0.145, blue: 0.125, alpha: 0.96)
    )
    static let ink = Color(uiColor: .label)
    static let mutedInk = Color(uiColor: .secondaryLabel)
    static let onAccent = Color(red: 0.08, green: 0.10, blue: 0.09)
    static let cardBorder = Color(uiColor: .separator).opacity(0.55)
    static let shadow = Color.black.opacity(0.18)
    static let gymFloor = Color(red: 0.12, green: 0.15, blue: 0.13)
    static let accent = Color(red: 0.53, green: 0.93, blue: 0.30)
    static let blue = Color(red: 0.14, green: 0.42, blue: 0.82)
    static let orange = Color(red: 0.95, green: 0.48, blue: 0.16)
    static let purple = Color(red: 0.50, green: 0.25, blue: 0.78)

    static let cardRadius: CGFloat = 8

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct TrainingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.pageBackground,
                    AppTheme.cardBackground,
                    AppTheme.pageBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

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
                .stroke(AppTheme.ink.opacity(0.05), lineWidth: 1)
            }

            VStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.gymFloor.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
