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

    @discardableResult
    func savePlanAsNew(_ plan: TrainingPlan) -> TrainingPlan {
        let now = Date()
        let copiedExercises = plan.exercises.map { exercise in
            PlanExercise(
                exercise: exercise.exercise,
                sortOrder: exercise.sortOrder,
                restSeconds: exercise.restSeconds,
                sets: exercise.sets.map { set in
                    PlanSetTarget(
                        setOrder: set.setOrder,
                        targetWeight: set.targetWeight,
                        targetReps: set.targetReps,
                        targetRPE: set.targetRPE,
                        plannedConcentricSeconds: set.plannedConcentricSeconds,
                        plannedEccentricSeconds: set.plannedEccentricSeconds,
                        plannedTempoBeatSpeed: set.plannedTempoBeatSpeed
                    )
                },
                alternativeExerciseIDs: exercise.alternativeExerciseIDs
            )
        }
        let copy = TrainingPlan(
            name: L10n.string(
                "training.ai_revision_copy_name",
                fallback: "{{value1}} 改訂版",
                values: [plan.name]
            ),
            exercises: copiedExercises,
            createdAt: now,
            updatedAt: now
        )
        savePlan(copy)
        return copy
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
            name: L10n.string("training.5cfd9de649b5", fallback: "初心者 全身スタート"),
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
                    .joined(separator: L10n.string("training.a2333d5b2d78", fallback: "・"))
                let detail = L10n.string("training.41bc72cbabce", fallback: "{{value1}}種目・{{value2}}セット・{{value3}}", values: [String(describing: exercises.count), String(describing: exercises.reduce(0) { $0 + $1.sets.count }), String(describing: equipmentNames)])
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
            let plan = plans.remove(at: offset)
            moveToTrash(title: plan.name, payload: .trainingPlan(plan))
        }
        storage.savePlans(plans)
    }

    @discardableResult
    func beginOrResumeWorkout(_ session: WorkoutSession) -> WorkoutSession {
        if let activeWorkoutSession,
           !activeWorkoutSession.session.isCompleted {
            return activeWorkoutSession.session
        }
        let active = ActiveWorkoutSession(session: session)
        activeWorkoutSession = active
        storage.saveActiveWorkoutSession(active)
        return session
    }

    func updateActiveWorkout(
        _ session: WorkoutSession,
        restTimerEndAt: Date? = nil,
        restExerciseID: UUID? = nil
    ) {
        guard session.endedAt == nil else { return }
        var active = activeWorkoutSession?.id == session.id
            ? activeWorkoutSession!
            : ActiveWorkoutSession(session: session)
        guard active.session != session
                || active.restTimerEndAt != restTimerEndAt
                || active.restExerciseID != restExerciseID else { return }
        active.session = session
        active.revision += 1
        active.updatedAt = Date()
        active.restTimerEndAt = restTimerEndAt
        active.restExerciseID = restExerciseID
        activeWorkoutSession = active
        storage.saveActiveWorkoutSession(active)
    }

    func setActiveWorkoutState(_ state: ActiveWorkoutState) {
        guard var active = activeWorkoutSession else { return }
        active.state = state
        active.revision += 1
        active.updatedAt = Date()
        activeWorkoutSession = active
        storage.saveActiveWorkoutSession(active)
    }

    func discardActiveWorkout() -> WorkoutSession? {
        let active = activeWorkoutSession
        let discarded = active?.session
        activeWorkoutSession = nil
        storage.saveActiveWorkoutSession(nil)
        if let active {
            moveToTrash(title: active.session.title, payload: .activeWorkout(active))
        }
        return discarded
    }

    func finishWorkout(_ session: WorkoutSession) {
        let isFirstCompletedWorkout = workoutHistory.isEmpty
        var completedSession = session
        completedSession.endedAt = Date()

        if let index = workoutHistory.firstIndex(where: { $0.id == completedSession.id }) {
            workoutHistory[index] = completedSession
        } else {
            workoutHistory.insert(completedSession, at: 0)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        storage.saveWorkoutHistory(workoutHistory)
        if activeWorkoutSession?.id == completedSession.id {
            activeWorkoutSession = nil
            storage.saveActiveWorkoutSession(nil)
        }
        UsageAnalytics.shared.record(.workoutCompleted)
        if isFirstCompletedWorkout {
            UsageAnalytics.shared.record(.firstWorkoutCompleted)
        }
        processPlanRevisionAfterWorkout(completedSession)
    }

    func deleteWorkoutHistory(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            let session = workoutHistory.remove(at: offset)
            moveToTrash(title: session.title, payload: .workout(session))
        }
        storage.saveWorkoutHistory(workoutHistory)
    }

    func deleteWorkout(_ session: WorkoutSession) {
        guard let index = workoutHistory.firstIndex(where: { $0.id == session.id }) else { return }
        let removed = workoutHistory.remove(at: index)
        storage.saveWorkoutHistory(workoutHistory)
        moveToTrash(title: removed.title, payload: .workout(removed))
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
        if session.isCompleted, activeWorkoutSession?.id == session.id {
            activeWorkoutSession = nil
            storage.saveActiveWorkoutSession(nil)
        }
        if session.isCompleted {
            processPlanRevisionAfterWorkout(session)
        }
    }

    func pendingPlanRevision(for sessionID: UUID) -> PlanRevisionProposal? {
        planRevisionProposals.first {
            $0.triggerSessionID == sessionID && $0.decision == .pending
        }
    }

    @discardableResult
    func acceptPlanRevision(
        triggerSession: WorkoutSession,
        originalPlan: TrainingPlan,
        revisedPlan: TrainingPlan,
        asNew: Bool,
        summary: String,
        evidence: [CoachEvidenceCitation] = [],
        evidenceStatus: CoachEvidenceStatus? = nil
    ) -> PlanRevisionProposal {
        var record = pendingPlanRevision(for: triggerSession.id) ?? PlanRevisionProposal(
            triggerSessionID: triggerSession.id,
            originalPlan: originalPlan,
            summary: summary,
            baselineAchievementRate: triggerSession.achievementRate
        )
        let appliedPlan: TrainingPlan
        if asNew {
            appliedPlan = savePlanAsNew(revisedPlan)
            record.decision = .acceptedAsNew
        } else {
            appliedPlan = revisedPlan
            savePlan(appliedPlan)
            record.decision = .acceptedAsUpdate
        }
        record.revisedPlan = appliedPlan
        record.summary = summary
        record.decidedAt = Date()
        record.appliedPlanID = appliedPlan.id
        record.evidence = evidence
        record.evidenceStatus = evidenceStatus
        upsertPlanRevision(record)
        return record
    }

    func rejectPlanRevision(triggerSession: WorkoutSession, originalPlan: TrainingPlan) {
        var record = pendingPlanRevision(for: triggerSession.id) ?? PlanRevisionProposal(
            triggerSessionID: triggerSession.id,
            originalPlan: originalPlan,
            summary: L10n.string("training.plan_revision_declined", fallback: "今回は現在の計画を続けます。"),
            baselineAchievementRate: triggerSession.achievementRate
        )
        record.decision = .rejected
        record.decidedAt = Date()
        upsertPlanRevision(record)
    }

    func revertPlanRevision(_ id: UUID) {
        guard let index = planRevisionProposals.firstIndex(where: { $0.id == id }) else { return }
        var record = planRevisionProposals[index]
        switch record.decision {
        case .acceptedAsUpdate:
            savePlan(record.originalPlan)
        case .acceptedAsNew:
            if let appliedPlanID = record.appliedPlanID {
                plans.removeAll { $0.id == appliedPlanID }
                storage.savePlans(plans)
                if dailyWorkoutSelection?.planID == appliedPlanID {
                    dailyWorkoutSelection = nil
                    storage.saveDailyWorkoutSelection(nil)
                }
            }
        default:
            return
        }
        record.decision = .reverted
        record.decidedAt = Date()
        upsertPlanRevision(record)
    }

    private func processPlanRevisionAfterWorkout(_ session: WorkoutSession) {
        evaluateAppliedPlanRevisions(with: session)
        guard pendingPlanRevision(for: session.id) == nil,
              let planID = session.sourcePlanID,
              let plan = plans.first(where: { $0.id == planID }),
              shouldSuggestPlanRevision(after: session, planID: planID) else { return }

        let record = PlanRevisionProposal(
            triggerSessionID: session.id,
            originalPlan: plan,
            summary: planRevisionTriggerSummary(for: session),
            baselineAchievementRate: session.achievementRate
        )
        planRevisionProposals.insert(record, at: 0)
        trimAndSavePlanRevisions()
    }

    private func shouldSuggestPlanRevision(after session: WorkoutSession, planID: UUID) -> Bool {
        let completedForPlan = workoutHistory.filter {
            $0.sourcePlanID == planID && $0.isCompleted
        }
        let completedRPEs = session.exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .compactMap(\.rpe)
        let averageRPE = completedRPEs.isEmpty
            ? nil
            : completedRPEs.reduce(0, +) / Double(completedRPEs.count)
        return completedForPlan.count >= 2
            || session.achievementRate >= 0.95
            || session.achievementRate < 0.7
            || (averageRPE ?? 0) >= 9
    }

    private func planRevisionTriggerSummary(for session: WorkoutSession) -> String {
        if session.achievementRate >= 0.95 {
            return L10n.string("training.plan_revision_progress", fallback: "目標を達成できたので、次回の負荷を確認できます。")
        }
        if session.achievementRate < 0.7 {
            return L10n.string("training.plan_revision_adjust", fallback: "未達が続かないよう、次回の負荷を調整できます。")
        }
        return L10n.string("training.plan_revision_review", fallback: "実績が揃ったので、次回計画を見直せます。")
    }

    private func evaluateAppliedPlanRevisions(with session: WorkoutSession) {
        guard let planID = session.sourcePlanID else { return }
        var changed = false
        for index in planRevisionProposals.indices {
            let record = planRevisionProposals[index]
            guard record.appliedPlanID == planID,
                  record.effectiveness == .unknown,
                  record.evaluatedSessionID == nil,
                  record.triggerSessionID != session.id,
                  let decidedAt = record.decidedAt,
                  session.startedAt >= decidedAt else { continue }
            let delta = session.achievementRate - record.baselineAchievementRate
            planRevisionProposals[index].effectiveness = if delta >= 0.05 {
                .improved
            } else if delta <= -0.05 {
                .worsened
            } else {
                .unchanged
            }
            planRevisionProposals[index].evaluatedSessionID = session.id
            changed = true
        }
        if changed { trimAndSavePlanRevisions() }
    }

    private func upsertPlanRevision(_ proposal: PlanRevisionProposal) {
        if let index = planRevisionProposals.firstIndex(where: { $0.id == proposal.id }) {
            planRevisionProposals[index] = proposal
        } else {
            planRevisionProposals.insert(proposal, at: 0)
        }
        trimAndSavePlanRevisions()
    }

    private func trimAndSavePlanRevisions() {
        planRevisionProposals.sort { $0.createdAt > $1.createdAt }
        planRevisionProposals = Array(planRevisionProposals.prefix(100))
        storage.savePlanRevisionProposals(planRevisionProposals)
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
            let exercise = customExercises.remove(at: offset)
            moveToTrash(title: exercise.name, payload: .customExercise(exercise))
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

    func makeWorkoutSession(
        from plan: TrainingPlan,
        linksToSavedPlan: Bool = true
    ) -> WorkoutSession {
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
            sourcePlanID: linksToSavedPlan ? plan.id : nil,
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
                targetRPE: target.targetRPE,
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
                BeginnerProgramTemplate(title: L10n.string("training.522aa99f1470", fallback: "上半身"), muscleGroups: [.chest, .back, .shoulders, .arms]),
                BeginnerProgramTemplate(title: L10n.string("training.2611654f84a2", fallback: "下半身"), muscleGroups: [.quadriceps, .hamstrings, .glutes, .calves]),
                BeginnerProgramTemplate(title: L10n.string("training.53aa1d520961", fallback: "全身"), muscleGroups: [.quadriceps, .chest, .back, .core])
            ]
        case .performance:
            [
                BeginnerProgramTemplate(title: L10n.string("training.018e4148e6e6", fallback: "筋力A"), muscleGroups: [.quadriceps, .chest, .back, .core]),
                BeginnerProgramTemplate(title: L10n.string("training.840f119546c3", fallback: "筋力B"), muscleGroups: [.hamstrings, .shoulders, .back, .glutes]),
                BeginnerProgramTemplate(title: L10n.string("training.53aa1d520961", fallback: "全身"), muscleGroups: [.quadriceps, .chest, .back, .core])
            ]
        case .diet, .health:
            [
                BeginnerProgramTemplate(title: L10n.string("training.0b609d7ebdd0", fallback: "全身A"), muscleGroups: [.quadriceps, .chest, .back, .core]),
                BeginnerProgramTemplate(title: L10n.string("training.23ab9984271c", fallback: "全身B"), muscleGroups: [.glutes, .shoulders, .back, .core]),
                BeginnerProgramTemplate(title: L10n.string("training.f74271660465", fallback: "全身C"), muscleGroups: [.hamstrings, .chest, .back, .calves])
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
    .chest: [L10n.string("training.01aca7cb57f6", fallback: "チェストプレス"), L10n.string("training.968fc7f1220b", fallback: "ダンベルベンチプレス"), L10n.string("training.2ef07d4e1418", fallback: "プッシュアップ"), L10n.string("training.e2b5cf1b1f39", fallback: "ベンチプレス")],
    .back: [L10n.string("training.350f04ad1646", fallback: "ラットプルダウン"), L10n.string("training.861902f328fe", fallback: "シーテッドロー"), L10n.string("training.37679aa5c82b", fallback: "ワンハンドダンベルロー"), L10n.string("training.21b3c423a0af", fallback: "TRXロー"), L10n.string("training.ffb65eb71783", fallback: "チンニング")],
    .shoulders: [L10n.string("training.5920e2c80803", fallback: "マシンショルダープレス"), L10n.string("training.7a44ac818519", fallback: "ショルダープレス"), L10n.string("training.8eac181b85a5", fallback: "サイドレイズ"), L10n.string("training.555c9f45a820", fallback: "フェイスプル")],
    .arms: [L10n.string("training.c878919a9bf6", fallback: "ダンベルカール"), L10n.string("training.1792e5824127", fallback: "ケーブルカール"), L10n.string("training.2f0138ac5e92", fallback: "トライセプスプレスダウン"), L10n.string("training.5dc1d6f9b7f5", fallback: "ハンマーカール")],
    .quadriceps: [L10n.string("training.f0fcaf87273a", fallback: "レッグプレス"), L10n.string("training.dc48071f113b", fallback: "ゴブレットスクワット"), L10n.string("training.264702fd4fe2", fallback: "スミスマシンスクワット"), L10n.string("training.ce9fc6f5909f", fallback: "スクワット"), L10n.string("training.564c4b7935f7", fallback: "ランジ")],
    .hamstrings: [L10n.string("training.c47e9693a5f3", fallback: "レッグカール"), L10n.string("training.0d799718504b", fallback: "ダンベルルーマニアンデッドリフト"), L10n.string("training.dfd6b19dd66a", fallback: "ルーマニアンデッドリフト")],
    .glutes: [L10n.string("training.bc25e5938e41", fallback: "ヒップスラスト"), L10n.string("training.7d35335dea62", fallback: "グルートブリッジ"), L10n.string("training.da70de7280dc", fallback: "ヒップアブダクション"), L10n.string("training.2a31f578437f", fallback: "ケーブルキックバック")],
    .calves: [L10n.string("training.d92fd6ec348c", fallback: "スタンディングカーフレイズ"), L10n.string("training.7ebc8b96d7ed", fallback: "シーテッドカーフレイズ")],
    .core: [L10n.string("training.d59e261b21df", fallback: "プランク"), L10n.string("training.0468fd02f0c1", fallback: "デッドバグ"), L10n.string("training.4b7886d221dd", fallback: "サイドプランク"), L10n.string("training.aa13a7c82f0f", fallback: "クランチ")]
]
