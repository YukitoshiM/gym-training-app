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
        return L10n.string("watch_widget.1a782a782a5d", fallback: "セット未設定")
    }

    let hasSameTarget = exercise.sets.allSatisfy {
        $0.targetWeight == firstSet.targetWeight && $0.targetReps == firstSet.targetReps
    }

    if hasSameTarget {
        return L10n.string("watch_widget.c27de027c299", fallback: "{{value1}} × {{value2}}回 × {{value3}}セット", values: [String(describing: formatWeight(firstSet.targetWeight, unit: unit)), String(describing: firstSet.targetReps), String(describing: exercise.sets.count)])
    }

    let totalReps = exercise.sets.reduce(0) { $0 + $1.targetReps }
    return L10n.string("watch_widget.54998c4de19e", fallback: "{{value1}}セット・目標 合計{{value2}}回", values: [String(describing: exercise.sets.count), String(describing: totalReps)])
}

func planOverview(_ plan: WatchWorkoutPlanSnapshot) -> String {
    if let exercise = plan.exercises.first, plan.exercises.count == 1 {
        return L10n.string("watch_widget.b37eb49c5125", fallback: "{{value1}}・{{value2}}セット・計{{value3}}回", values: [String(describing: exercise.name), String(describing: exercise.sets.count), String(describing: plan.totalTargetRepCount)])
    }

    return L10n.string("watch_widget.2411abd90241", fallback: "{{value1}}種目・{{value2}}セット・計{{value3}}回", values: [String(describing: plan.exercises.count), String(describing: plan.totalSetCount), String(describing: plan.totalTargetRepCount)])
}

func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):" + String(format: "%02d", seconds)
}
