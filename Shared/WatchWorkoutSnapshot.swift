import Foundation

struct WatchWorkoutPlanLibrarySnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var plans: [WatchWorkoutPlanSnapshot]
    var preferredPlanID: UUID?
    var userProfile: WatchUserProfileSnapshot?
    var sensorPreferences: WatchSensorPreferences?
    var appearanceSettings: AppAppearanceSettings?
    var dailyRecommendation: WatchDailyRecommendationSnapshot?

    init(
        generatedAt: Date = Date(),
        plans: [WatchWorkoutPlanSnapshot],
        preferredPlanID: UUID? = nil,
        userProfile: WatchUserProfileSnapshot? = nil,
        sensorPreferences: WatchSensorPreferences? = nil,
        appearanceSettings: AppAppearanceSettings? = nil,
        dailyRecommendation: WatchDailyRecommendationSnapshot? = nil
    ) {
        self.generatedAt = generatedAt
        self.plans = plans
        self.preferredPlanID = preferredPlanID
        self.userProfile = userProfile
        self.sensorPreferences = sensorPreferences
        self.appearanceSettings = appearanceSettings
        self.dailyRecommendation = dailyRecommendation
    }
}

struct WatchDailyRecommendationSnapshot: Codable, Hashable, Sendable {
    struct Action: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var systemImage: String
        var isCompleted: Bool
    }

    var date: Date
    var readiness: String
    var summary: String
    var actions: [Action]
    var preferredPlanID: UUID?
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
    var plannedConcentricSeconds: Int? = nil
    var plannedEccentricSeconds: Int? = nil
    var plannedTempoBeatSpeed: Int? = nil
    var previousActualWeight: Double? = nil
    var previousActualReps: Int? = nil
    var previousRPE: Double? = nil
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
