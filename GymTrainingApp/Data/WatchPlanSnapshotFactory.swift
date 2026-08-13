import Foundation

extension WatchWorkoutPlanSnapshot {
    init(
        plan: TrainingPlan,
        weightUnit: WeightUnit,
        previousExercise: (Exercise) -> WorkoutExercise? = { _ in nil }
    ) {
        self.init(
            id: plan.id,
            name: plan.name,
            weightUnit: WatchWeightUnit(weightUnit),
            exercises: plan.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    WatchPlanExerciseSnapshot(
                        planExercise: $0,
                        previousExercise: previousExercise($0.exercise)
                    )
                }
        )
    }
}

extension WatchDailyRecommendationSnapshot {
    init(recommendation: DailyRecommendation) {
        let planID = recommendation.activeActions.compactMap { action -> UUID? in
            if case .workout(let planID) = action.destination { return planID }
            return nil
        }.first
        self.init(
            date: recommendation.date,
            readiness: recommendation.readiness.level.displayName,
            summary: recommendation.summary,
            actions: recommendation.activeActions.map {
                Action(
                    id: $0.id,
                    title: $0.title,
                    systemImage: $0.category.systemImage,
                    isCompleted: $0.status == .completed
                )
            },
            preferredPlanID: planID
        )
    }
}

private extension WatchPlanExerciseSnapshot {
    init(planExercise: PlanExercise, previousExercise: WorkoutExercise?) {
        let previousSets = previousExercise?
            .sets
            .filter(\.isCompleted)
            .sorted { $0.setOrder < $1.setOrder } ?? []
        let restSeconds = (previousExercise?.restSeconds ?? 0) > 0
            ? previousExercise?.restSeconds ?? planExercise.restSeconds
            : planExercise.restSeconds

        self.init(
            id: planExercise.id,
            exerciseID: planExercise.exercise.id,
            name: planExercise.exercise.name,
            primaryMuscleName: planExercise.exercise.primaryMuscle.displayName,
            primaryMuscleRawValue: planExercise.exercise.primaryMuscle.rawValue,
            equipmentRawValue: planExercise.exercise.equipment.rawValue,
            restSeconds: restSeconds,
            sets: planExercise.sets
                .sorted { $0.setOrder < $1.setOrder }
                .map { planSet in
                    let previous = previousSets.first { previousSet in
                        previousSet.setOrder == planSet.setOrder
                    } ?? previousSets.last
                    return WatchPlanSetTargetSnapshot(planSet: planSet, previousSet: previous)
                }
        )
    }
}

private extension WatchPlanSetTargetSnapshot {
    init(planSet: PlanSetTarget, previousSet: WorkoutSet?) {
        self.init(
            id: planSet.id,
            setOrder: planSet.setOrder,
            targetWeight: planSet.targetWeight,
            targetReps: planSet.targetReps,
            plannedConcentricSeconds: planSet.plannedConcentricSeconds,
            plannedEccentricSeconds: planSet.plannedEccentricSeconds,
            plannedTempoBeatSpeed: planSet.plannedTempoBeatSpeed,
            previousActualWeight: previousSet?.actualWeight,
            previousActualReps: previousSet?.actualReps,
            previousRPE: previousSet?.rpe
        )
    }
}

private extension WatchWeightUnit {
    init(_ weightUnit: WeightUnit) {
        switch weightUnit {
        case .kg:
            self = .kg
        case .lb:
            self = .lb
        }
    }
}

extension WorkoutSession {
    init(watchSession: WatchWorkoutSessionSnapshot) {
        self.init(
            id: watchSession.id,
            title: watchSession.title,
            sourcePlanID: watchSession.sourcePlanID,
            startedAt: watchSession.startedAt,
            endedAt: watchSession.endedAt,
            exercises: watchSession.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { WorkoutExercise(watchExercise: $0) },
            sourceDevice: .appleWatch,
            watchSyncState: .received,
            sensorSummary: watchSession.sensorSummary.map(WorkoutSensorSummary.init),
            healthWorkoutSaveState: watchSession.healthKitSaveStatus.map(HealthWorkoutSaveState.init),
            note: watchSession.note
        )
    }
}

