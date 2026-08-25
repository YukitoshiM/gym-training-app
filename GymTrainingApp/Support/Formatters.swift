import Foundation

enum BodyLengthUnit: String, CaseIterable, Identifiable {
    case centimeters
    case inches

    static let storageKey = "bodymode.units.bodyLength"
    var id: String { rawValue }
    var symbol: String { self == .centimeters ? "cm" : "in" }
    static var defaultValue: BodyLengthUnit { Locale.current.measurementSystem == .us ? .inches : .centimeters }
    static var current: BodyLengthUnit {
        BodyLengthUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultValue
    }
}

enum BodyUnitPreferences {
    static let weightKey = "bodymode.units.weight"
    static var weight: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: weightKey) ?? "")
            ?? .regionalDefault
    }
}

enum AppFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
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

    static func signedWeight(_ value: Double, unit: WeightUnit = .kg) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + weight(value, unit: unit)
    }

    static func signedVolume(_ value: Double, unit: WeightUnit = .kg) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + volume(value, unit: unit)
    }

    static func signedReps(_ value: Int) -> String {
        let prefix = value > 0 ? "+" : ""
        return L10n.string("core_ui.d1d79a159d4b", fallback: "{{value1}}{{value2}}回", values: [String(describing: prefix), String(describing: value)])
    }

    static func bodyweightLoadSummary(
        bodyWeight: Double,
        addedWeight: Double,
        unit: WeightUnit
    ) -> String {
        let effectiveLoad = max(0, bodyWeight + addedWeight)
        if addedWeight < 0 {
            return L10n.string("core_ui.848ccd1f9199", fallback: "体重 {{value1}} - アシスト {{value2}} = 参考負荷 {{value3}}", values: [String(describing: weight(bodyWeight, unit: unit)), String(describing: weight(abs(addedWeight), unit: unit)), String(describing: weight(effectiveLoad, unit: unit))])
        }
        return L10n.string("core_ui.95c5fa8fabe3", fallback: "体重 {{value1}} + 加算 {{value2}} = 参考負荷 {{value3}}", values: [String(describing: weight(bodyWeight, unit: unit)), String(describing: weight(addedWeight, unit: unit)), String(describing: weight(effectiveLoad, unit: unit))])
    }

    static func calories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kcal"
    }

    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "g"
    }

    static func preciseGrams(_ value: Double) -> String {
        grams(value)
    }

    static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func metricValue(_ value: Double, unit: String) -> String {
        let displayed = switch unit {
        case "lb": value * 2.2046226218
        case "in": value / 2.54
        default: value
        }
        return displayed.formatted(.number.precision(.fractionLength(0...1))) + " " + unit
    }

    static func distance(kilometers: Double) -> String {
        let measurement = Measurement(value: kilometers, unit: UnitLength.kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(0...1))
            )
        )
    }

    static func speed(kilometersPerHour: Double) -> String {
        Measurement(value: kilometersPerHour, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func pace(secondsPerKilometer: Double) -> String {
        let usesMiles = Locale.current.measurementSystem == .us
        let seconds = max(0, secondsPerKilometer) * (usesMiles ? 1.609_344 : 1)
        let wholeSeconds = Int(seconds.rounded())
        return String(
            format: "%d:%02d %@",
            wholeSeconds / 60,
            wholeSeconds % 60,
            usesMiles ? "/mi" : "/km"
        )
    }
}
