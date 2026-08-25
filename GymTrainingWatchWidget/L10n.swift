import Foundation

enum L10n {
    static func string(
        _ key: String,
        fallback: String,
        values: [String] = [],
        bundle: Bundle = .main
    ) -> String {
        var result = bundle.localizedString(forKey: key, value: fallback, table: nil)
        for (index, value) in values.enumerated() {
            result = result.replacingOccurrences(of: "{{value\(index + 1)}}", with: value)
        }
        return result
    }
}