private extension WorkoutExercise {
    init(watchExercise: WatchWorkoutExerciseSnapshot) {
        self.init(
            id: watchExercise.id,
            exercise: Exercise(watchExercise: watchExercise),
            sortOrder: watchExercise.sortOrder,
            restSeconds: watchExercise.restSeconds,
            sets: watchExercise.sets
                .sorted { $0.setOrder < $1.setOrder }
                .map { WorkoutSet(watchSet: $0) }
        )
    }
}

private extension WorkoutSet {
    init(watchSet: WatchWorkoutSetSnapshot) {
        self.init(
            id: watchSet.id,
            setOrder: watchSet.setOrder,
            targetWeight: watchSet.targetWeight,
            targetReps: watchSet.targetReps,
            plannedConcentricSeconds: watchSet.plannedConcentricSeconds,
            plannedEccentricSeconds: watchSet.plannedEccentricSeconds,
            plannedTempoBeatSpeed: watchSet.plannedTempoBeatSpeed,
            actualWeight: watchSet.actualWeight,
            actualReps: watchSet.actualReps,
            isCompleted: watchSet.isCompleted,
            rpe: watchSet.rpe,
            startedAt: watchSet.startedAt,
            completedAt: watchSet.completedAt,
            sensorSummary: watchSet.sensorSummary.map(SetSensorSummary.init),
            note: watchSet.note
        )
    }
}

private extension WorkoutSensorSummary {
    init(_ summary: WatchWorkoutSensorSummary) {
        self.init(
            durationSeconds: summary.durationSeconds,
            activeEnergyKilocalories: summary.activeEnergyKilocalories,
            averageHeartRate: summary.averageHeartRate,
            maximumHeartRate: summary.maximumHeartRate,
            heartRateRecovery: summary.heartRateRecovery,
            estimatedReps: summary.estimatedReps,
            motionConfidence: summary.motionConfidence,
            heartRateZoneDurations: summary.heartRateZoneDurations
        )
    }
}

private extension SetSensorSummary {
    init(_ summary: WatchSetSensorSummary) {
        self.init(
            heartRateAtStart: summary.heartRateAtStart,
            heartRateAtEnd: summary.heartRateAtEnd,
            averageHeartRate: summary.averageHeartRate,
            maximumHeartRate: summary.maximumHeartRate,
            heartRateRecovery: summary.heartRateRecovery,
            estimatedReps: summary.estimatedReps,
            averageRepDuration: summary.averageRepDuration,
            movementConsistency: summary.movementConsistency,
            confidence: summary.confidence,
            averageConcentricDuration: summary.averageConcentricDuration,
            averageEccentricDuration: summary.averageEccentricDuration,
            averagePauseDuration: summary.averagePauseDuration,
            relativeRangeOfMotion: summary.relativeRangeOfMotion,
            rangeOfMotionConsistency: summary.rangeOfMotionConsistency,
            velocityLossPercent: summary.velocityLossPercent,
            exerciseCandidateName: summary.exerciseCandidateName,
            exerciseCandidateConfidence: summary.exerciseCandidateConfidence
        )
    }
}

private extension HealthWorkoutSaveState {
    init(_ status: WatchHealthKitSaveStatus) {
        switch status {
        case .unavailable: self = .unavailable
        case .permissionDenied: self = .permissionDenied
        case .collecting: self = .collecting
        case .saved: self = .saved
        case .failed: self = .failed
        }
    }
}

private extension Exercise {
    init(watchExercise: WatchWorkoutExerciseSnapshot) {
        self.init(
            id: watchExercise.exerciseID ?? watchExercise.planExerciseID,
            name: watchExercise.name,
            primaryMuscle: MuscleGroup(rawValue: watchExercise.primaryMuscleRawValue ?? "") ?? .fullBody,
            equipment: Equipment(rawValue: watchExercise.equipmentRawValue ?? "") ?? .other,
            instruction: "Apple Watchから同期した種目です。"
        )
    }
}
