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
    var sourceDevice: WorkoutSourceDevice?
    var watchSyncState: WatchSyncState?
    var sensorSummary: WorkoutSensorSummary?
    var healthWorkoutSaveState: HealthWorkoutSaveState?
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        sourcePlanID: UUID?,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        exercises: [WorkoutExercise],
        sourceDevice: WorkoutSourceDevice? = nil,
        watchSyncState: WatchSyncState? = nil,
        sensorSummary: WorkoutSensorSummary? = nil,
        healthWorkoutSaveState: HealthWorkoutSaveState? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourcePlanID = sourcePlanID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.sourceDevice = sourceDevice
        self.watchSyncState = watchSyncState
        self.sensorSummary = sensorSummary
        self.healthWorkoutSaveState = healthWorkoutSaveState
        self.note = note
    }

    var isCompleted: Bool {
        endedAt != nil
    }

    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }

    var plannedSetCount: Int {
        exercises.reduce(0) { $0 + $1.plannedSetCount }
    }

    var completedPlannedSetCount: Int {
        exercises.reduce(0) { $0 + $1.completedPlannedSetCount }
    }

    var achievedPlannedSetCount: Int {
        exercises.reduce(0) { $0 + $1.achievedPlannedSetCount }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.completedSetCount }
    }

    var completedRepCount: Int {
        exercises.reduce(0) { $0 + $1.completedRepCount }
    }

    var targetVolume: Double {
        exercises.reduce(0) { $0 + $1.targetVolume }
    }

    var actualPlannedVolume: Double {
        exercises.reduce(0) { $0 + $1.actualPlannedVolume }
    }

    var volumeDelta: Double {
        actualPlannedVolume - targetVolume
    }

    var achievementRate: Double {
        let plannedSets = exercises
            .filter { !$0.isSkipped }
            .flatMap(\.plannedSets)
        guard !plannedSets.isEmpty else { return 0 }
        let total = plannedSets.reduce(0) { $0 + $1.achievementRate }
        return total / Double(plannedSets.count)
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

    var plannedSets: [WorkoutSet] {
        sets.filter { !$0.isAdded }
    }

    var plannedSetCount: Int {
        isSkipped ? 0 : plannedSets.count
    }

    var completedPlannedSetCount: Int {
        isSkipped ? 0 : plannedSets.filter(\.isCompleted).count
    }

    var achievedPlannedSetCount: Int {
        isSkipped ? 0 : plannedSets.filter(\.isAchieved).count
    }

    var completedSetCount: Int {
        isSkipped ? 0 : sets.filter(\.isCompleted).count
    }

    var completedRepCount: Int {
        guard !isSkipped else { return 0 }
        return sets.filter(\.isCompleted).reduce(0) { $0 + $1.actualReps }
    }

    var targetVolume: Double {
        guard !isSkipped else { return 0 }
        return plannedSets.reduce(0) { $0 + $1.targetVolume }
    }

    var actualPlannedVolume: Double {
        guard !isSkipped else { return 0 }
        return plannedSets.filter(\.isCompleted).reduce(0) { $0 + $1.volume }
    }

    var volumeDelta: Double {
        actualPlannedVolume - targetVolume
    }

    var achievementRate: Double {
        guard !isSkipped else { return 0 }
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
    var rpe: Double?
    var startedAt: Date?
    var completedAt: Date?
    var sensorSummary: SetSensorSummary?
    var note: String?

    init(
        id: UUID = UUID(),
        setOrder: Int,
        targetWeight: Double,
        targetReps: Int,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        isCompleted: Bool = false,
        isAdded: Bool = false,
        rpe: Double? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        sensorSummary: SetSensorSummary? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.setOrder = setOrder
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.actualWeight = actualWeight ?? targetWeight
        self.actualReps = actualReps ?? targetReps
        self.isCompleted = isCompleted
        self.isAdded = isAdded
        self.rpe = rpe
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.sensorSummary = sensorSummary
        self.note = note
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

    var targetVolume: Double {
        targetWeight * Double(targetReps)
    }

    var duration: TimeInterval? {
        guard let startedAt, let completedAt, completedAt >= startedAt else {
            return nil
        }

        return completedAt.timeIntervalSince(startedAt)
    }

    var achievementRate: Double {
        guard isCompleted else { return 0 }
        guard targetReps > 0 else { return 0 }
        let repsRate = min(Double(actualReps) / Double(targetReps), 1)
        guard targetWeight > 0 else {
            return repsRate
        }
        let weightRate = min(actualWeight / targetWeight, 1)
        return min(weightRate, repsRate)
    }

    var isAchieved: Bool {
        isCompleted && actualReps >= targetReps && actualWeight >= targetWeight
    }
}

enum WorkoutSourceDevice: String, Codable, Hashable {
    case iPhone
    case appleWatch

    var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .appleWatch: "Apple Watch"
        }
    }
}

enum WatchSyncState: String, Codable, Hashable {
    case pending
    case sent
    case received
    case failed
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
