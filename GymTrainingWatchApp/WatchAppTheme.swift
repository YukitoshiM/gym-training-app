import SwiftUI

enum WatchAppTheme {
    static var accent: Color {
        color(cobalt: 0x5B82FF, champagne: 0xFF3448)
    }

    static var ink: Color {
        color(cobalt: 0xF2F5F7, champagne: 0xF4DF9E)
    }

    static var mutedInk: Color {
        color(cobalt: 0xAAB8CF, champagne: 0xB7A36B)
    }

    static var surface: Color {
        color(cobalt: 0x0B1B35, champagne: 0x12100C)
    }

    static var positive: Color { accent }
    static var warning: Color { accent.opacity(0.82) }
    static var critical: Color { accent }
    static var secondaryAccent: Color { ink.opacity(0.68) }

    private static func color(cobalt: UInt32, champagne: UInt32) -> Color {
        Color(hex: AppAppearanceSettings.load().colorTheme == .royalCobalt ? cobalt : champagne)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
