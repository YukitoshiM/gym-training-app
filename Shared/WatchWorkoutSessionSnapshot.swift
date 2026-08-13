import Foundation

enum WatchTempoPhase: String, Codable, Hashable, Sendable {
    case concentric
    case eccentric

    var displayName: String {
        switch self {
        case .concentric: "上げ"
        case .eccentric: "下げ"
        }
    }
}

enum WatchTempoHapticCue: String, Codable, Hashable, Sendable {
    case concentricStart
    case eccentricStart
    case beat
}

enum TempoAchievement: String, Codable, Hashable, Sendable {
    case onTarget
    case faster
    case slower
    case mixed
}

struct TempoPerformance: Codable, Hashable, Sendable {
    static let targetToleranceSeconds = 0.35

    var observedConcentricSeconds: Double
    var observedEccentricSeconds: Double
    var concentricDifferenceSeconds: Double
    var eccentricDifferenceSeconds: Double
    var achievement: TempoAchievement
    var wasManuallyCorrected: Bool

    init?(
        plannedConcentricSeconds: Int?,
        plannedEccentricSeconds: Int?,
        observedConcentricSeconds: Double?,
        observedEccentricSeconds: Double?,
        wasManuallyCorrected: Bool
    ) {
        guard let plannedConcentricSeconds,
              let plannedEccentricSeconds,
              let observedConcentricSeconds,
              let observedEccentricSeconds,
              observedConcentricSeconds.isFinite,
              observedEccentricSeconds.isFinite,
              observedConcentricSeconds > 0,
              observedEccentricSeconds > 0 else {
            return nil
        }

        let concentricDifference = observedConcentricSeconds - Double(plannedConcentricSeconds)
        let eccentricDifference = observedEccentricSeconds - Double(plannedEccentricSeconds)
        self.observedConcentricSeconds = observedConcentricSeconds
        self.observedEccentricSeconds = observedEccentricSeconds
        self.concentricDifferenceSeconds = concentricDifference
        self.eccentricDifferenceSeconds = eccentricDifference
        self.achievement = Self.achievement(
            concentricDifference: concentricDifference,
            eccentricDifference: eccentricDifference
        )
        self.wasManuallyCorrected = wasManuallyCorrected
    }

    private static func achievement(
        concentricDifference: Double,
        eccentricDifference: Double
    ) -> TempoAchievement {
        let differences = [concentricDifference, eccentricDifference]
        if differences.allSatisfy({ abs($0) <= targetToleranceSeconds }) {
            return .onTarget
        }
        if differences.allSatisfy({ $0 < -targetToleranceSeconds }) {
            return .faster
        }
        if differences.allSatisfy({ $0 > targetToleranceSeconds }) {
            return .slower
        }
        return .mixed
    }
}

struct WatchTempoTarget: Codable, Hashable, Sendable {
    var concentricSeconds: Int
    var eccentricSeconds: Int
    var repetitions: Int
    var beatSpeed: Int

    init?(concentricSeconds: Int?, eccentricSeconds: Int?, repetitions: Int, beatSpeed: Int = 1) {
        guard let concentricSeconds,
              let eccentricSeconds,
              (1...10).contains(concentricSeconds),
              (1...10).contains(eccentricSeconds),
              repetitions > 0,
              (1...3).contains(beatSpeed) else {
            return nil
        }
        self.concentricSeconds = concentricSeconds
        self.eccentricSeconds = eccentricSeconds
        self.repetitions = repetitions
        self.beatSpeed = beatSpeed
    }
}

struct WatchTempoCue: Codable, Hashable, Sendable {
    var phase: WatchTempoPhase
    var second: Int
    var phaseDuration: Int
    var repetition: Int
    var targetRepetitions: Int
    var beatSpeed: Int

    var displayText: String {
        "\(phase.displayName) \(second)/\(phaseDuration)・\(repetition)/\(targetRepetitions)回"
    }

    var hapticCue: WatchTempoHapticCue {
        guard second == 1 else { return .beat }
        return phase == .concentric ? .concentricStart : .eccentricStart
    }

    var shouldEmitBeat: Bool {
        return true
    }

    var hapticCount: Int {
        min(3, max(1, beatSpeed))
    }

    var hapticPattern: [WatchTempoHapticPulse] {
        let first: WatchTempoHapticPulse = switch hapticCue {
        case .concentricStart: .directionUp
        case .eccentricStart: .directionDown
        case .beat: .click
        }
        return [first] + Array(repeating: .click, count: hapticCount - 1)
    }

    var hapticIntervalNanoseconds: UInt64 {
        UInt64(1_000_000_000 / hapticCount)
    }
}

enum WatchTempoHapticPulse: String, Codable, Hashable, Sendable {
    case directionUp
    case directionDown
    case click
}

struct WatchTempoGuideState: Codable, Hashable, Sendable {
    let target: WatchTempoTarget
    private(set) var phase: WatchTempoPhase = .concentric
    private(set) var elapsedSeconds = 0
    private(set) var repetition = 1
    private(set) var isFinished = false
    private(set) var isPaused = false
    private(set) var isEnabled = true

    mutating func advance() -> WatchTempoCue? {
        guard isEnabled, !isPaused, !isFinished else { return nil }
        elapsedSeconds += 1
        let duration = phase == .concentric
            ? target.concentricSeconds
            : target.eccentricSeconds
        let cue = WatchTempoCue(
            phase: phase,
            second: elapsedSeconds,
            phaseDuration: duration,
            repetition: repetition,
            targetRepetitions: target.repetitions,
            beatSpeed: target.beatSpeed
        )
        guard elapsedSeconds >= duration else { return cue }
        moveToNextPhase()
        return cue
    }

