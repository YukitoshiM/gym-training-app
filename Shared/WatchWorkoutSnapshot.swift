import Foundation

struct WatchWorkoutPlanLibrarySnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var plans: [WatchWorkoutPlanSnapshot]
    var preferredPlanID: UUID?
    var userProfile: WatchUserProfileSnapshot?
    var sensorPreferences: WatchSensorPreferences?

    init(
        generatedAt: Date = Date(),
        plans: [WatchWorkoutPlanSnapshot],
        preferredPlanID: UUID? = nil,
        userProfile: WatchUserProfileSnapshot? = nil,
        sensorPreferences: WatchSensorPreferences? = nil
    ) {
        self.generatedAt = generatedAt
        self.plans = plans
        self.preferredPlanID = preferredPlanID
        self.userProfile = userProfile
        self.sensorPreferences = sensorPreferences
    }
}

struct WatchUserProfileSnapshot: Codable, Hashable, Sendable {
    var birthYear: Int?
    var goalTypeRawValue: String
}

struct WatchSensorPreferences: Codable, Hashable, Sendable {
    var healthWorkoutEnabled: Bool
    var motionRepDetectionEnabled: Bool
    var adaptiveRestEnabled: Bool
    var hapticCoachingEnabled: Bool
    var reducedSensorSamplingEnabled: Bool

    static let `default` = WatchSensorPreferences(
        healthWorkoutEnabled: true,
        motionRepDetectionEnabled: true,
        adaptiveRestEnabled: true,
        hapticCoachingEnabled: true,
        reducedSensorSamplingEnabled: false
    )
}

struct WatchWorkoutPlanSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var generatedAt: Date
    var weightUnit: WatchWeightUnit
    var exercises: [WatchPlanExerciseSnapshot]

    init(
        id: UUID,
        name: String,
        generatedAt: Date = Date(),
        weightUnit: WatchWeightUnit,
        exercises: [WatchPlanExerciseSnapshot]
    ) {
        self.id = id
        self.name = name
        self.generatedAt = generatedAt
        self.weightUnit = weightUnit
        self.exercises = exercises
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalTargetRepCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { $0 + $1.targetReps }
        }
    }
}

struct WatchPlanExerciseSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var exerciseID: UUID?
    var name: String
    var primaryMuscleName: String
    var primaryMuscleRawValue: String?
    var equipmentRawValue: String?
    var restSeconds: Int
    var sets: [WatchPlanSetTargetSnapshot]
}

struct WatchPlanSetTargetSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var setOrder: Int
    var targetWeight: Double
    var targetReps: Int
}

enum WatchWeightUnit: String, Codable, Hashable, Sendable {
    case kg
    case lb

    var displayName: String {
        switch self {
        case .kg: "kg"
        case .lb: "lb"
        }
    }
}

enum WatchWorkoutTransfer {
    static let messageTypeKey = "type"
    static let payloadKey = "payload"
    static let eventIDKey = "event_id"
    static let sentAtKey = "sent_at"
    static let acknowledgementKey = "acknowledged"
    static let planPushType = "watch_plan_push"
    static let planLibraryPushType = "watch_plan_library_push"
    static let sessionFinishedType = "watch_session_finished"
}

