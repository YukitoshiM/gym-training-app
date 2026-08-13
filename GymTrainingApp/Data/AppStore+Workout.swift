import SwiftUI

@MainActor
extension AppStore {
    var allExercises: [Exercise] {
        (PresetExerciseStore.exercises + customExercises)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func savePlan(_ plan: TrainingPlan) {
        var nextPlan = plan
        nextPlan.updatedAt = Date()

        if let index = plans.firstIndex(where: { $0.id == nextPlan.id }) {
            plans[index] = nextPlan
        } else {
            plans.append(nextPlan)
        }

        plans.sort { $0.updatedAt > $1.updatedAt }
        storage.savePlans(plans)
        UsageAnalytics.shared.record(.planSaved)
    }

    func makeBeginnerStarterPlan() -> TrainingPlan {
        let exercises = beginnerPlanExercises(
            muscleGroups: [.quadriceps, .chest, .back],
            setCount: 2,
            targetReps: 10,
            restSeconds: 90,
            maximumExerciseCount: 3
        )

        return TrainingPlan(
            name: "初心者 全身スタート",
            exercises: exercises
        )
    }

    func makeBeginnerProgramRecommendations() -> [BeginnerProgramRecommendation] {
        let progress = BeginnerJourneyProgress(
            hasPlan: !plans.isEmpty,
            completedWorkoutCount: workoutHistory.filter(\.isCompleted).count
        )
        guard progress.isFoundationComplete else { return [] }

        let prescription = beginnerPrescription(for: userProfile.goalType)
        let maximumExerciseCount: Int = if userProfile.preferredSessionMinutes <= 30 {
            3
        } else if userProfile.preferredSessionMinutes <= 60 {
            4
        } else {
            5
        }
        let requestedPlanCount = min(3, max(1, userProfile.weeklyTrainingDays))

        return beginnerTemplates(for: userProfile.goalType)
            .prefix(requestedPlanCount)
            .enumerated()
            .compactMap { index, template in
                let focusGroups = userProfile.focusMuscles + template.muscleGroups
                let groups = focusGroups.reduce(into: [MuscleGroup]()) { result, group in
                    if !result.contains(group) {
                        result.append(group)
                    }
                }
                let exercises = beginnerPlanExercises(
                    muscleGroups: groups,
                    setCount: prescription.setCount,
                    targetReps: prescription.targetReps,
                    restSeconds: prescription.restSeconds,
                    maximumExerciseCount: maximumExerciseCount
                )
                guard !exercises.isEmpty else { return nil }

                let title = "LEVEL \(progress.level) \(template.title)"
                let equipmentNames = Array(Set(exercises.map { $0.exercise.equipment.displayName }))
                    .sorted()
                    .joined(separator: "・")
                let detail = "\(exercises.count)種目・\(exercises.reduce(0) { $0 + $1.sets.count })セット・\(equipmentNames)"
                return BeginnerProgramRecommendation(
                    id: "level-\(progress.level)-\(index)-\(template.title)",
                    level: progress.level,
                    title: title,
                    detail: detail,
                    plan: TrainingPlan(name: title, exercises: exercises)
                )
            }
    }

    func deletePlans(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            plans.remove(at: offset)
        }
        storage.savePlans(plans)
    }