    mutating func skipCurrentPhase() {
        guard isEnabled, !isFinished else { return }
        moveToNextPhase()
    }

    mutating func pause() {
        guard isEnabled, !isFinished else { return }
        isPaused = true
    }

    mutating func resume() {
        guard isEnabled, !isFinished else { return }
        isPaused = false
    }

    mutating func setEnabled(_ enabled: Bool) {
        guard !isFinished else { return }
        isEnabled = enabled
        if !enabled {
            isPaused = false
        }
    }

    private mutating func moveToNextPhase() {
        elapsedSeconds = 0
        if phase == .concentric {
            phase = .eccentric
        } else if repetition < target.repetitions {
            phase = .concentric
            repetition += 1
        } else {
            isFinished = true
            isPaused = false
        }
    }
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
        let supportsAssistedLoad = AssistedLoadSupport.isSupported(exerciseName: planExercise.name)
        self.init(
            planExerciseID: planExercise.id,
            exerciseID: planExercise.exerciseID,
            name: planExercise.name,
            primaryMuscleName: planExercise.primaryMuscleName,
            primaryMuscleRawValue: planExercise.primaryMuscleRawValue,
            equipmentRawValue: planExercise.equipmentRawValue,
            sortOrder: sortOrder,
            restSeconds: planExercise.restSeconds,
            sets: planExercise.sets.map {
                WatchWorkoutSetSnapshot(
                    planSet: $0,
                    supportsAssistedLoad: supportsAssistedLoad
                )
            }
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

    var supportsAssistedLoad: Bool {
        AssistedLoadSupport.isSupported(exerciseName: name)
    }

    var isDipExercise: Bool {
        AssistedLoadSupport.isDip(exerciseName: name)
    }
}

enum AssistedLoadSupport {
    static let kilogramRange: ClosedRange<Double> = -300...999

    static func isSupported(exerciseName: String) -> Bool {
        isDip(exerciseName: exerciseName)
            || containsAny(
                exerciseName,
                keywords: ["チンニング", "懸垂", "chin-up", "chin up", "pull-up", "pull up"]
            )
    }

    static func isDip(exerciseName: String) -> Bool {
        containsAny(exerciseName, keywords: ["ディップ", "dip"])
    }

    private static func containsAny(_ exerciseName: String, keywords: [String]) -> Bool {
        let normalizedName = exerciseName.lowercased()
        return keywords.contains { normalizedName.contains($0) }
    }
}

struct WatchWorkoutSetSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var setOrder: Int
    var targetWeight: Double
    var targetReps: Int
    var plannedConcentricSeconds: Int?
    var plannedEccentricSeconds: Int?
    var plannedTempoBeatSpeed: Int?
    var actualWeight: Double
    var actualReps: Int
    var hasUserAdjustedWeight: Bool?
    var isCompleted: Bool
    var rpe: Double?
    var startedAt: Date?
    var completedAt: Date?
    var sensorSummary: WatchSetSensorSummary?
    var tempoPerformance: TempoPerformance?
    var note: String?

    init(
        id: UUID = UUID(),
        setOrder: Int,
        targetWeight: Double,
        targetReps: Int,
        plannedConcentricSeconds: Int? = nil,
        plannedEccentricSeconds: Int? = nil,
        plannedTempoBeatSpeed: Int? = nil,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        hasUserAdjustedWeight: Bool? = nil,
        isCompleted: Bool = false,
        rpe: Double? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        sensorSummary: WatchSetSensorSummary? = nil,
        tempoPerformance: TempoPerformance? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.setOrder = setOrder
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.plannedConcentricSeconds = plannedConcentricSeconds
        self.plannedEccentricSeconds = plannedEccentricSeconds
        self.plannedTempoBeatSpeed = plannedTempoBeatSpeed
        self.actualWeight = actualWeight ?? targetWeight
        self.actualReps = actualReps ?? targetReps
        self.hasUserAdjustedWeight = hasUserAdjustedWeight
        self.isCompleted = isCompleted
        self.rpe = rpe
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.sensorSummary = sensorSummary
        self.tempoPerformance = tempoPerformance ?? TempoPerformance(
            plannedConcentricSeconds: plannedConcentricSeconds,
            plannedEccentricSeconds: plannedEccentricSeconds,
            observedConcentricSeconds: sensorSummary?.averageConcentricDuration,
            observedEccentricSeconds: sensorSummary?.averageEccentricDuration,
            wasManuallyCorrected: false
        )
        self.note = note
    }

    init(planSet: WatchPlanSetTargetSnapshot, supportsAssistedLoad: Bool = false) {
        self.init(
            setOrder: planSet.setOrder,
            targetWeight: planSet.targetWeight,
            targetReps: planSet.targetReps,
            plannedConcentricSeconds: planSet.plannedConcentricSeconds,
            plannedEccentricSeconds: planSet.plannedEccentricSeconds,
            plannedTempoBeatSpeed: planSet.plannedTempoBeatSpeed,
            actualWeight: planSet.targetWeight,
            actualReps: planSet.targetReps,
            rpe: planSet.previousRPE
        )
    }

    var resolvedTempoBeatSpeed: Int {
        min(3, max(1, plannedTempoBeatSpeed ?? 1))
    }

    var volume: Double {
        actualWeight * Double(actualReps)
    }
}
