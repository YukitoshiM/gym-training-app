import Foundation

enum AppFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func weight(_ value: Double, unit: WeightUnit = .kg) -> String {
        switch unit {
        case .kg:
            value.formatted(.number.precision(.fractionLength(0...1))) + " kg"
        case .lb:
            (value * 2.2046226218).formatted(.number.precision(.fractionLength(0...1))) + " lb"
        }
    }

    static func volume(_ value: Double, unit: WeightUnit = .kg) -> String {
        switch unit {
        case .kg:
            value.formatted(.number.precision(.fractionLength(0))) + " kg"
        case .lb:
            (value * 2.2046226218).formatted(.number.precision(.fractionLength(0))) + " lb"
        }
    }

    static func calories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kcal"
    }

    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "g"
    }

    static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func metricValue(_ value: Double, unit: String) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit
    }
}
