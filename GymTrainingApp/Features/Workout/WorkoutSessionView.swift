import SwiftUI

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var session: WorkoutSession
    @State private var isSelectingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false
    @State private var completedSession: WorkoutSession?

    init(session: WorkoutSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("全体達成率")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(AppFormatters.percent(session.achievementRate))
                                .font(.title2.bold())
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("総ボリューム")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(AppFormatters.volume(session.totalVolume))
                                .font(.title2.bold())
                        }
                    }
                    .padding(.vertical, 6)
                }

                ForEach($session.exercises) { $workoutExercise in
                    WorkoutExerciseSection(workoutExercise: $workoutExercise)
                }

                Section {
                    Button {
                        isSelectingExercise = true
                    } label: {
                        Label("種目を追加", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("終了") {
                        isConfirmingCancel = true
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("完了") {
                        isConfirmingFinish = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $isSelectingExercise) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                    isSelectingExercise = false
                }
            }
            .sheet(item: $completedSession) { completed in
                WorkoutSummaryView(session: completed) {
                    dismiss()
                }
            }
            .confirmationDialog("ワークアウトを終了しますか？", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                Button("記録せず閉じる", role: .destructive) {
                    dismiss()
                }
                Button("続ける", role: .cancel) {}
            } message: {
                Text("完了していない記録は保存されません。")
            }
            .confirmationDialog("ワークアウトを完了しますか？", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button("完了して履歴に保存") {
                    finishWorkout()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = session.exercises.count
        let sets = PlanSetTarget.defaultSets().map {
            WorkoutSet(
                setOrder: $0.setOrder,
                targetWeight: $0.targetWeight,
                targetReps: $0.targetReps
            )
        }

        session.exercises.append(
            WorkoutExercise(
                exercise: exercise,
                sortOrder: nextOrder,
                restSeconds: 90,
                sets: sets
            )
        )
    }

    private func finishWorkout() {
        var completed = session
        completed.endedAt = Date()
        appStore.finishWorkout(completed)
        completedSession = completed
    }
}

private struct WorkoutExerciseSection: View {
    @Binding var workoutExercise: WorkoutExercise

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workoutExercise.exercise.name)
                        .font(.headline)

                    Text("\(workoutExercise.exercise.primaryMuscle.displayName)・達成率 \(AppFormatters.percent(workoutExercise.achievementRate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("スキップ", isOn: $workoutExercise.isSkipped)
                    .labelsHidden()
            }

            if workoutExercise.isSkipped {
                Label("この種目はスキップされました", systemImage: "forward.end")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($workoutExercise.sets) { $set in
                    WorkoutSetRow(set: $set) {
                        removeSet(set)
                    }
                }

                Button {
                    addSet()
                } label: {
                    Label("セットを追加", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addSet() {
        let previous = workoutExercise.sets.last
        workoutExercise.sets.append(
            WorkoutSet(
                setOrder: workoutExercise.sets.count + 1,
                targetWeight: previous?.targetWeight ?? 20,
                targetReps: previous?.targetReps ?? 10,
                actualWeight: previous?.actualWeight,
                actualReps: previous?.actualReps,
                isAdded: true
            )
        )
    }

    private func removeSet(_ set: WorkoutSet) {
        guard workoutExercise.sets.count > 1 else {
            return
        }

        workoutExercise.sets.removeAll { $0.id == set.id }
        for index in workoutExercise.sets.indices {
            workoutExercise.sets[index].setOrder = index + 1
        }
    }
}

private struct WorkoutSetRow: View {
    @Binding var set: WorkoutSet
    let onDelete: () -> Void

    private var deltaText: String {
        if set.repsDelta == 0 {
            return "目標通り"
        }

        return set.repsDelta > 0 ? "+\(set.repsDelta)回" : "\(set.repsDelta)回"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(set.setOrder)")
                    .font(.headline)
                    .frame(width: 30, height: 30)
                    .background(set.isCompleted ? .green.opacity(0.18) : .thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("目標 \(AppFormatters.weight(set.targetWeight)) × \(set.targetReps)回")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(deltaText)
                        .font(.caption.bold())
                        .foregroundStyle(set.isAchieved ? .green : .orange)
                }

                Spacer()

                Toggle("完了", isOn: $set.isCompleted)
                    .labelsHidden()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Stepper(value: $set.actualWeight, in: 0...999, step: 2.5) {
                    Text(AppFormatters.weight(set.actualWeight))
                        .frame(minWidth: 80, alignment: .leading)
                }

                Stepper(value: $set.actualReps, in: 0...999) {
                    Text("\(set.actualReps)回")
                        .frame(minWidth: 52, alignment: .leading)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WorkoutSessionView(
        session: WorkoutSession(plan: TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
            ]
        ))
    )
    .environmentObject(AppStore())
}

