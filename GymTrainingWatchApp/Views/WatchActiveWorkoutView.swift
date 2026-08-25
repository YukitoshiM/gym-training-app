import SwiftUI

struct WatchActiveWorkoutView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false
    @State private var isEditingRestTimer = false
    @State private var isEditingWorkoutNote = false
    @State private var selectedExerciseID: UUID?
    @State private var activeWeightEditor: WatchActiveWeightEditor?
    @State private var activeRepsEditor: WatchActiveRepsEditor?
    @State private var activeRPEEditor: WatchActiveRPEEditor?
    @State private var activeTempoEditor: WatchActiveTempoEditor?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @ViewBuilder
    var body: some View {
        if let session = workoutStore.activeSession {
            if session.isOutdoorCardio {
                WatchOutdoorActiveView(session: session)
            } else {
                activeWorkoutContent(session: session)
            }
        } else {
            Text(L10n.string("watch_widget.e7c120e0433a", fallback: "記録中のワークアウトがありません"))
                .padding()
        }
    }

    private func activeWorkoutContent(session: WatchWorkoutSessionSnapshot) -> some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.title)
                            .font(.headline)
                        Text(L10n.string("watch_widget.fcce7b71cb97", fallback: "{{value1}}/{{value2}}セット・{{value3}}回記録", values: [String(describing: session.completedSetCount), String(describing: session.totalSetCount), String(describing: session.completedRepCount)]))
                            .font(.caption)
                            .foregroundStyle(WatchAppTheme.mutedInk)
                            .accessibilityIdentifier("watchWorkoutProgress")

                        if let activeSet {
                            Text(L10n.string("watch_widget.bbe1d3c236c4", fallback: "{{value1}}・セット{{value2}}", values: [String(describing: activeSet.exercise.name), String(describing: activeSet.set.setOrder)]))
                                .font(.caption.bold())
                                .foregroundStyle(WatchAppTheme.positive)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.string("watch_widget.3e06adb84ec0", fallback: "実績 {{value1}} × {{value2}}回", values: [String(describing: formatWeight(activeSet.set.actualWeight, unit: session.weightUnit)), String(describing: activeSet.set.actualReps)]))
                                    .font(.caption)
                                    .accessibilityIdentifier("watchActiveSetActual")

                                HStack(spacing: 6) {
                                    Button {
                                        activeWeightEditor = WatchActiveWeightEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set,
                                            unit: session.weightUnit
                                        )
                                    } label: {
                                        Label(L10n.string("watch_widget.74211dc96bd5", fallback: "重量"), systemImage: "dial.medium")
                                    }
                                    .accessibilityLabel(L10n.string("watch_widget.27c9510ceaed", fallback: "実行中セットの重量を変更"))
                                    .accessibilityIdentifier("watchActiveWeightEntry")

                                    Button {
                                        activeRepsEditor = WatchActiveRepsEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Label(L10n.string("watch_widget.83fdf5d78dd0", fallback: "回数"), systemImage: "number")
                                    }
                                    .accessibilityLabel(L10n.string("watch_widget.55fbfa481026", fallback: "実行中セットの回数を変更"))
                                    .accessibilityIdentifier("watchActiveRepsEntry")

                                    Button {
                                        activeTempoEditor = WatchActiveTempoEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Label(L10n.string("watch_widget.d7e6f512c71c", fallback: "テンポ"), systemImage: "metronome")
                                    }
                                    .accessibilityLabel(L10n.string("watch_widget.d782504f8bde", fallback: "実行中セットのテンポを変更"))
                                    .accessibilityIdentifier("watchActiveTempoEntry")

                                    Button {
                                        activeRPEEditor = WatchActiveRPEEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Text("RPE")
                                    }
                                    .accessibilityLabel(L10n.string("watch_widget.ec4ab4872cdb", fallback: "実行中セットのRPEを変更"))
                                    .accessibilityIdentifier("watchActiveRPEEntry")
                                }
                                .buttonStyle(.bordered)
                                .font(.caption2)

                                HStack {
                                    Button {
                                        workoutStore.cancelSet(
                                            exerciseID: activeSet.exercise.id,
                                            setID: activeSet.set.id
                                        )
                                    } label: {
                                        Label(L10n.string("watch_widget.e04ccdac55cd", fallback: "取消"), systemImage: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel(L10n.string("watch_widget.f6a396814054", fallback: "セット開始を取り消す"))
                                    .accessibilityIdentifier("watchCancelActiveSetButton")

                                    Button {
                                        workoutStore.setCompletion(
                                            exerciseID: activeSet.exercise.id,
                                            setID: activeSet.set.id,
                                            isCompleted: true
                                        )
                                    } label: {
                                        Label(L10n.string("watch_widget.01657c68d2fc", fallback: "完了"), systemImage: "checkmark")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(WatchAppTheme.positive)
                                    .accessibilityLabel(L10n.string("watch_widget.8223803cd257", fallback: "セットを完了"))
                                    .accessibilityIdentifier("watchCompleteActiveSetButton")
                                }
                                .font(.caption)

                                if let target = WatchTempoTarget(
                                    concentricSeconds: activeSet.set.plannedConcentricSeconds,
                                    eccentricSeconds: activeSet.set.plannedEccentricSeconds,
                                    repetitions: activeSet.set.targetReps,
                                    beatSpeed: activeSet.set.resolvedTempoBeatSpeed
                                ) {
                                    WatchTempoGuideView(target: target)
                                }
                            }

                        }

                        if !pendingExercises.isEmpty {
                            Picker(L10n.string("watch_widget.218a9aa6d716", fallback: "次の種目"), selection: $selectedExerciseID) {
                                ForEach(pendingExercises) { exercise in
                                    Text(exercise.name)
                                        .tag(Optional(exercise.id))
                                }
                            }
                            .accessibilityIdentifier("watchNextExerciseMenu")

                            if activeSet == nil, let selectedPendingSet {
                                Button {
                                    activeTempoEditor = WatchActiveTempoEditor(
                                        exercise: selectedPendingSet.exercise,
                                        set: selectedPendingSet.set
                                    )
                                } label: {
                                    Label(
                                        tempoSummary(for: selectedPendingSet.set),
                                        systemImage: "metronome"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .font(.caption2)
                                .accessibilityLabel(L10n.string("watch_widget.2f3d8874afc6", fallback: "開始前にテンポを設定"))
                                .accessibilityValue(tempoSummary(for: selectedPendingSet.set))
                                .accessibilityIdentifier(
                                    "watchSelectedTempoEntry-\(selectedPendingSet.exercise.sortOrder)-\(selectedPendingSet.set.setOrder)"
                                )
                            }

                            Button {
                                guard let selectedNextSet else { return }
                                workoutStore.startSet(
                                    exerciseID: selectedNextSet.exerciseID,
                                    setID: selectedNextSet.setID
                                )
                            } label: {
                                Label(
                                    activeSet == nil ? L10n.string("watch_widget.864ffb74d301", fallback: "セットを開始") : L10n.string("watch_widget.b5ad6016c9a4", fallback: "選択セットへ切替"),
                                    systemImage: activeSet == nil ? "play.fill" : "arrow.left.arrow.right"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WatchAppTheme.positive)
                            .accessibilityIdentifier(
                                activeSet == nil
                                    ? "watchStartNextSetButton"
                                    : "watchSwitchSetButton"
                            )
                            .id("watch-set-switch-control")
                        }

                        ProgressView(
                            value: Double(session.completedSetCount),
                            total: Double(max(session.totalSetCount, 1))
                        )
                        .tint(WatchAppTheme.positive)

                        WatchLiveMetricsView(
                            metrics: workoutStore.liveMetrics,
                            statusMessage: workoutStore.healthStatusMessage,
                            powerModeMessage: workoutStore.sensorPowerModeMessage
                        )

                        if session.completedSetCount > 0 {
                            NavigationLink {
                                WatchCompletedSetsArchiveView(session: session)
                            } label: {
                                Label(
                                    L10n.string("watch_widget.f7114d6c4059", fallback: "完了セット {{value1}}件", values: [String(describing: session.completedSetCount)]),
                                    systemImage: "archivebox.fill"
                                )
                            }
                            .accessibilityIdentifier("watchCompletedSetsArchiveLink")
                        }

                        if let suggestion = workoutStore.setStartSuggestion {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(L10n.string("watch_widget.39817f548ab9", fallback: "動作候補: {{value1}}", values: [String(describing: suggestion.exerciseName)]), systemImage: "sensor.tag.radiowaves.forward")
                                    .font(.caption.bold())
                                Text(L10n.string("watch_widget.65047314093f", fallback: "信頼度 {{value1}}%・{{value2}}", values: [String(describing: Int(suggestion.confidence * 100)), String(describing: suggestion.reason)]))
                                    .font(.caption2)
                                    .foregroundStyle(WatchAppTheme.mutedInk)
                                HStack {
                                    Button(L10n.string("watch_widget.73efe52b65c2", fallback: "開始")) {
                                        workoutStore.acceptSetStartSuggestion()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(WatchAppTheme.positive)
                                    .accessibilityIdentifier("watchAcceptSetStartSuggestion")

                                    Button(L10n.string("watch_widget.2db35aa51fee", fallback: "違う")) {
                                        workoutStore.dismissSetStartSuggestion()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .accessibilityIdentifier("watchSetStartSuggestion")
                        }
                    }
                }

                ForEach(visibleExercises) { exercise in
                    Section(exercise.name) {
                        ForEach(exercise.sets.filter { !$0.isCompleted }) { set in
                            WatchSetControlRow(exerciseID: exercise.id, setID: set.id, unit: session.weightUnit)
                        }

                        if workoutStore.isRestTimerRunning,
                           workoutStore.restExerciseID == exercise.id {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(L10n.string("watch_widget.bc91575d959a", fallback: "休憩 {{value1}}", values: [String(describing: formatDuration(workoutStore.restRemaining))]), systemImage: "timer")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(WatchAppTheme.positive)
                                        .accessibilityIdentifier("watchRestTimer")

                                    Spacer()

                                    Button {
                                        workoutStore.stopRestTimer()
                                    } label: {
                                        Image(systemName: "forward.end.fill")
                                    }
                                    .accessibilityLabel(L10n.string("watch_widget.9101acbdbd05", fallback: "休憩をスキップ"))
                                }

                                Button {
                                    isEditingRestTimer = true
                                } label: {
                                    Label(L10n.string("watch_widget.7b9526eff5f9", fallback: "時間を変更"), systemImage: "dial.medium")
                                }
                                .buttonStyle(.bordered)
                                .font(.caption2)
                                .accessibilityIdentifier("watchRestTimerEntry")

                                if let restReadinessMessage = workoutStore.restReadinessMessage {
                                    Text(restReadinessMessage)
                                        .font(.caption2)
                                        .foregroundStyle(WatchAppTheme.mutedInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let suggestion = workoutStore.nextSetLoadSuggestion {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(
                                            L10n.string("watch_widget.ac9b2200eb4a", fallback: "次: {{value1}} {{value2}} × {{value3}}回", values: [String(describing: suggestion.exerciseName), String(describing: formatWeight(suggestion.suggestedWeight, unit: session.weightUnit)), String(describing: suggestion.suggestedReps)])
                                        )
                                            .font(.caption.bold())
                                        Text(suggestion.reason)
                                            .font(.caption2)
                                            .foregroundStyle(WatchAppTheme.mutedInk)
                                        Button(L10n.string("watch_widget.b15c1f0ea25c", fallback: "提案を反映")) {
                                            workoutStore.applyNextSetLoadSuggestion()
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                        .accessibilityIdentifier("watchApplyNextLoadSuggestion")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .id(restTimerAnchor(for: exercise.id))
                        }
                    }
                    .id(exercise.id)
                }

                Section {
                    Button {
                        if workoutStore.isWorkoutPaused {
                            workoutStore.resumeWorkout()
                        } else {
                            workoutStore.pauseWorkout()
                        }
                    } label: {
                        Label(
                            workoutStore.isWorkoutPaused ? L10n.string("watch_widget.0c6172650d06", fallback: "再開") : L10n.string("watch_widget.68283c0be6f6", fallback: "一時停止"),
                            systemImage: workoutStore.isWorkoutPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .accessibilityIdentifier("watchPauseWorkoutButton")

                    Button {
                        isEditingWorkoutNote = true
                    } label: {
                        Label(session.note == nil ? L10n.string("watch_widget.784d61a7d1fe", fallback: "音声・文字メモ") : L10n.string("watch_widget.6dacb17a2939", fallback: "メモを編集"), systemImage: "mic")
                    }
                    .accessibilityIdentifier("watchWorkoutNoteButton")

                    if let note = session.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(WatchAppTheme.mutedInk)
                            .lineLimit(3)
                    }

                    Button {
                        isConfirmingFinish = true
                    } label: {
                        Label(L10n.string("watch_widget.b1deb806b237", fallback: "完了して送信"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchAppTheme.positive)
                    .accessibilityIdentifier("watchFinishWorkoutButton")

                    Button(role: .destructive) {
                        isConfirmingCancel = true
                    } label: {
                        Label(L10n.string("watch_widget.49e3394121fb", fallback: "破棄"), systemImage: "xmark.circle")
                    }
                }
            }
            .onChange(of: workoutStore.restExerciseID) { _, exerciseID in
                guard let exerciseID else { return }
                withAnimation {
                    proxy.scrollTo(restTimerAnchor(for: exerciseID), anchor: .center)
                }
            }
            .onChange(of: session.completedSetCount) { _, _ in
                ensureSelectedExercise()
            }
            .onChange(of: activeWeightEditor?.id) { previousID, currentID in
                guard previousID != nil, currentID == nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation {
                        proxy.scrollTo("watch-set-switch-control", anchor: .center)
                    }
                }
            }
            .onChange(of: activeRepsEditor?.id) { previousID, currentID in
                guard previousID != nil, currentID == nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation {
                        proxy.scrollTo("watch-set-switch-control", anchor: .center)
                    }
                }
            }
            .onChange(of: activeRPEEditor?.id) { previousID, currentID in
                guard previousID != nil, currentID == nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation {
                        proxy.scrollTo("watch-set-switch-control", anchor: .center)
                    }
                }
            }
            .onChange(of: activeTempoEditor?.id) { previousID, currentID in
                guard previousID != nil, currentID == nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation {
                        proxy.scrollTo("watch-set-switch-control", anchor: .center)
                    }
                }
            }
            .onAppear {
                ensureSelectedExercise()
                guard workoutStore.isRestTimerRunning,
                      let restExerciseID = workoutStore.restExerciseID else {
                    return
                }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(restTimerAnchor(for: restExerciseID), anchor: .center)
                }
            }
        }
        .navigationTitle(L10n.string("watch_widget.31d6157ec148", fallback: "記録中"))
        .onReceive(timer) { _ in
            workoutStore.tickRestTimer()
        }
        .sheet(isPresented: $isEditingRestTimer) {
            NavigationStack {
                WatchRestTimerEntryView(currentSeconds: workoutStore.restRemaining)
            }
        }
        .sheet(isPresented: $isEditingWorkoutNote) {
            NavigationStack {
                WatchWorkoutNoteEntryView(currentNote: session.note ?? "")
            }
        }
        .sheet(item: $activeWeightEditor) { editor in
            NavigationStack {
                WatchWeightEntryView(
                    exerciseID: editor.exercise.id,
                    setID: editor.set.id,
                    currentWeight: editor.set.actualWeight,
                    unit: editor.unit,
                    supportsAssistedLoad: editor.exercise.supportsAssistedLoad
                )
            }
        }
        .sheet(item: $activeRepsEditor) { editor in
            NavigationStack {
                WatchRepsEntryView(
                    exerciseID: editor.exercise.id,
                    setID: editor.set.id,
                    currentReps: editor.set.actualReps
                )
            }
        }
        .sheet(item: $activeRPEEditor) { editor in
            NavigationStack {
                WatchRPESelectionView(
                    exerciseID: editor.exercise.id,
                    setID: editor.set.id,
                    currentRPE: editor.set.rpe ?? editor.set.targetRPE
                )
            }
        }
        .sheet(item: $activeTempoEditor) { editor in
            NavigationStack {
                WatchTempoEntryView(
                    exerciseID: editor.exercise.id,
                    setID: editor.set.id,
                    concentricSeconds: editor.set.plannedConcentricSeconds,
                    eccentricSeconds: editor.set.plannedEccentricSeconds,
                    beatSpeed: editor.set.plannedTempoBeatSpeed
                )
            }
        }
        .confirmationDialog(L10n.string("watch_widget.1b2df563ab78", fallback: "ワークアウトを完了しますか？"), isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button(L10n.string("watch_widget.5a4fab46f0a5", fallback: "完了してiPhoneへ送信")) {
                workoutStore.finishWorkout()
            }
            Button(L10n.string("watch_widget.5ce04d515d1c", fallback: "続ける"), role: .cancel) {}
        } message: {
            Text(L10n.string("watch_widget.0e66f9cd10a3", fallback: "未完了セットも含めて現在の内容を保存します。"))
        }
        .confirmationDialog(L10n.string("watch_widget.a9bcd1d54574", fallback: "記録を破棄しますか？"), isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button(L10n.string("watch_widget.49e3394121fb", fallback: "破棄"), role: .destructive) {
                workoutStore.cancelWorkout()
            }
            Button(L10n.string("watch_widget.5ce04d515d1c", fallback: "続ける"), role: .cancel) {}
        } message: {
            Text(L10n.string("watch_widget.cbeb009a0ca4", fallback: "Watch上の実行中記録は削除されます。"))
        }
    }

    private var activeSet: (exercise: WatchWorkoutExerciseSnapshot, set: WatchWorkoutSetSnapshot)? {
        guard let session = workoutStore.activeSession else {
            return nil
        }

        for exercise in session.exercises {
            if let set = exercise.sets.first(where: { $0.startedAt != nil && !$0.isCompleted }) {
                return (exercise, set)
            }
        }
        return nil
    }

    private var pendingExercises: [WatchWorkoutExerciseSnapshot] {
        guard let session = workoutStore.activeSession else {
            return []
        }
        return session.exercises.filter { exercise in
            exercise.sets.contains { $0.startedAt == nil && !$0.isCompleted }
        }
    }

    private var visibleExercises: [WatchWorkoutExerciseSnapshot] {
        guard let session = workoutStore.activeSession else {
            return []
        }
        return session.exercises.filter { exercise in
            exercise.sets.contains { !$0.isCompleted }
                || (workoutStore.isRestTimerRunning && workoutStore.restExerciseID == exercise.id)
        }
    }

    private var selectedNextSet: (exerciseID: UUID, setID: UUID)? {
        guard let selectedPendingSet else {
            return nil
        }
        return (selectedPendingSet.exercise.id, selectedPendingSet.set.id)
    }

    private var selectedPendingSet: (
        exercise: WatchWorkoutExerciseSnapshot,
        set: WatchWorkoutSetSnapshot
    )? {
        let exercise = pendingExercises.first(where: { $0.id == selectedExerciseID })
            ?? pendingExercises.first
        guard let exercise,
              let set = exercise.sets.first(where: { $0.startedAt == nil && !$0.isCompleted }) else {
            return nil
        }
        return (exercise, set)
    }

    private func ensureSelectedExercise() {
        guard !pendingExercises.contains(where: { $0.id == selectedExerciseID }) else { return }
        selectedExerciseID = pendingExercises.first?.id
    }

    private func restTimerAnchor(for exerciseID: UUID) -> String {
        "rest-timer-\(exerciseID.uuidString)"
    }

    private func tempoSummary(for set: WatchWorkoutSetSnapshot) -> String {
        guard let concentric = set.plannedConcentricSeconds,
              let eccentric = set.plannedEccentricSeconds else {
            return L10n.string("watch_widget.2ab8c8962b18", fallback: "テンポを設定")
        }
        return L10n.string("watch_widget.f1b303fe38bd", fallback: "上{{value1}}s・下{{value2}}s・{{value3}}回/秒", values: [String(describing: concentric), String(describing: eccentric), String(describing: set.resolvedTempoBeatSpeed)])
    }
}

private struct WatchTempoGuideView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    let target: WatchTempoTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(statusText)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(WatchAppTheme.positive)
                .accessibilityValue(L10n.string("watch_widget.8cfae2e66c26", fallback: "{{value1}}回/秒", values: [String(describing: target.beatSpeed)]))
                .accessibilityIdentifier("watchTempoCue")
                .accessibilityElement(children: .ignore)

            HStack(spacing: 6) {
                if !workoutStore.isTempoGuideFinished {
                    Button {
                        if workoutStore.isTempoGuidePaused {
                            workoutStore.resumeTempoGuide()
                        } else {
                            workoutStore.pauseTempoGuide()
                        }
                    } label: {
                        Image(systemName: workoutStore.isTempoGuidePaused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(workoutStore.isTempoGuidePaused ? L10n.string("watch_widget.d30b38ecfe50", fallback: "テンポ案内を再開") : L10n.string("watch_widget.f8a940f32407", fallback: "テンポ案内を一時停止"))
                    .accessibilityIdentifier("watchTempoPauseButton")

                    Button {
                        workoutStore.skipTempoPhase()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .accessibilityLabel(L10n.string("watch_widget.96ff4778f70e", fallback: "現在の動作をスキップ"))
                    .accessibilityIdentifier("watchTempoSkipButton")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusText: String {
        if workoutStore.isTempoGuideFinished {
            return L10n.string("watch_widget.8e715c8cf147", fallback: "目標テンポ完了")
        }
        if workoutStore.isTempoGuidePaused {
            return L10n.string("watch_widget.97c1d37f643b", fallback: "一時停止・上げ{{value1}}秒／下げ{{value2}}秒", values: [String(describing: target.concentricSeconds), String(describing: target.eccentricSeconds)])
        }
        return workoutStore.tempoCue?.displayText
            ?? L10n.string("watch_widget.53a48095c684", fallback: "上げ{{value1}}秒／下げ{{value2}}秒", values: [String(describing: target.concentricSeconds), String(describing: target.eccentricSeconds)])
    }
}

struct WatchActiveWeightEditor: Identifiable {
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot
    let unit: WatchWeightUnit

    var id: UUID { self.set.id }
}

struct WatchActiveRepsEditor: Identifiable {
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot

    var id: UUID { self.set.id }
}

struct WatchActiveRPEEditor: Identifiable {
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot

    var id: UUID { self.set.id }
}

struct WatchActiveTempoEditor: Identifiable {
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot

    var id: UUID { self.set.id }
}

struct WatchCompletedSetsArchiveView: View {
    let session: WatchWorkoutSessionSnapshot

    var body: some View {
        List {
            ForEach(session.exercises.filter { $0.completedSetCount > 0 }) { exercise in
                Section(exercise.name) {
                    ForEach(exercise.sets.filter(\.isCompleted)) { set in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(WatchAppTheme.positive)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.string("watch_widget.cf0fe40d1182", fallback: "セット {{value1}}", values: [String(describing: set.setOrder)]))
                                    .font(.caption.bold())
                                Text(
                                    "\(formatWeight(set.actualWeight, unit: session.weightUnit)) × "
                                        + L10n.string("watch_widget.672403542889", fallback: "{{value1}}回", values: [String(describing: set.actualReps)])
                                )
                                .font(.headline)
                            }

                            Spacer()

                            if let rpe = set.rpe {
                                Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                                    .font(.caption2)
                                    .foregroundStyle(WatchAppTheme.mutedInk)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.string("watch_widget.31a26178d3b4", fallback: "完了セット"))
    }
}

struct WatchWorkoutNoteEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(currentNote: String) {
        _note = State(initialValue: currentNote)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextField(L10n.string("watch_widget.a2c4001d98d3", fallback: "メモ"), text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("watchWorkoutNoteField")

                Button(L10n.string("watch_widget.139ccbf8df18", fallback: "保存")) {
                    workoutStore.setWorkoutNote(note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchWorkoutNoteButton")
            }
        }
        .navigationTitle(L10n.string("watch_widget.a2c4001d98d3", fallback: "メモ"))
    }
}
