import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject private var appStore: AppStore

    let session: WorkoutSession
    let onClose: () -> Void

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        MetricPill(title: "達成率", value: AppFormatters.percent(session.achievementRate), systemImage: "target", tint: AppTheme.accent)
                        MetricPill(title: "計画セット", value: "\(session.completedPlannedSetCount)/\(session.plannedSetCount)", systemImage: "checklist", tint: AppTheme.blue)
                        MetricPill(title: "総ボリューム", value: AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass", tint: AppTheme.orange)
                        MetricPill(
                            title: "目標差",
                            value: AppFormatters.signedVolume(session.volumeDelta, unit: appStore.userProfile.weightUnit),
                            systemImage: "plusminus",
                            tint: session.volumeDelta >= 0 ? AppTheme.accent : AppTheme.orange
                        )
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
                                Text("計画 \(exercise.completedPlannedSetCount)/\(exercise.plannedSetCount)セット完了 / 達成 \(exercise.achievedPlannedSetCount)/\(exercise.plannedSetCount)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedInk)
                                Text("目標差 \(AppFormatters.signedVolume(exercise.volumeDelta, unit: appStore.userProfile.weightUnit))")
                                    .font(.caption.bold())
                                    .foregroundStyle(exercise.volumeDelta >= 0 ? AppTheme.positive : AppTheme.orange)
                            }

                            Spacer()

                            Text(exercise.isSkipped ? "スキップ" : AppFormatters.percent(exercise.achievementRate))
                                .font(.headline)
                                .foregroundStyle(exercise.isSkipped ? AppTheme.mutedInk : AppTheme.ink)
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
                .foregroundStyle(AppTheme.mutedInk)
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
    .environmentObject(AppStore())
}
