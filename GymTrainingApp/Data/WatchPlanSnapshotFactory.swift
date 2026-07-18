import Foundation

extension WatchWorkoutPlanSnapshot {
    init(plan: TrainingPlan, weightUnit: WeightUnit) {
        self.init(
            id: plan.id,
            name: plan.name,
            weightUnit: WatchWeightUnit(weightUnit),
            exercises: plan.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { WatchPlanExerciseSnapshot(planExercise: $0) }
        )
    }
}

private extension WatchPlanExerciseSnapshot {
    init(planExercise: PlanExercise) {
        self.init(
            id: planExercise.id,
            exerciseID: planExercise.exercise.id,
            name: planExercise.exercise.name,
            primaryMuscleName: planExercise.exercise.primaryMuscle.displayName,
            primaryMuscleRawValue: planExercise.exercise.primaryMuscle.rawValue,
            equipmentRawValue: planExercise.exercise.equipment.rawValue,
            restSeconds: planExercise.restSeconds,
            sets: planExercise.sets
                .sorted { $0.setOrder < $1.setOrder }
                .map { WatchPlanSetTargetSnapshot(planSet: $0) }
        )
    }
}

private extension WatchPlanSetTargetSnapshot {
    init(planSet: PlanSetTarget) {
        self.init(
            id: planSet.id,
            setOrder: planSet.setOrder,
            targetWeight: planSet.targetWeight,
            targetReps: planSet.targetReps
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
            watchSyncState: .received
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
            actualWeight: watchSet.actualWeight,
            actualReps: watchSet.actualReps,
            isCompleted: watchSet.isCompleted,
            rpe: watchSet.rpe,
            completedAt: watchSet.completedAt
        )
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
