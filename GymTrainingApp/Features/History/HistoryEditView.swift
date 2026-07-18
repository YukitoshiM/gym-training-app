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

                                WeightInputControl(
                                    weightInKilograms: $set.actualWeight,
                                    unit: appStore.userProfile.weightUnit,
                                    accessibilityIdentifier: "historyWeightField-\(exercise.sortOrder)-\(set.setOrder)"
                                )

                                RepsInputControl(
                                    reps: $set.actualReps,
                                    accessibilityIdentifier: "historyRepsField-\(exercise.sortOrder)-\(set.setOrder)"
                                )
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