struct WatchWorkoutSessionSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourcePlanID: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var weightUnit: WatchWeightUnit
    var exercises: [WatchWorkoutExerciseSnapshot]
    var sensorSummary: WatchWorkoutSensorSummary?
    var healthKitSaveStatus: WatchHealthKitSaveStatus?
    var note: String?

    init(
        id: UUID = UUID(),
        sourcePlanID: UUID?,
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        weightUnit: WatchWeightUnit,
        exercises: [WatchWorkoutExerciseSnapshot],
        sensorSummary: WatchWorkoutSensorSummary? = nil,
        healthKitSaveStatus: WatchHealthKitSaveStatus? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.sourcePlanID = sourcePlanID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.weightUnit = weightUnit
        self.exercises = exercises
        self.sensorSummary = sensorSummary
        self.healthKitSaveStatus = healthKitSaveStatus
        self.note = note
    }

    init(plan: WatchWorkoutPlanSnapshot) {
        self.init(
            sourcePlanID: plan.id,
            title: plan.name,
            weightUnit: plan.weightUnit,
            exercises: plan.exercises.enumerated().map { offset, exercise in
                WatchWorkoutExerciseSnapshot(planExercise: exercise, sortOrder: offset)
            }
        )
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    var completedRepCount: Int {
        exercises.reduce(0) { $0 + $1.completedRepCount }
    }

    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }

    var isAllSetsCompleted: Bool {
        totalSetCount > 0 && completedSetCount == totalSetCount
    }
}

struct WatchWorkoutExerciseSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var planExerciseID: UUID
    var exerciseID: UUID?
    var name: String
    var primaryMuscleName: String
    var primaryMuscleRawValue: String?
    var equipmentRawValue: String?
    var sortOrder: Int
    var restSeconds: Int
    var sets: [WatchWorkoutSetSnapshot]

    init(
        id: UUID = UUID(),
        planExerciseID: UUID,
        exerciseID: UUID?,
        name: String,
        primaryMuscleName: String,
        primaryMuscleRawValue: String?,
        equipmentRawValue: String?,
        sortOrder: Int,
        restSeconds: Int,
        sets: [WatchWorkoutSetSnapshot]
    ) {
        self.id = id
        self.planExerciseID = planExerciseID
        self.exerciseID = exerciseID
        self.name = name
        self.primaryMuscleName = primaryMuscleName
        self.primaryMuscleRawValue = primaryMuscleRawValue
        self.equipmentRawValue = equipmentRawValue
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.sets = sets
    }

    init(planExercise: WatchPlanExerciseSnapshot, sortOrder: Int) {
        self.init(
            planExerciseID: planExercise.id,
            exerciseID: planExercise.exerciseID,
            name: planExercise.name,
            primaryMuscleName: planExercise.primaryMuscleName,
            primaryMuscleRawValue: planExercise.primaryMuscleRawValue,
            equipmentRawValue: planExercise.equipmentRawValue,
            sortOrder: sortOrder,
            restSeconds: planExercise.restSeconds,
            sets: planExercise.sets.map { WatchWorkoutSetSnapshot(planSet: $0) }
        )
    }

    var totalVolume: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + $1.volume }
    }

    var completedSetCount: Int {
        sets.filter(\.isCompleted).count
    }

    var completedRepCount: Int {
        sets.filter(\.isCompleted).reduce(0) { $0 + $1.actualReps }
    }
}

struct WatchWorkoutSetSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var setOrder: Int
    var targetWeight: Double
    var targetReps: Int
    var actualWeight: Double
    var actualReps: Int
    var isCompleted: Bool
    var rpe: Double?
    var startedAt: Date?
    var completedAt: Date?
    var sensorSummary: WatchSetSensorSummary?
    var note: String?

    init(
        id: UUID = UUID(),
        setOrder: Int,
        targetWeight: Double,
        targetReps: Int,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        isCompleted: Bool = false,
        rpe: Double? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        sensorSummary: WatchSetSensorSummary? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.setOrder = setOrder
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.actualWeight = actualWeight ?? targetWeight
        self.actualReps = actualReps ?? targetReps
        self.isCompleted = isCompleted
        self.rpe = rpe
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.sensorSummary = sensorSummary
        self.note = note
    }

    init(planSet: WatchPlanSetTargetSnapshot) {
        self.init(
            setOrder: planSet.setOrder,
            targetWeight: planSet.targetWeight,
            targetReps: planSet.targetReps
        )
    }

    var volume: Double {
        actualWeight * Double(actualReps)
    }
}

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

struct WatchLiveWorkoutMetrics: Equatable, Sendable {
    var elapsedSeconds: Double = 0
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
