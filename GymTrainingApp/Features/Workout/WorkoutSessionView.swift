import SwiftUI

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var session: WorkoutSession
    @State private var isSelectingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false
    @State private var completedSession: WorkoutSession?

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(session: WorkoutSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        MetricPill(
                            title: "全体達成率",
                            value: AppFormatters.percent(session.achievementRate),
                            systemImage: "target",
                            tint: AppTheme.accent
                        )
                        MetricPill(
                            title: "計画セット",
                            value: "\(session.completedPlannedSetCount)/\(session.plannedSetCount)",
                            systemImage: "checklist",
                            tint: AppTheme.blue
                        )
                        MetricPill(
                            title: "総ボリューム",
                            value: AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit),
                            systemImage: "scalemass",
                            tint: AppTheme.orange
                        )
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
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
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
                    .accessibilityIdentifier("finishWorkoutButton")
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
    @EnvironmentObject private var appStore: AppStore
    @Binding var workoutExercise: WorkoutExercise
    @State private var restRemaining = 0
    @State private var isRestTimerRunning = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var previousSets: [WorkoutSet] {
        appStore.latestCompletedSets(for: workoutExercise.exercise)
    }

    var body: some View {
        Section {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workoutExercise.exercise.name)
                                .font(.headline)

                            Text("\(workoutExercise.exercise.primaryMuscle.displayName)・計画 \(workoutExercise.completedPlannedSetCount)/\(workoutExercise.plannedSetCount)セット・達成率 \(AppFormatters.percent(workoutExercise.achievementRate))")
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
                        RestTimerControl(
                            restSeconds: workoutExercise.restSeconds,
                            remaining: restRemaining,
                            isRunning: isRestTimerRunning,
                            onStart: startRestTimer,
                            onStop: stopRestTimer
                        )

                        WorkoutPlanProgressStrip(workoutExercise: workoutExercise)

                        ForEach($workoutExercise.sets) { $set in
                            WorkoutSetRow(
                                set: $set,
                                previousSet: previousSet(for: set),
                                restSeconds: workoutExercise.restSeconds,
                                onCompleted: startRestTimer
                            ) {
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
        }
        .onReceive(timer) { _ in
            guard isRestTimerRunning else {
                return
            }

            if restRemaining > 0 {
                restRemaining -= 1
            }

            if restRemaining <= 0 {
                isRestTimerRunning = false
            }
        }
    }

    private func startRestTimer() {
        guard workoutExercise.restSeconds > 0 else {
            return
        }
        restRemaining = workoutExercise.restSeconds
        isRestTimerRunning = true
    }

    private func stopRestTimer() {
        isRestTimerRunning = false
        restRemaining = 0
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

    private func previousSet(for set: WorkoutSet) -> WorkoutSet? {
        previousSets.first { $0.setOrder == set.setOrder }
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
    @EnvironmentObject private var appStore: AppStore
    @Binding var set: WorkoutSet
    let previousSet: WorkoutSet?
    let restSeconds: Int
    let onCompleted: () -> Void
    let onDelete: () -> Void

    private var statusText: String {
        if set.isAdded {
            return "追加"
        }
        if !set.isCompleted {
            return "未完了"
        }
        return set.isAchieved ? "達成" : "未達"
    }

    private var statusTint: Color {
        if set.isAchieved {
            return .green
        }
        if set.isCompleted {
            return AppTheme.orange
        }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previousSet {
                HStack {
                    Label(previousText(for: previousSet), systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copyPrevious(previousSet)
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("copyPreviousSet-\(set.setOrder)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            }

            HStack {
                Text("\(set.setOrder)")
                    .font(.headline)
                    .frame(width: 30, height: 30)
                    .background(set.isCompleted ? Color.green.opacity(0.18) : Color(.secondarySystemFill), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("目標 \(AppFormatters.weight(set.targetWeight)) × \(set.targetReps)回")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        DeltaBadge(
                            title: "重量差",
                            value: AppFormatters.signedWeight(set.weightDelta, unit: appStore.userProfile.weightUnit),
                            tint: statusTint
                        )
                        DeltaBadge(
                            title: "回数差",
                            value: AppFormatters.signedReps(set.repsDelta),
                            tint: statusTint
                        )
                    }
                    .accessibilityIdentifier("workoutSetDelta-\(set.setOrder)")
                }

                Spacer()

                Text(statusText)
                    .font(.caption.bold())
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusTint.opacity(0.12), in: Capsule())

                Toggle("完了", isOn: $set.isCompleted)
                    .labelsHidden()
                    .accessibilityIdentifier("completeSetToggle-\(set.setOrder)")
                    .onChange(of: set.isCompleted) { oldValue, newValue in
                        if !oldValue && newValue {
                            set.completedAt = Date()
                            onCompleted()
                        } else if oldValue && !newValue {
                            set.completedAt = nil
                            set.rpe = nil
                        }
                    }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Stepper(value: $set.actualWeight, in: 0...999, step: 2.5) {
                    Text(AppFormatters.weight(set.actualWeight, unit: appStore.userProfile.weightUnit))
                        .frame(minWidth: 80, alignment: .leading)
                }

                Stepper(value: $set.actualReps, in: 0...999) {
                    Text("\(set.actualReps)回")
                        .frame(minWidth: 52, alignment: .leading)
                }
            }
            .font(.subheadline)

            Button {
                copyTarget()
            } label: {
                Label("目標値をコピー", systemImage: "target")
            }
            .font(.caption.bold())
            .buttonStyle(.borderless)
            .accessibilityIdentifier("copyTargetSet-\(set.setOrder)")
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func previousText(for previousSet: WorkoutSet) -> String {
        "前回 \(AppFormatters.weight(previousSet.actualWeight, unit: appStore.userProfile.weightUnit)) × \(previousSet.actualReps)回"
    }

    private func copyPrevious(_ previousSet: WorkoutSet) {
        set.actualWeight = previousSet.actualWeight
        set.actualReps = previousSet.actualReps
    }

    private func copyTarget() {
        set.actualWeight = set.targetWeight
        set.actualReps = set.targetReps
    }
}

private struct WorkoutPlanProgressStrip: View {
    @EnvironmentObject private var appStore: AppStore
    let workoutExercise: WorkoutExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: workoutExercise.achievementRate)
                .tint(progressTint)

            HStack(spacing: 8) {
                DeltaBadge(
                    title: "達成セット",
                    value: "\(workoutExercise.achievedPlannedSetCount)/\(workoutExercise.plannedSetCount)",
                    tint: AppTheme.accent
                )
                DeltaBadge(
                    title: "目標差",
                    value: AppFormatters.signedVolume(workoutExercise.volumeDelta, unit: appStore.userProfile.weightUnit),
                    tint: workoutExercise.volumeDelta >= 0 ? AppTheme.accent : AppTheme.orange
                )
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var progressTint: Color {
        workoutExercise.achievementRate >= 1 ? .green : AppTheme.accent
    }
}

private struct DeltaBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RestTimerControl: View {
    let restSeconds: Int
    let remaining: Int
    let isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    private var displayRemaining: Int {
        isRunning ? remaining : restSeconds
    }

    var body: some View {
        HStack {
            Label("休憩 \(format(displayRemaining))", systemImage: "timer")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                isRunning ? onStop() : onStart()
            } label: {
                Label(isRunning ? "停止" : "開始", systemImage: isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("restTimerButton")
        }
        .padding(10)
        .background(AppTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
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
