import Foundation

struct SensorSettings: Codable, Equatable {
    var healthIntegrationEnabled: Bool
    var motionRepDetectionEnabled: Bool
    var adaptiveRestEnabled: Bool
    var hapticCoachingEnabled: Bool
    var reducedSensorSamplingEnabled: Bool
    var gymVisitDetectionEnabled: Bool
    var includeSensorDataInAI: Bool

    static let `default` = SensorSettings(
        healthIntegrationEnabled: true,
        motionRepDetectionEnabled: true,
        adaptiveRestEnabled: true,
        hapticCoachingEnabled: true,
        reducedSensorSamplingEnabled: false,
        gymVisitDetectionEnabled: false,
        includeSensorDataInAI: false
    )
}

enum HealthAccessState: Equatable {
    case unavailable
    case notRequested
    case requesting
    case ready
    case deniedOrLimited
    case failed(String)

    var title: String {
        switch self {
        case .unavailable: "この端末では利用できません"
        case .notRequested: "未連携"
        case .requesting: "連携を確認中"
        case .ready: "連携済み"
        case .deniedOrLimited: "一部データを取得できません"
        case .failed: "取得に失敗しました"
        }
    }
}

struct HealthMetricValue: Equatable {
    var value: Double
    var recordedAt: Date?
}

struct ActivityProgress: Equatable {
    var moveKilocalories: Double?
    var moveGoalKilocalories: Double?
    var exerciseMinutes: Double?
    var exerciseGoalMinutes: Double?
    var standHours: Double?
    var standGoalHours: Double?
}

struct DailyHealthSnapshot: Equatable {
    var generatedAt: Date
    var steps: Double?
    var activeEnergyKilocalories: Double?
    var restingEnergyKilocalories: Double?
    var walkingRunningDistanceKilometers: Double?
    var flightsClimbed: Double?
    var sleepHours: Double?
    var sleepSummary: SleepSummary?
    var restingHeartRate: HealthMetricValue?
    var heartRateVariabilityMilliseconds: HealthMetricValue?
    var respiratoryRate: HealthMetricValue?
    var wristTemperatureCelsius: HealthMetricValue?
    var environmentalAudioExposureDecibels: HealthMetricValue?
    var heartRateRecovery: HealthMetricValue?
    var activityProgress: ActivityProgress?
    var baselines: RecoveryBaselines
    var latestOutdoorRoute: OutdoorWorkoutRouteSummary?

    static let empty = DailyHealthSnapshot(
        generatedAt: Date(),
        baselines: RecoveryBaselines()
    )

    init(
        generatedAt: Date,
        steps: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        restingEnergyKilocalories: Double? = nil,
        walkingRunningDistanceKilometers: Double? = nil,
        flightsClimbed: Double? = nil,
        sleepHours: Double? = nil,
        sleepSummary: SleepSummary? = nil,
        restingHeartRate: HealthMetricValue? = nil,
        heartRateVariabilityMilliseconds: HealthMetricValue? = nil,
        respiratoryRate: HealthMetricValue? = nil,
        wristTemperatureCelsius: HealthMetricValue? = nil,
        environmentalAudioExposureDecibels: HealthMetricValue? = nil,
        heartRateRecovery: HealthMetricValue? = nil,
        activityProgress: ActivityProgress? = nil,
        baselines: RecoveryBaselines = RecoveryBaselines(),
        latestOutdoorRoute: OutdoorWorkoutRouteSummary? = nil
    ) {
        self.generatedAt = generatedAt
        self.steps = steps
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.restingEnergyKilocalories = restingEnergyKilocalories
        self.walkingRunningDistanceKilometers = walkingRunningDistanceKilometers
        self.flightsClimbed = flightsClimbed
        self.sleepHours = sleepHours
        self.sleepSummary = sleepSummary
        self.restingHeartRate = restingHeartRate
        self.heartRateVariabilityMilliseconds = heartRateVariabilityMilliseconds
        self.respiratoryRate = respiratoryRate
        self.wristTemperatureCelsius = wristTemperatureCelsius
        self.environmentalAudioExposureDecibels = environmentalAudioExposureDecibels
        self.heartRateRecovery = heartRateRecovery
        self.activityProgress = activityProgress
        self.baselines = baselines
        self.latestOutdoorRoute = latestOutdoorRoute
    }
}

struct OutdoorWorkoutRouteSummary: Equatable {
    var workoutID: UUID
    var startedAt: Date
    var durationSeconds: Double
    var distanceKilometers: Double?
    var averageSpeedKilometersPerHour: Double?
    var elevationGainMeters: Double?
    var points: [OutdoorRoutePoint]
}

struct OutdoorRoutePoint: Equatable {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var recordedAt: Date
}

struct RecoveryBaselines: Equatable {
    var restingHeartRate: Double?
    var heartRateVariabilityMilliseconds: Double?
    var wristTemperatureCelsius: Double?
    var respiratoryRate: Double?
}

struct SleepSummary: Equatable {
    var totalHours: Double
    var coreHours: Double?
    var deepHours: Double?
    var remHours: Double?
    var awakeHours: Double?
    var interruptionCount: Int?
    var qualityScore: Int?
    var hasDetailedStages: Bool
}

struct SubjectiveRecoveryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var recordedAt: Date
    var fatigueLevel: Int

    init(id: UUID = UUID(), recordedAt: Date = Date(), fatigueLevel: Int) {
        self.id = id
        self.recordedAt = recordedAt
        self.fatigueLevel = min(5, max(1, fatigueLevel))
    }
}

struct DailyRecoveryTrendRecord: Identifiable, Codable, Equatable {
    var date: Date
    var sleepHours: Double?
    var restingHeartRateDelta: Double?
    var hrvRatio: Double?
    var activeEnergyKilocalories: Double?

    var id: Date { date }
}

struct ReadinessAssessment: Equatable {
    enum Level: String {
        case good
        case moderate
        case recover

        var title: String {
            switch self {
            case .good: "良好"
            case .moderate: "通常"
            case .recover: "回復優先"
            }
        }
    }

    var score: Int?
    var level: Level
    var summary: String
    var factors: [String]
    var availableFactorCount: Int
}

struct WorkoutSensorSummary: Codable, Hashable {
    var durationSeconds: Double
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var heartRateRecovery: Double?
    var estimatedReps: Int?
    var motionConfidence: Double?
    var heartRateZoneDurations: [Int: Double]?
}

struct SetSensorSummary: Codable, Hashable {
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

enum HealthWorkoutSaveState: String, Codable, Hashable {
    case unavailable
    case permissionDenied
    case collecting
    case saved
    case failed
}

struct DailyWorkoutSelection: Codable, Equatable {
    var date: Date
    var planID: UUID
}

struct GymLocation: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
}

struct GymVisit: Identifiable, Codable, Equatable {
    var id: UUID
    var arrivedAt: Date
    var departedAt: Date?
    var source: String

    init(id: UUID = UUID(), arrivedAt: Date = Date(), departedAt: Date? = nil, source: String) {
        self.id = id
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.source = source
    }
}
