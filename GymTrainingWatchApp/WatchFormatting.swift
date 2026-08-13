import Foundation

func formatWeight(_ value: Double, unit: WatchWeightUnit) -> String {
    switch unit {
    case .kg:
        value.formatted(.number.precision(.fractionLength(0...1))) + " kg"
    case .lb:
        (value * 2.2046226218).formatted(.number.precision(.fractionLength(0...1))) + " lb"
    }
}

func targetSummary(for exercise: WatchPlanExerciseSnapshot, unit: WatchWeightUnit) -> String {
    guard let firstSet = exercise.sets.first else {
        return "セット未設定"
    }

    let hasSameTarget = exercise.sets.allSatisfy {
        $0.targetWeight == firstSet.targetWeight && $0.targetReps == firstSet.targetReps
    }

    if hasSameTarget {
        return "\(formatWeight(firstSet.targetWeight, unit: unit)) × \(firstSet.targetReps)回 × \(exercise.sets.count)セット"
    }

    let totalReps = exercise.sets.reduce(0) { $0 + $1.targetReps }
    return "\(exercise.sets.count)セット・目標 合計\(totalReps)回"
}

func planOverview(_ plan: WatchWorkoutPlanSnapshot) -> String {
    if let exercise = plan.exercises.first, plan.exercises.count == 1 {
        return "\(exercise.name)・\(exercise.sets.count)セット・計\(plan.totalTargetRepCount)回"
    }

    return "\(plan.exercises.count)種目・\(plan.totalSetCount)セット・計\(plan.totalTargetRepCount)回"
}

func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):" + String(format: "%02d", seconds)
}
