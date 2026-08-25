import Foundation

enum OutdoorCardioActivity: String, Codable, CaseIterable, Hashable, Sendable {
    case running
    case walking
    case cycling

    var localizedName: String {
        switch self {
        case .running:
            L10n.string("outdoor_cardio.running", fallback: "屋外ランニング")
        case .walking:
            L10n.string("outdoor_cardio.walking", fallback: "屋外ウォーキング")
        case .cycling:
            L10n.string("outdoor_cardio.cycling", fallback: "屋外サイクリング")
        }
    }
}

enum OutdoorCardioGoalKind: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case distance
    case duration
}

struct OutdoorCardioTarget: Codable, Hashable, Sendable {
    var kind: OutdoorCardioGoalKind
    var distanceKilometers: Double?
    var durationSeconds: Double?
    var targetPaceSecondsPerKilometer: Double?

    init(
        kind: OutdoorCardioGoalKind = .open,
        distanceKilometers: Double? = nil,
        durationSeconds: Double? = nil,
        targetPaceSecondsPerKilometer: Double? = nil
    ) {
        self.kind = kind
        self.distanceKilometers = distanceKilometers.map { max(0.1, $0) }
        self.durationSeconds = durationSeconds.map { max(60, $0) }
        self.targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer.map { max(60, $0) }
    }
}

struct OutdoorCardioSnapshot: Codable, Hashable, Sendable {
    var activity: OutdoorCardioActivity
    var target: OutdoorCardioTarget
    var distanceKilometers: Double
    var averagePaceSecondsPerKilometer: Double?
    var routePointCount: Int
    var routeStoredInHealthKit: Bool

    init(
        activity: OutdoorCardioActivity,
        target: OutdoorCardioTarget = OutdoorCardioTarget(),
        distanceKilometers: Double = 0,
        averagePaceSecondsPerKilometer: Double? = nil,
        routePointCount: Int = 0,
        routeStoredInHealthKit: Bool = false
    ) {
        self.activity = activity
        self.target = target
        self.distanceKilometers = max(0, distanceKilometers)
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.routePointCount = max(0, routePointCount)
        self.routeStoredInHealthKit = routeStoredInHealthKit
    }

    func progress(elapsedSeconds: Double) -> Double? {
        switch target.kind {
        case .open:
            return nil
        case .distance:
            guard let targetDistance = target.distanceKilometers, targetDistance > 0 else { return nil }
            return min(1, distanceKilometers / targetDistance)
        case .duration:
            guard let targetDuration = target.durationSeconds, targetDuration > 0 else { return nil }
            return min(1, max(0, elapsedSeconds) / targetDuration)
        }
    }

    func updating(distanceKilometers: Double, elapsedSeconds: Double) -> Self {
        var updated = self
        updated.distanceKilometers = max(0, distanceKilometers)
        if distanceKilometers > 0.01, elapsedSeconds > 0 {
            updated.averagePaceSecondsPerKilometer = elapsedSeconds / distanceKilometers
        }
        return updated
    }
}
