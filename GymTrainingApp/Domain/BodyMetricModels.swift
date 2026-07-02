import Foundation

enum BodyMetricKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case bodyWeight
    case waist
    case bodyFatPercentage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyWeight: "体重"
        case .waist: "腹囲"
        case .bodyFatPercentage: "体脂肪率"
        }
    }

    var unit: String {
        switch self {
        case .bodyWeight: "kg"
        case .waist: "cm"
        case .bodyFatPercentage: "%"
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
        case .increase: "増やしたい"
        case .decrease: "減らしたい"
        }
    }
}

struct BodyMetricEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: BodyMetricKind
    var value: Double
    var recordedAt: Date
    var note: String

    init(
        id: UUID = UUID(),
        kind: BodyMetricKind,
        value: Double,
        recordedAt: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
        self.note = note
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
