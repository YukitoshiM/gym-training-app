import Foundation

enum L10n {
    static func string(
        _ key: String,
        fallback: String,
        values: [String] = [],
        bundle: Bundle? = nil
    ) -> String {
        let bundle = bundle ?? AppLanguagePreference.localizedBundle
        var result = bundle.localizedString(forKey: key, value: fallback, table: nil)
        for (index, value) in values.enumerated() {
            result = result.replacingOccurrences(of: "{{value\(index + 1)}}", with: value)
        }
        return result
    }
}

enum AppLanguagePreference {
    static let storageKey = "bodymode.appLanguage"
    static let systemIdentifier = "system"

    static let supportedIdentifiers = [
        "ar-SA", "ca", "cs", "da", "de-DE", "el",
        "en-AU", "en-CA", "en-GB", "en-US",
        "es-ES", "es-MX", "fi", "fr-CA", "fr-FR",
        "gu", "he", "hi", "hr", "hu", "id", "it", "ja", "ko",
        "mr", "ms", "nb", "nl-NL", "pl", "pt-BR", "pt-PT", "ro",
        "ru", "sk", "sl", "sv", "ta", "te", "th", "tr", "uk", "vi",
        "zh-Hans", "zh-Hant"
    ]

    static var selectedIdentifier: String {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? systemIdentifier
        return supportedIdentifiers.contains(stored) ? stored : systemIdentifier
    }

    static var locale: Locale {
        selectedIdentifier == systemIdentifier ? .autoupdatingCurrent : Locale(identifier: selectedIdentifier)
    }

    static var aiLocaleIdentifier: String {
        guard selectedIdentifier == systemIdentifier else { return selectedIdentifier }

        for preferredIdentifier in Locale.preferredLanguages {
            if supportedIdentifiers.contains(preferredIdentifier) {
                return preferredIdentifier
            }

            let preferredLanguage = Locale(identifier: preferredIdentifier).language.languageCode?.identifier
            if let match = supportedIdentifiers.first(where: {
                Locale(identifier: $0).language.languageCode?.identifier == preferredLanguage
            }) {
                return match
            }
        }
        return "en-US"
    }

    static var localizedBundle: Bundle {
        guard selectedIdentifier != systemIdentifier else { return .main }

        for identifier in bundleCandidates(for: selectedIdentifier) {
            if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    static var usesJapanese: Bool {
        let identifier = selectedIdentifier == systemIdentifier
            ? Locale.autoupdatingCurrent.identifier
            : selectedIdentifier
        return identifier.lowercased().hasPrefix("ja")
    }

    static var languageLabel: String {
        usesJapanese ? "言語" : "Language"
    }

    static var systemLabel: String {
        usesJapanese ? "システム設定" : "System Default"
    }

    static func bilingual(japanese: String, english: String) -> String {
        usesJapanese ? japanese : english
    }

    static func displayName(for identifier: String) -> String {
        guard identifier != systemIdentifier else { return systemLabel }
        let nativeLocale = Locale(identifier: identifier)
        return nativeLocale.localizedString(forIdentifier: identifier)
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    private static func bundleCandidates(for identifier: String) -> [String] {
        var candidates = [identifier]
        let locale = Locale(identifier: identifier)
        if let languageCode = locale.language.languageCode?.identifier,
           !candidates.contains(languageCode) {
            candidates.append(languageCode)
        }
        return candidates
    }
}
