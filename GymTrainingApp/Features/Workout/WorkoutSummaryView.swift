import SwiftUI

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        SummaryMetric(title: "達成率", value: AppFormatters.percent(session.achievementRate))
                        Spacer()
                        SummaryMetric(title: "総ボリューム", value: AppFormatters.volume(session.totalVolume))
                    }
                    .padding(.vertical, 8)
                }

                Section("種目別") {
                    ForEach(session.exercises) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.exercise.name)
                                    .font(.headline)
                                Text("\(exercise.sets.filter(\.isCompleted).count)/\(exercise.sets.count)セット完了")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(exercise.isSkipped ? "スキップ" : AppFormatters.percent(exercise.achievementRate))
                                .font(.headline)
                                .foregroundStyle(exercise.isSkipped ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle("完了")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("閉じる", action: onClose)
                }
            }
        }
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
    }
}

#Preview {
    WorkoutSummaryView(
        session: WorkoutSession(plan: TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
            ]
        )),
        onClose: {}
    )
}

