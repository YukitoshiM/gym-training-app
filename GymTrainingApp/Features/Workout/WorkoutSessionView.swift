import SwiftUI

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appStore: AppStore

    @State private var session: WorkoutSession
    @State private var isSelectingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false
    @State private var completedSession: WorkoutSession?
    @State private var isPaused = false
    @State private var restTimerEndAt: Date?
    @State private var restExerciseID: UUID?

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
                if isPaused {
                    Section {
                        Button {
                            isPaused = false
                            appStore.setActiveWorkoutState(.active)
                        } label: {
                            Label(L10n.string("training.resume_workout", fallback: "トレーニングを再開"), systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("resumeActiveWorkoutButton")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        MetricPill(
                            title: L10n.string("training.2f789b4bb6e5", fallback: "全体達成率"),
                            value: AppFormatters.percent(session.achievementRate),
                            systemImage: "target",
                            tint: AppTheme.accent
                        )
                        MetricPill(
                            title: L10n.string("training.a85ababac45e", fallback: "計画セット"),
                            value: "\(session.completedPlannedSetCount)/\(session.plannedSetCount)",
                            systemImage: "checklist",
                            tint: AppTheme.blue
                        )
                        MetricPill(
                            title: L10n.string("training.922870c3ac56", fallback: "総ボリューム"),
                            value: AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit),
                            systemImage: "scalemass",
                            tint: AppTheme.orange
                        )
                        MetricPill(
                            title: L10n.string("training.f85857b6a867", fallback: "目標差"),
                            value: AppFormatters.signedVolume(session.volumeDelta, unit: appStore.userProfile.weightUnit),
                            systemImage: "plusminus",
                            tint: session.volumeDelta >= 0 ? AppTheme.accent : AppTheme.orange
                        )
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach($session.exercises) { $workoutExercise in
                    WorkoutExerciseSection(
                        workoutExercise: $workoutExercise,
                        workoutDate: session.startedAt,
                        sharedRestTimerEndAt: $restTimerEndAt,
                        sharedRestExerciseID: $restExerciseID
                    )
                    .disabled(isPaused)
                }

                Section {
                    Button {
                        isSelectingExercise = true
                    } label: {
                        Label(L10n.string("training.131342b755f7", fallback: "種目を追加"), systemImage: "plus.circle")
                    }
                }
                .disabled(isPaused)
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
                    Button(L10n.string("training.fd89f4db4ef1", fallback: "終了")) {
                        isConfirmingCancel = true
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            isPaused.toggle()
                            appStore.setActiveWorkoutState(isPaused ? .paused : .active)
                        } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        }
                        .accessibilityLabel(isPaused
                            ? L10n.string("training.resume", fallback: "再開")
                            : L10n.string("training.pause", fallback: "一時停止"))
                        .accessibilityIdentifier("toggleWorkoutPauseButton")

                        Button(L10n.string("training.4dce1b477edb", fallback: "完了")) {
                            isConfirmingFinish = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("finishWorkoutButton")
                    }
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
            .confirmationDialog(L10n.string("training.02fd70fbf77e", fallback: "ワークアウトを終了しますか？"), isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                Button(L10n.string("training.pause_and_close", fallback: "中断して閉じる")) {
                    appStore.setActiveWorkoutState(.paused)
                    dismiss()
                }
                Button(L10n.string("training.discard_workout", fallback: "記録を破棄"), role: .destructive) {
                    _ = appStore.discardActiveWorkout()
                    dismiss()
                }
                Button(L10n.string("training.ab9657692a70", fallback: "続ける"), role: .cancel) {}
            } message: {
                Text(L10n.string("training.active_workout_saved", fallback: "中断すると現在のセット内容を保存し、あとで続きから再開できます。"))
            }
            .confirmationDialog(L10n.string("training.f51fc1a0d598", fallback: "ワークアウトを完了しますか？"), isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button(L10n.string("training.b99f564095bb", fallback: "完了して履歴に保存")) {
                    finishWorkout()
                }
                Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル"), role: .cancel) {}
            }
            .onAppear {
                let restored = appStore.beginOrResumeWorkout(session)
                session = restored
                if let active = appStore.activeWorkoutSession, active.id == restored.id {
                    isPaused = active.state != .active
                    restTimerEndAt = active.restTimerEndAt
                    restExerciseID = active.restExerciseID
                }
            }
            .onChange(of: session) { _, value in
                appStore.updateActiveWorkout(
                    value,
                    restTimerEndAt: restTimerEndAt,
                    restExerciseID: restExerciseID
                )
            }
            .onChange(of: restTimerEndAt) { _, _ in persistActiveSession() }
            .onChange(of: restExerciseID) { _, _ in persistActiveSession() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, appStore.activeWorkoutSession?.id == session.id {
                    appStore.setActiveWorkoutState(.interrupted)
                }
            }
        }
    }

    private func persistActiveSession() {
        appStore.updateActiveWorkout(
            session,
            restTimerEndAt: restTimerEndAt,
            restExerciseID: restExerciseID
        )
    }

    private func addExercise(_ exercise: Exercise) {
        session.exercises.append(
            appStore.makeWorkoutExercise(
                for: exercise,
                sortOrder: session.exercises.count
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
    let workoutDate: Date
    @Binding var sharedRestTimerEndAt: Date?
    @Binding var sharedRestExerciseID: UUID?
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

                            Text(L10n.string("training.f6878ce776cf", fallback: "{{value1}}・計画 {{value2}}/{{value3}}セット・達成率 {{value4}}", values: [String(describing: workoutExercise.exercise.primaryMuscle.displayName), String(describing: workoutExercise.completedPlannedSetCount), String(describing: workoutExercise.plannedSetCount), String(describing: AppFormatters.percent(workoutExercise.achievementRate))]))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }

                        Spacer()

                        Toggle(L10n.string("training.17135f0f1ac6", fallback: "スキップ"), isOn: $workoutExercise.isSkipped)
                            .labelsHidden()
                    }

                    if workoutExercise.isSkipped {
                        Label(L10n.string("training.cb7f0433f8fc", fallback: "この種目はスキップされました"), systemImage: "forward.end")
                            .foregroundStyle(AppTheme.mutedInk)
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
                                exercise: workoutExercise.exercise,
                                exerciseSortOrder: workoutExercise.sortOrder,
                                previousSet: previousSet(for: set),
                                bodyWeight: appStore.bodyWeight(on: workoutDate),
                                restSeconds: workoutExercise.restSeconds,
                                onCompleted: startRestTimer
                            ) {
                                removeSet(set)
                            }
                        }

                        Button {
                            addSet()
                        } label: {
                            Label(L10n.string("training.0a9240ad4b7e", fallback: "セットを追加"), systemImage: "plus")
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
                if sharedRestExerciseID == workoutExercise.id {
                    sharedRestTimerEndAt = nil
                    sharedRestExerciseID = nil
                }
            }
        }
        .onAppear {
            guard sharedRestExerciseID == workoutExercise.id,
                  let endAt = sharedRestTimerEndAt else { return }
            restRemaining = max(0, Int(ceil(endAt.timeIntervalSinceNow)))
            isRestTimerRunning = restRemaining > 0
        }
    }

    private func startRestTimer() {
        guard workoutExercise.restSeconds > 0 else {
            return
        }
        restRemaining = workoutExercise.restSeconds
        isRestTimerRunning = true
        sharedRestExerciseID = workoutExercise.id
        sharedRestTimerEndAt = Date().addingTimeInterval(TimeInterval(workoutExercise.restSeconds))
    }

    private func stopRestTimer() {
        isRestTimerRunning = false
        restRemaining = 0
        if sharedRestExerciseID == workoutExercise.id {
            sharedRestTimerEndAt = nil
            sharedRestExerciseID = nil
        }
    }

    private func addSet() {
        let previous = workoutExercise.sets.last
        workoutExercise.sets.append(
            WorkoutSet(
                setOrder: workoutExercise.sets.count + 1,
                targetWeight: previous?.targetWeight ?? 50,
                targetReps: previous?.targetReps ?? 10,
                targetRPE: previous?.targetRPE,
                plannedConcentricSeconds: previous?.plannedConcentricSeconds,
                plannedEccentricSeconds: previous?.plannedEccentricSeconds,
                plannedTempoBeatSpeed: previous?.plannedTempoBeatSpeed,
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
    let exercise: Exercise
    let exerciseSortOrder: Int
    let previousSet: WorkoutSet?
    let bodyWeight: Double?
    let restSeconds: Int
    let onCompleted: () -> Void
    let onDelete: () -> Void

    private var statusText: String {
        if set.isAdded {
            return L10n.string("training.aef5c7b0939e", fallback: "追加")
        }
        if !set.isCompleted {
            return L10n.string("training.9720cc8de334", fallback: "未完了")
        }
        return set.isAchieved ? L10n.string("training.6f68dd807f5f", fallback: "達成") : L10n.string("training.76bbf2a42b69", fallback: "未達")
    }

    private var statusTint: Color {
        if set.isAchieved {
            return AppTheme.positive
        }
        if set.isCompleted {
            return AppTheme.orange
        }
        return AppTheme.mutedInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previousSet {
                HStack {
                    Label(previousText(for: previousSet), systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    Spacer()

                    Button {
                        copyPrevious(previousSet)
                    } label: {
                        Label(L10n.string("training.0c7818c1fc9e", fallback: "コピー"), systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.footnote.bold())
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("copyPreviousSet-\(exerciseSortOrder)-\(set.setOrder)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            }

            HStack {
                Text("\(set.setOrder)")
                    .font(.headline)
                    .frame(width: 30, height: 30)
                    .background(set.isCompleted ? AppTheme.positive.opacity(0.18) : AppTheme.ink.opacity(0.09), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("training.ad1d41e268ba", fallback: "目標 {{value1}} × {{value2}}回", values: [String(describing: AppFormatters.weight(set.targetWeight)), String(describing: set.targetReps)]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    HStack(spacing: 6) {
                        DeltaBadge(
                            title: L10n.string("training.37144dc3ed75", fallback: "重量差"),
                            value: AppFormatters.signedWeight(set.weightDelta, unit: appStore.userProfile.weightUnit),
                            tint: statusTint
                        )
                        DeltaBadge(
                            title: L10n.string("training.8e33a5a0f037", fallback: "回数差"),
                            value: AppFormatters.signedReps(set.repsDelta),
                            tint: statusTint
                        )
                    }
                    .accessibilityIdentifier("workoutSetDelta-\(exerciseSortOrder)-\(set.setOrder)")
                }

                Spacer()

                Text(statusText)
                    .font(.footnote.bold())
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusTint.opacity(0.12), in: Capsule())

                Toggle(L10n.string("training.4dce1b477edb", fallback: "完了"), isOn: $set.isCompleted)
                    .labelsHidden()
                    .accessibilityIdentifier("completeSetToggle-\(exerciseSortOrder)-\(set.setOrder)")
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
                WeightInputControl(
                    weightInKilograms: $set.actualWeight,
                    unit: appStore.userProfile.weightUnit,
                    kilogramRange: exercise.weightInputRange,
                    accessibilityIdentifier: "workoutWeightField-\(exerciseSortOrder)-\(set.setOrder)"
                )

                RepsInputControl(
                    reps: $set.actualReps,
                    accessibilityIdentifier: "workoutRepsField-\(exerciseSortOrder)-\(set.setOrder)"
                )
            }
            .font(.subheadline)

            if exercise.isDipExercise, let bodyWeight {
                Label(
                    AppFormatters.bodyweightLoadSummary(
                        bodyWeight: bodyWeight,
                        addedWeight: set.actualWeight,
                        unit: appStore.userProfile.weightUnit
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .accessibilityIdentifier("dipLoadSummary-\(exerciseSortOrder)-\(set.setOrder)")
            }

            Button {
                copyTarget()
            } label: {
                Label(L10n.string("training.85006d7df5ce", fallback: "目標値をコピー"), systemImage: "target")
            }
            .font(.footnote.bold())
            .buttonStyle(.borderless)
            .accessibilityIdentifier("copyTargetSet-\(exerciseSortOrder)-\(set.setOrder)")
        }
        .padding(10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func previousText(for previousSet: WorkoutSet) -> String {
        L10n.string("training.eef6e758977b", fallback: "前回 {{value1}} × {{value2}}回", values: [String(describing: AppFormatters.weight(previousSet.actualWeight, unit: appStore.userProfile.weightUnit)), String(describing: previousSet.actualReps)])
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
                    title: L10n.string("training.90687409925b", fallback: "達成セット"),
                    value: "\(workoutExercise.achievedPlannedSetCount)/\(workoutExercise.plannedSetCount)",
                    tint: AppTheme.accent
                )
                DeltaBadge(
                    title: L10n.string("training.f85857b6a867", fallback: "目標差"),
                    value: AppFormatters.signedVolume(workoutExercise.volumeDelta, unit: appStore.userProfile.weightUnit),
                    tint: workoutExercise.volumeDelta >= 0 ? AppTheme.accent : AppTheme.orange
                )
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var progressTint: Color {
        workoutExercise.achievementRate >= 1 ? AppTheme.positive : AppTheme.accent
    }
}

private struct DeltaBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            Text(value)
                .font(.footnote.bold())
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
            Label(L10n.string("training.a0b0ff58b87b", fallback: "休憩 {{value1}}", values: [String(describing: format(displayRemaining))]), systemImage: "timer")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                isRunning ? onStop() : onStart()
            } label: {
                Label(isRunning ? L10n.string("training.e2374146acf3", fallback: "停止") : L10n.string("training.92f3acd01a38", fallback: "開始"), systemImage: isRunning ? "stop.fill" : "play.fill")
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
            name: L10n.string("training.d30ca9b91ccb", fallback: "胸の日"),
            exercises: [
                PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
            ]
        ))
    )
    .environmentObject(AppStore())
}
