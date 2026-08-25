import Foundation

enum BodyMetricKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case bodyWeight
    case waist
    case bodyFatPercentage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyWeight: L10n.string("domain_catalog.00a62c054ebd", fallback: "体重")
        case .waist: L10n.string("domain_catalog.b9cbca96cdbd", fallback: "腹囲")
        case .bodyFatPercentage: L10n.string("domain_catalog.70b83fa847e3", fallback: "体脂肪率")
        }
    }

    var unit: String {
        switch self {
        case .bodyWeight: BodyUnitPreferences.weight.rawValue
        case .waist: BodyLengthUnit.current.symbol
        case .bodyFatPercentage: "%"
        }
    }

    var storageUnit: String {
        switch self {
        case .bodyWeight: "kg"
        case .waist: "cm"
        case .bodyFatPercentage: "%"
        }
    }

    func displayedValue(fromStored value: Double) -> Double {
        switch self {
        case .bodyWeight where BodyUnitPreferences.weight == .lb: value * 2.2046226218
        case .waist where BodyLengthUnit.current == .inches: value / 2.54
        default: value
        }
    }

    func storedValue(fromDisplayed value: Double) -> Double {
        switch self {
        case .bodyWeight where BodyUnitPreferences.weight == .lb: value / 2.2046226218
        case .waist where BodyLengthUnit.current == .inches: value * 2.54
        default: value
        }
    }

    var systemImage: String {
        switch self {
        case .bodyWeight: "scalemass"
        case .waist: "figure.core.training"
        case .bodyFatPercentage: "percent"
        }
    }

    var defaultGoalDirection: BodyMetricGoalDirection {
        switch self {
        case .bodyWeight, .waist, .bodyFatPercentage: .decrease
        }
    }
}

enum BodyMetricGoalDirection: String, CaseIterable, Identifiable, Codable, Hashable {
    case increase
    case decrease

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .increase: L10n.string("domain_catalog.5ee36a0dcb06", fallback: "増やしたい")
        case .decrease: L10n.string("domain_catalog.25f3a0cfbb8f", fallback: "減らしたい")
        }
    }
}

struct BodyMetricEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: BodyMetricKind
    var value: Double
    var recordedAt: Date
    var note: String
    var isEstimated: Bool?
    var estimateLowerBound: Double?
    var estimateUpperBound: Double?

    init(
        id: UUID = UUID(),
        kind: BodyMetricKind,
        value: Double,
        recordedAt: Date = Date(),
        note: String = "",
        isEstimated: Bool? = nil,
        estimateLowerBound: Double? = nil,
        estimateUpperBound: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
        self.note = note
        self.isEstimated = isEstimated
        self.estimateLowerBound = estimateLowerBound
        self.estimateUpperBound = estimateUpperBound
    }
}

struct BodyMetricGoal: Identifiable, Codable, Hashable {
    var kind: BodyMetricKind
    var targetValue: Double?
    var direction: BodyMetricGoalDirection

    var id: BodyMetricKind { kind }

    init(
        kind: BodyMetricKind,
        targetValue: Double? = nil,
        direction: BodyMetricGoalDirection? = nil
    ) {
        self.kind = kind
        self.targetValue = targetValue
        self.direction = direction ?? kind.defaultGoalDirection
    }

    func delta(from currentValue: Double) -> Double? {
        guard let targetValue else {
            return nil
        }

        return currentValue - targetValue
    }

    func achievementRate(from currentValue: Double) -> Double? {
        guard let targetValue, targetValue > 0 else {
            return nil
        }

        switch direction {
        case .increase:
            return min(currentValue / targetValue, 1)
        case .decrease:
            guard currentValue > 0 else { return nil }
            return min(targetValue / currentValue, 1)
        }
    }
}
