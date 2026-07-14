import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    var body: some View {
        NavigationStack {
            Group {
                if let plan = workoutStore.plan {
                    WatchPlanDetailView(plan: plan, statusMessage: workoutStore.statusMessage)
                } else {
                    WatchEmptyPlanView(statusMessage: workoutStore.statusMessage)
                }
            }
            .navigationTitle("Gym")
        }
    }
}

private struct WatchEmptyPlanView: View {
    let statusMessage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("計画待ち")
                .font(.headline)

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("iPhoneの記録タブからApple Watchへ送信します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct WatchPlanDetailView: View {
    let plan: WatchWorkoutPlanSnapshot
    let statusMessage: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                    Text("\(plan.exercises.count)種目 / \(plan.totalSetCount)セット")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(plan.exercises) { exercise in
                NavigationLink {
                    WatchExerciseDetailView(exercise: exercise, unit: plan.weightUnit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(exercise.primaryMuscleName)・\(exercise.sets.count)セット・休憩 \(exercise.restSeconds)秒")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct WatchExerciseDetailView: View {
    let exercise: WatchPlanExerciseSnapshot
    let unit: WatchWeightUnit

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                    Text(exercise.primaryMuscleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("休憩 \(exercise.restSeconds)秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("セット") {
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setOrder)")
                            .font(.headline)
                            .frame(width: 26, height: 26)
                            .background(.green.opacity(0.2), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatWeight(set.targetWeight, unit: unit))
                                .font(.headline)
                            Text("\(set.targetReps)回")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }

    private func formatWeight(_ value: Double, unit: WatchWeightUnit) -> String {
        switch unit {
        case .kg:
            value.formatted(.number.precision(.fractionLength(0...1))) + " kg"
        case .lb:
            (value * 2.2046226218).formatted(.number.precision(.fractionLength(0...1))) + " lb"
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchWorkoutStore())
}
