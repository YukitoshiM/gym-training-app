import Foundation

struct TrainingPlan: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var exercises: [PlanExercise]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        exercises: [PlanExercise] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}

struct PlanExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exercise: Exercise
    var sortOrder: Int
    var restSeconds: Int
    var sets: [PlanSetTarget]

    init(
        id: UUID = UUID(),
        exercise: Exercise,
        sortOrder: Int,
        restSeconds: Int = 90,
        sets: [PlanSetTarget] = PlanSetTarget.defaultSets()
    ) {
        self.id = id
        self.exercise = exercise
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

struct PlanSetTarget: Identifiable, Codable, Hashable {
    var id: UUID
    var setOrder: Int
    var targetWeight: Double
    var targetReps: Int

    init(
        id: UUID = UUID(),
        setOrder: Int,
        targetWeight: Double,
        targetReps: Int
    ) {
        self.id = id
        self.setOrder = setOrder
        self.targetWeight = targetWeight
        self.targetReps = targetReps
    }

    static func defaultSets() -> [PlanSetTarget] {
        (1...3).map {
            PlanSetTarget(setOrder: $0, targetWeight: 20, targetReps: 10)
        }
    }
}

struct WorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var sourcePlanID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var exercises: [WorkoutExercise]

    init(
        id: UUID = UUID(),
        title: String,
        sourcePlanID: UUID?,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        exercises: [WorkoutExercise]
    ) {
        self.id = id
        self.title = title
        self.sourcePlanID = sourcePlanID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
    }

    var isCompleted: Bool {
        endedAt != nil
    }

    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }

    var achievementRate: Double {
        let plannedExercises = exercises.filter { !$0.isSkipped }
        guard !plannedExercises.isEmpty else { return 0 }
        let total = plannedExercises.reduce(0) { $0 + $1.achievementRate }
        return total / Double(plannedExercises.count)
    }
}

struct WorkoutExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var exercise: Exercise
    var sortOrder: Int
    var restSeconds: Int
    var isSkipped: Bool
    var sets: [WorkoutSet]

    init(
        id: UUID = UUID(),
        exercise: Exercise,
        sortOrder: Int,
        restSeconds: Int,
        isSkipped: Bool = false,
        sets: [WorkoutSet]
    ) {
        self.id = id
        self.exercise = exercise
        self.sortOrder = sortOrder
        self.restSeconds = restSeconds
        self.isSkipped = isSkipped
        self.sets = sets
    }

    var totalVolume: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + $1.volume }
    }

    var achievementRate: Double {
        guard !isSkipped else { return 0 }
        let plannedSets = sets.filter { !$0.isAdded }
        guard !plannedSets.isEmpty else { return 0 }
        let total = plannedSets.reduce(0) { $0 + $1.achievementRate }
        return total / Double(plannedSets.count)
    }
}

struct WorkoutSet: Identifiable, Codable, Hashable {
    var id: UUID
    var setOrder: Int
    var targetWeight: Double
    var targetReps: Int
    var actualWeight: Double
    var actualReps: Int
    var isCompleted: Bool
    var isAdded: Bool

    init(
        id: UUID = UUID(),
        setOrder: Int,
        targetWeight: Double,
        targetReps: Int,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        isCompleted: Bool = false,
        isAdded: Bool = false
    ) {
        self.id = id
        self.setOrder = setOrder
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.actualWeight = actualWeight ?? targetWeight
        self.actualReps = actualReps ?? targetReps
        self.isCompleted = isCompleted
        self.isAdded = isAdded
    }

    var repsDelta: Int {
        actualReps - targetReps
    }

    var weightDelta: Double {
        actualWeight - targetWeight
    }

    var volume: Double {
        actualWeight * Double(actualReps)
    }

    var achievementRate: Double {
        guard targetReps > 0 else { return 0 }
        return min(Double(actualReps) / Double(targetReps), 1)
    }

    var isAchieved: Bool {
        actualReps >= targetReps && actualWeight >= targetWeight
    }
}

extension WorkoutSession {
    init(plan: TrainingPlan) {
        let workoutExercises = plan.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { planExercise in
                WorkoutExercise(
                    exercise: planExercise.exercise,
                    sortOrder: planExercise.sortOrder,
                    restSeconds: planExercise.restSeconds,
                    sets: planExercise.sets
                        .sorted { $0.setOrder < $1.setOrder }
                        .map {
                            WorkoutSet(
                                setOrder: $0.setOrder,
                                targetWeight: $0.targetWeight,
                                targetReps: $0.targetReps
                            )
                        }
                )
            }

        self.init(
            title: plan.name,
            sourcePlanID: plan.id,
            exercises: workoutExercises
        )
    }
}

