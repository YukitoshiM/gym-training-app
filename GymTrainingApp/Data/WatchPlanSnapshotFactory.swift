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
            name: planExercise.exercise.name,
            primaryMuscleName: planExercise.exercise.primaryMuscle.displayName,
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
