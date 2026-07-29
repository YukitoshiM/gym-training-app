import Foundation

enum AppColorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case royalCobalt
    case blackChampagne

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .royalCobalt: "ロイヤルコバルト"
        case .blackChampagne: "ブラックシャンパン"
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
        case .royalCobalt: "知的・高貴・先進的"
        case .blackChampagne: "重厚・高級・刺激的"
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
        case .system: "自動"
        case .light: "ライト"
        case .dark: "ダーク"
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