    func finishWorkout(_ session: WorkoutSession) {
        var completedSession = session
        completedSession.endedAt = Date()

        if let index = workoutHistory.firstIndex(where: { $0.id == completedSession.id }) {
            workoutHistory[index] = completedSession
        } else {
            workoutHistory.insert(completedSession, at: 0)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        storage.saveWorkoutHistory(workoutHistory)
        UsageAnalytics.shared.record(.workoutCompleted)
    }

    func deleteWorkoutHistory(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            workoutHistory.remove(at: offset)
        }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func deleteWorkout(_ session: WorkoutSession) {
        workoutHistory.removeAll { $0.id == session.id }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func workoutSessions(on date: Date = Date()) -> [WorkoutSession] {
        workoutHistory
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func saveWorkoutHistorySession(_ session: WorkoutSession) {
        if let index = workoutHistory.firstIndex(where: { $0.id == session.id }) {
            workoutHistory[index] = session
        } else {
            workoutHistory.append(session)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func saveCustomExercise(_ exercise: Exercise) {
        if let index = customExercises.firstIndex(where: { $0.id == exercise.id }) {
            customExercises[index] = exercise
        } else {
            customExercises.append(exercise)
        }

        customExercises.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        storage.saveCustomExercises(customExercises)
    }

    func deleteCustomExercises(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            customExercises.remove(at: offset)
        }
        storage.saveCustomExercises(customExercises)
    }

    func latestCompletedExercise(for exercise: Exercise) -> WorkoutExercise? {
        for session in workoutHistory {
            guard let workoutExercise = session.exercises.first(where: { $0.exercise.name == exercise.name }) else {
                continue
            }

            if workoutExercise.sets.contains(where: \.isCompleted) {
                return workoutExercise
            }
        }

        return nil
    }

    func latestCompletedSets(for exercise: Exercise) -> [WorkoutSet] {
        latestCompletedExercise(for: exercise)?
            .sets
            .filter(\.isCompleted)
            .sorted { $0.setOrder < $1.setOrder } ?? []
    }

    func latestRestSeconds(for exercise: Exercise) -> Int? {
        guard let restSeconds = latestCompletedExercise(for: exercise)?.restSeconds,
              restSeconds > 0 else {
            return nil
        }

        return restSeconds
    }

    func makeWorkoutSession(from plan: TrainingPlan) -> WorkoutSession {
        let exercises = plan.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { planExercise in
                makeWorkoutExercise(
                    for: planExercise.exercise,
                    sortOrder: planExercise.sortOrder,
                    restSeconds: planExercise.restSeconds,
                    planSets: planExercise.sets
                )
            }

        return WorkoutSession(
            title: plan.name,
            sourcePlanID: plan.id,
            exercises: exercises
        )
    }

    func makeWorkoutExercise(
        for exercise: Exercise,
        sortOrder: Int,
        restSeconds: Int = 90,
        planSets: [PlanSetTarget]? = nil
    ) -> WorkoutExercise {
        let previousExercise = latestCompletedExercise(for: exercise)
        let previousSets = previousExercise?
            .sets
            .filter(\.isCompleted)
            .sorted { $0.setOrder < $1.setOrder } ?? []
        let targets = planSets?.sorted { $0.setOrder < $1.setOrder }
            ?? suggestedPlanSets(from: previousSets, exercise: exercise)

        let sets = targets.map { target in
            let previous = previousSets.first { $0.setOrder == target.setOrder } ?? previousSets.last
            return WorkoutSet(
                setOrder: target.setOrder,
                targetWeight: target.targetWeight,
                targetReps: target.targetReps,
                plannedConcentricSeconds: target.plannedConcentricSeconds,
                plannedEccentricSeconds: target.plannedEccentricSeconds,
                plannedTempoBeatSpeed: target.plannedTempoBeatSpeed,
                actualWeight: reusableWeight(previous?.actualWeight, for: exercise) ?? target.targetWeight,
                actualReps: positiveValue(previous?.actualReps) ?? target.targetReps,
                rpe: previous?.rpe
            )
        }

        return WorkoutExercise(
            exercise: exercise,
            sortOrder: sortOrder,
            restSeconds: positiveValue(previousExercise?.restSeconds) ?? restSeconds,
            sets: sets
        )
    }

    private func suggestedPlanSets(
        from previousSets: [WorkoutSet],
        exercise: Exercise
    ) -> [PlanSetTarget] {
        let setCount = max(previousSets.count, 3)
        return (1...setCount).map { setOrder in
            let previous = previousSets.first { $0.setOrder == setOrder } ?? previousSets.last
            return PlanSetTarget(
                setOrder: setOrder,
                targetWeight: reusableWeight(previous?.actualWeight, for: exercise)
                    ?? (exercise.supportsAssistedLoad ? 0 : 50),
                targetReps: positiveValue(previous?.actualReps) ?? 10
            )
        }
    }

    private func positiveValue(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func reusableWeight(_ value: Double?, for exercise: Exercise) -> Double? {
        guard let value, value.isFinite else { return nil }
        if exercise.supportsAssistedLoad {
            return min(
                exercise.weightInputRange.upperBound,
                max(exercise.weightInputRange.lowerBound, value)
            )
        }
        return positiveValue(value)
    }

    private func positiveValue(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func beginnerPlanExercises(
        muscleGroups: [MuscleGroup],
        setCount: Int,
        targetReps: Int,
        restSeconds: Int,
        maximumExerciseCount: Int
    ) -> [PlanExercise] {
        let allowedEquipment = Set(userProfile.availableEquipment)
        var usedExerciseIDs = Set<UUID>()
        var selectedExercises: [Exercise] = []

        for muscleGroup in muscleGroups where selectedExercises.count < maximumExerciseCount {
            let candidates = allExercises.filter { exercise in
                allowedEquipment.contains(exercise.equipment)
                    && !usedExerciseIDs.contains(exercise.id)
                    && exercise.matches(muscle: muscleGroup)
            }
            guard let exercise = candidates.min(by: {
                beginnerPreferenceRank($0, for: muscleGroup) < beginnerPreferenceRank($1, for: muscleGroup)
            }) else {
                continue
            }
            selectedExercises.append(exercise)
            usedExerciseIDs.insert(exercise.id)
        }

        if selectedExercises.isEmpty,
           let fallback = allExercises.first(where: { allowedEquipment.contains($0.equipment) }) {
            selectedExercises = [fallback]
        }

        return selectedExercises.enumerated().map { index, exercise in
            let previousSets = latestCompletedSets(for: exercise)
            let achievedPreviousTarget = previousSets.count >= setCount
                && previousSets.prefix(setCount).allSatisfy { $0.actualReps >= targetReps }
            let weightIncrement = achievedPreviousTarget ? beginnerWeightIncrement(for: exercise) : 0
            let progressedReps = exercise.equipment == .bodyweight && achievedPreviousTarget
                ? min(30, targetReps + 1)
                : targetReps
            let sets = (1...setCount).map { setOrder in
                let previous = previousSets.first { $0.setOrder == setOrder } ?? previousSets.last
                let baseWeight = previous?.actualWeight ?? beginnerDefaultWeight(for: exercise)
                let targetWeight = min(
                    exercise.weightInputRange.upperBound,
                    max(exercise.weightInputRange.lowerBound, baseWeight + weightIncrement)
                )
                return PlanSetTarget(
                    setOrder: setOrder,
                    targetWeight: targetWeight,
                    targetReps: progressedReps
                )
            }
            return PlanExercise(
                exercise: exercise,
                sortOrder: index,
                restSeconds: latestRestSeconds(for: exercise) ?? restSeconds,
                sets: sets
            )
        }
    }

    private func beginnerPrescription(for goal: GoalType) -> (setCount: Int, targetReps: Int, restSeconds: Int) {
        switch goal {
        case .muscleGain, .bodyShape:
            (3, 10, 90)
        case .performance:
            (3, 8, 120)
        case .diet, .health:
            (2, 12, 60)
        }
    }

    private func beginnerTemplates(for goal: GoalType) -> [BeginnerProgramTemplate] {
        switch goal {
        case .muscleGain, .bodyShape:
            [
                BeginnerProgramTemplate(title: "上半身", muscleGroups: [.chest, .back, .shoulders, .arms]),
                BeginnerProgramTemplate(title: "下半身", muscleGroups: [.quadriceps, .hamstrings, .glutes, .calves]),
                BeginnerProgramTemplate(title: "全身", muscleGroups: [.quadriceps, .chest, .back, .core])
            ]
        case .performance:
            [
                BeginnerProgramTemplate(title: "筋力A", muscleGroups: [.quadriceps, .chest, .back, .core]),
                BeginnerProgramTemplate(title: "筋力B", muscleGroups: [.hamstrings, .shoulders, .back, .glutes]),
                BeginnerProgramTemplate(title: "全身", muscleGroups: [.quadriceps, .chest, .back, .core])
            ]
        case .diet, .health:
            [
                BeginnerProgramTemplate(title: "全身A", muscleGroups: [.quadriceps, .chest, .back, .core]),
                BeginnerProgramTemplate(title: "全身B", muscleGroups: [.glutes, .shoulders, .back, .core]),
                BeginnerProgramTemplate(title: "全身C", muscleGroups: [.hamstrings, .chest, .back, .calves])
            ]
        }
    }

    private func beginnerPreferenceRank(_ exercise: Exercise, for muscleGroup: MuscleGroup) -> Int {
        let preferredNames = beginnerPreferredExerciseNames[muscleGroup] ?? []
        let nameRank = preferredNames.firstIndex(of: exercise.name).map { $0 * 10 } ?? 500
        let equipmentRank = beginnerEquipmentRank[exercise.equipment] ?? 20
        return nameRank + equipmentRank
    }

    private func beginnerDefaultWeight(for exercise: Exercise) -> Double {
        if exercise.supportsAssistedLoad { return 0 }
        return switch exercise.equipment {
        case .barbell, .smithMachine, .machine: 20
        case .dumbbell, .kettlebell: 8
        case .cable: 10
        case .resistanceBand, .suspension, .bodyweight, .other: 0
        }
    }

    private func beginnerWeightIncrement(for exercise: Exercise) -> Double {
        if exercise.supportsAssistedLoad { return 2.5 }
        return switch exercise.equipment {
        case .barbell, .smithMachine, .machine: 2.5
        case .dumbbell, .cable, .kettlebell: 1
        case .resistanceBand, .suspension, .bodyweight, .other: 0
        }
    }

}

private struct BeginnerProgramTemplate {
    let title: String
    let muscleGroups: [MuscleGroup]
}

private let beginnerEquipmentRank: [Equipment: Int] = [
    .machine: 0,
    .cable: 1,
    .dumbbell: 2,
    .bodyweight: 3,
    .smithMachine: 4,
    .barbell: 5,
    .resistanceBand: 6,
    .kettlebell: 7,
    .suspension: 8,
    .other: 9
]

private let beginnerPreferredExerciseNames: [MuscleGroup: [String]] = [
    .chest: ["チェストプレス", "ダンベルベンチプレス", "プッシュアップ", "ベンチプレス"],
    .back: ["ラットプルダウン", "シーテッドロー", "ワンハンドダンベルロー", "TRXロー", "チンニング"],
    .shoulders: ["マシンショルダープレス", "ショルダープレス", "サイドレイズ", "フェイスプル"],
    .arms: ["ダンベルカール", "ケーブルカール", "トライセプスプレスダウン", "ハンマーカール"],
    .quadriceps: ["レッグプレス", "ゴブレットスクワット", "スミスマシンスクワット", "スクワット", "ランジ"],
    .hamstrings: ["レッグカール", "ダンベルルーマニアンデッドリフト", "ルーマニアンデッドリフト"],
    .glutes: ["ヒップスラスト", "グルートブリッジ", "ヒップアブダクション", "ケーブルキックバック"],
    .calves: ["スタンディングカーフレイズ", "シーテッドカーフレイズ"],
    .core: ["プランク", "デッドバグ", "サイドプランク", "クランチ"]
]
