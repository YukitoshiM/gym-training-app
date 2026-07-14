import Foundation

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
}

struct WatchPlanExerciseSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var primaryMuscleName: String
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
    static let planPushType = "watch_plan_push"
}
