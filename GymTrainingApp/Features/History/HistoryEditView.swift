import SwiftUI

struct HistoryEditView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WorkoutSession

    init(session: WorkoutSession) {
        _draft = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("タイトル", text: $draft.title)
                        .accessibilityIdentifier("historyTitleField")
                }

                ForEach($draft.exercises) { $exercise in
                    Section(exercise.exercise.name) {
                        Toggle("スキップ", isOn: $exercise.isSkipped)

                        ForEach($exercise.sets) { $set in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("セット\(set.setOrder) 完了", isOn: $set.isCompleted)

                                Stepper(value: $set.actualWeight, in: 0...999, step: 2.5) {
                                    Text("重量 \(AppFormatters.weight(set.actualWeight, unit: appStore.userProfile.weightUnit))")
                                }

                                Stepper(value: $set.actualReps, in: 0...999) {
                                    Text("回数 \(set.actualReps)回")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("履歴編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier("saveHistoryEditButton")
                }
            }
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.title.isEmpty {
            draft.title = "ワークアウト"
        }
        appStore.saveWorkoutHistorySession(draft)
        dismiss()
    }
}

#Preview {
    HistoryEditView(
        session: WorkoutSession(
            plan: TrainingPlan(name: "胸の日", exercises: [PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)])
        )
    )
    .environmentObject(AppStore())
}
