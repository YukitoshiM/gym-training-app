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
                Section(L10n.string("training.ac1592e85d63", fallback: "基本")) {
                    TextField(L10n.string("training.c1fe760f7267", fallback: "タイトル"), text: $draft.title)
                        .accessibilityIdentifier("historyTitleField")
                    DatePicker(
                        L10n.string("health_meals_body_ai.c5deaf60f00d", fallback: "記録日"),
                        selection: workoutDate,
                        in: RecordDatePolicy.allowedRange(),
                        displayedComponents: .date
                    )
                }

                ForEach($draft.exercises) { $exercise in
                    Section(exercise.exercise.name) {
                        Toggle(L10n.string("training.17135f0f1ac6", fallback: "スキップ"), isOn: $exercise.isSkipped)

                        ForEach($exercise.sets) { $set in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(L10n.string("training.9f638e07adf6", fallback: "セット{{value1}} 完了", values: [String(describing: set.setOrder)]), isOn: $set.isCompleted)

                                WeightInputControl(
                                    weightInKilograms: $set.actualWeight,
                                    unit: appStore.userProfile.weightUnit,
                                    kilogramRange: exercise.exercise.weightInputRange,
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
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("training.818fc41a9095", fallback: "履歴編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("training.0fcb170ec7cf", fallback: "保存")) {
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
            draft.title = L10n.string("training.3a175af6d72d", fallback: "ワークアウト")
        }
        appStore.saveWorkoutHistorySession(draft)
        dismiss()
    }

    private var workoutDate: Binding<Date> {
        Binding(
            get: { RecordDatePolicy.normalizedDay(draft.startedAt) },
            set: { newDate in
                draft = RecordDatePolicy.shifting(draft, to: RecordDatePolicy.normalizedDay(newDate))
            }
        )
    }
}

#Preview {
    HistoryEditView(
        session: WorkoutSession(
            plan: TrainingPlan(name: L10n.string("training.d30ca9b91ccb", fallback: "胸の日"), exercises: [PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)])
        )
    )
    .environmentObject(AppStore())
}
