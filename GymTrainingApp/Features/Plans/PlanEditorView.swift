import SwiftUI

struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var draft: TrainingPlan
    @State private var isSelectingExercise = false
    @State private var isShowingValidation = false

    init(plan: TrainingPlan?) {
        _draft = State(
            initialValue: plan ?? TrainingPlan(
                name: "",
                exercises: []
            )
        )
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !draft.exercises.isEmpty
        && draft.exercises.allSatisfy { !$0.sets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("計画名") {
                    TextField("例: 胸の日", text: $draft.name)
                }

                Section {
                    if draft.exercises.isEmpty {
                        ContentUnavailableView {
                            Label("種目がありません", systemImage: "dumbbell")
                        } description: {
                            Text("種目を追加して、セットごとの目標を入力します。")
                        }
                    } else {
                        ForEach($draft.exercises) { $planExercise in
                            PlanExerciseEditorCard(planExercise: $planExercise) {
                                removeExercise(planExercise)
                            }
                        }
                        .onMove(perform: moveExercise)
                    }

                    Button {
                        isSelectingExercise = true
                    } label: {
                        Label("種目を追加", systemImage: "plus.circle")
                    }
                } header: {
                    Text("種目")
                } footer: {
                    Text("セット目標はワークアウト開始時にコピーされ、履歴に残ります。")
                }
            }
            .navigationTitle(draft.name.isEmpty ? "計画作成" : draft.name)
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
                }

                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(draft.exercises.count < 2)
                }
            }
            .sheet(isPresented: $isSelectingExercise) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                    isSelectingExercise = false
                }
            }
            .alert("保存できません", isPresented: $isShowingValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("計画名と1つ以上の種目を入力してください。")
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = draft.exercises.count
        draft.exercises.append(
            PlanExercise(
                exercise: exercise,
                sortOrder: nextOrder
            )
        )
    }

    private func removeExercise(_ planExercise: PlanExercise) {
        draft.exercises.removeAll { $0.id == planExercise.id }
        normalizeSortOrder()
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        draft.exercises.move(fromOffsets: source, toOffset: destination)
        normalizeSortOrder()
    }

    private func normalizeSortOrder() {
        for index in draft.exercises.indices {
            draft.exercises[index].sortOrder = index
        }
    }

    private func save() {
        guard canSave else {
            isShowingValidation = true
            return
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizeSortOrder()
        appStore.savePlan(draft)
        dismiss()
    }
}

private struct PlanExerciseEditorCard: View {
    @Binding var planExercise: PlanExercise
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planExercise.exercise.name)
                        .font(.headline)
                    Text("\(planExercise.exercise.primaryMuscle.displayName)・\(planExercise.exercise.equipment.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Stepper(value: $planExercise.restSeconds, in: 0...600, step: 30) {
                Text("休憩 \(planExercise.restSeconds)秒")
            }

            VStack(spacing: 8) {
                ForEach($planExercise.sets) { $set in
                    PlanSetTargetRow(set: $set) {
                        removeSet(set)
                    }
                }
            }

            Button {
                addSet()
            } label: {
                Label("セットを追加", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private func addSet() {
        let previous = planExercise.sets.last
        planExercise.sets.append(
            PlanSetTarget(
                setOrder: planExercise.sets.count + 1,
                targetWeight: previous?.targetWeight ?? 20,
                targetReps: previous?.targetReps ?? 10
            )
        )
    }

    private func removeSet(_ set: PlanSetTarget) {
        guard planExercise.sets.count > 1 else {
            return
        }

        planExercise.sets.removeAll { $0.id == set.id }
        for index in planExercise.sets.indices {
            planExercise.sets[index].setOrder = index + 1
        }
    }
}

private struct PlanSetTargetRow: View {
    @Binding var set: PlanSetTarget
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: Circle())

            Stepper(value: $set.targetWeight, in: 0...999, step: 2.5) {
                Text(AppFormatters.weight(set.targetWeight))
                    .frame(minWidth: 72, alignment: .leading)
            }

            Stepper(value: $set.targetReps, in: 1...999) {
                Text("\(set.targetReps)回")
                    .frame(minWidth: 48, alignment: .leading)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .font(.subheadline)
    }
}

#Preview {
    PlanEditorView(plan: nil)
        .environmentObject(AppStore())
}

