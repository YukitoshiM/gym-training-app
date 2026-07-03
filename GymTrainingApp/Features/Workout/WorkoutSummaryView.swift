import SwiftUI

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        MetricPill(title: "達成率", value: AppFormatters.percent(session.achievementRate), systemImage: "target", tint: AppTheme.accent)
                        MetricPill(title: "総ボリューム", value: AppFormatters.volume(session.totalVolume), systemImage: "scalemass", tint: AppTheme.orange)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

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
                        .padding(.vertical, 6)
                    }
                }
                .listRowBackground(AppTheme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
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
