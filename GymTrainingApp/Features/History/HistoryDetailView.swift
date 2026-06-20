import SwiftUI

struct HistoryDetailView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.title2.bold())

                    Text(AppFormatters.shortDateTime.string(from: session.startedAt))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    SummaryMetric(title: "達成率", value: AppFormatters.percent(session.achievementRate))
                    Spacer()
                    SummaryMetric(title: "総ボリューム", value: AppFormatters.volume(session.totalVolume))
                }
                .padding(.vertical, 8)
            }

            ForEach(session.exercises) { exercise in
                Section {
                    if exercise.isSkipped {
                        Label("スキップ", systemImage: "forward.end")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(exercise.sets) { set in
                            HistorySetRow(set: set)
                        }
                    }
                } header: {
                    HStack {
                        Text(exercise.exercise.name)
                        Spacer()
                        Text(exercise.isSkipped ? "スキップ" : AppFormatters.percent(exercise.achievementRate))
                    }
                }
            }
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("履歴を削除")
            }
        }
        .confirmationDialog("この履歴を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                appStore.deleteWorkout(session)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }
}

private struct HistorySetRow: View {
    let set: WorkoutSet

    private var resultText: String {
        if !set.isCompleted {
            return "未完了"
        }

        return set.isAchieved ? "達成" : "未達"
    }

    var body: some View {
        HStack {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(set.isAchieved ? Color.green.opacity(0.18) : Color(.secondarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("実績 \(AppFormatters.weight(set.actualWeight)) × \(set.actualReps)回")
                    .font(.headline)

                Text("目標 \(AppFormatters.weight(set.targetWeight)) × \(set.targetReps)回 / 差分 \(set.repsDelta >= 0 ? "+" : "")\(set.repsDelta)回")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(resultText)
                .font(.subheadline.bold())
                .foregroundStyle(set.isAchieved ? .green : .orange)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            session: WorkoutSession(plan: TrainingPlan(
                name: "胸の日",
                exercises: [
                    PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
                ]
            ))
        )
    }
    .environmentObject(AppStore())
}
