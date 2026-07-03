import SwiftUI

enum AppTheme {
    static let pageBackground = Color(red: 0.92, green: 0.94, blue: 0.90)
    static let cardBackground = Color(red: 0.99, green: 0.99, blue: 0.96)
    static let elevatedBackground = Color.white.opacity(0.92)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.09)
    static let mutedInk = Color(red: 0.43, green: 0.48, blue: 0.43)
    static let gymFloor = Color(red: 0.12, green: 0.15, blue: 0.13)
    static let accent = Color(red: 0.53, green: 0.93, blue: 0.30)
    static let blue = Color(red: 0.14, green: 0.42, blue: 0.82)
    static let orange = Color(red: 0.95, green: 0.48, blue: 0.16)
    static let purple = Color(red: 0.50, green: 0.25, blue: 0.78)

    static let cardRadius: CGFloat = 8
}

struct TrainingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.92, blue: 0.84),
                    Color(red: 0.96, green: 0.95, blue: 0.89),
                    Color(red: 0.91, green: 0.93, blue: 0.90)
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
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
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
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 14, x: 0, y: 8)
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
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(0.08), radius: 14, x: 0, y: 8)
    }
}
