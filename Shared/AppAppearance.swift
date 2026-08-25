import Foundation

enum AppColorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case royalCobalt
    case blackChampagne

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .royalCobalt: L10n.string("runtime_messages.381a8ceae643", fallback: "ロイヤルコバルト")
        case .blackChampagne: L10n.string("runtime_messages.8617ffabdc47", fallback: "ブラックシャンパン")
        }
    }

    var shortCode: String {
        switch self {
        case .royalCobalt: "B"
        case .blackChampagne: "D"
        }
    }

    var summary: String {
        switch self {
        case .royalCobalt: L10n.string("runtime_messages.2dc960114eaa", fallback: "知的・高貴・先進的")
        case .blackChampagne: L10n.string("runtime_messages.f974d51c5ef8", fallback: "重厚・高級・刺激的")
        }
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.string("runtime_messages.e7c885a6a202", fallback: "自動")
        case .light: L10n.string("runtime_messages.e0654cb7b536", fallback: "ライト")
        case .dark: L10n.string("runtime_messages.02b7a66f4b4d", fallback: "ダーク")
        }
    }
}

struct AppAppearanceSettings: Codable, Hashable, Sendable {
    var colorTheme: AppColorTheme
    var mode: AppAppearanceMode

    static let `default` = AppAppearanceSettings(
        colorTheme: .royalCobalt,
        mode: .system
    )

    static let themeStorageKey = "gym.training.appearance.theme"
    static let modeStorageKey = "gym.training.appearance.mode"

    static func load(from defaults: UserDefaults = .standard) -> AppAppearanceSettings {
        AppAppearanceSettings(
            colorTheme: defaults.string(forKey: themeStorageKey)
                .flatMap(AppColorTheme.init(rawValue:)) ?? Self.default.colorTheme,
            mode: defaults.string(forKey: modeStorageKey)
                .flatMap(AppAppearanceMode.init(rawValue:)) ?? Self.default.mode
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(colorTheme.rawValue, forKey: Self.themeStorageKey)
        defaults.set(mode.rawValue, forKey: Self.modeStorageKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: themeStorageKey)
        defaults.removeObject(forKey: modeStorageKey)
    }
}
