import Foundation

enum WatchHealthKitSaveStatus: String, Codable, Hashable, Sendable {
    case unavailable
    case permissionDenied
    case collecting
    case saved
    case failed
}

struct WatchWorkoutSensorSummary: Codable, Hashable, Sendable {
    var durationSeconds: Double
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var heartRateRecovery: Double?
    var completedSets: Int
    var estimatedReps: Int?
    var motionConfidence: Double?
    var heartRateZoneDurations: [Int: Double]?
}

struct WatchSetSensorSummary: Codable, Hashable, Sendable {
    var heartRateAtStart: Double?
    var heartRateAtEnd: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var heartRateRecovery: Double?
    var estimatedReps: Int?
    var averageRepDuration: Double?
    var movementConsistency: Double?
    var confidence: Double?
    var averageConcentricDuration: Double?
    var averageEccentricDuration: Double?
    var averagePauseDuration: Double?
    var relativeRangeOfMotion: Double?
    var rangeOfMotionConsistency: Double?
    var velocityLossPercent: Double?
    var exerciseCandidateName: String?
    var exerciseCandidateConfidence: Double?
}

struct WatchLiveWorkoutMetrics: Codable, Hashable, Sendable {
    var elapsedSeconds: Double = 0
    var distanceKilometers: Double?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var heartRateZone: Int?
    var heartRateZoneDurations: [Int: Double] = [:]

    static let empty = WatchLiveWorkoutMetrics()
}

struct WatchMotionEstimate: Equatable, Sendable {
    var estimatedReps: Int = 0
    var averageRepDuration: Double?
    var movementConsistency: Double?
    var confidence: Double = 0
    var averageConcentricDuration: Double?
    var averageEccentricDuration: Double?
    var averagePauseDuration: Double?
    var relativeRangeOfMotion: Double?
    var rangeOfMotionConsistency: Double?
    var velocityLossPercent: Double?
    var dominantAxis: String?
    var rotationalMovementRatio: Double?
    var isTempoDeviationDetected = false

    static let empty = WatchMotionEstimate()
}

struct WatchSetStartSuggestion: Equatable, Sendable {
    var exerciseID: UUID
    var setID: UUID
    var exerciseName: String
    var confidence: Double
    var reason: String
}

struct WatchNextSetLoadSuggestion: Equatable, Sendable {
    var exerciseID: UUID
    var setID: UUID
    var exerciseName: String
    var suggestedWeight: Double
    var suggestedReps: Int
    var reason: String
}
