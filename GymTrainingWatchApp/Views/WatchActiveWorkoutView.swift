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
            activeWorkoutContent(session: session)
        } else {
            Text("記録中のワークアウトがありません")
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
                        Text("\(session.completedSetCount)/\(session.totalSetCount)セット・\(session.completedRepCount)回記録")
                            .font(.caption)
                            .foregroundStyle(WatchAppTheme.mutedInk)
                            .accessibilityIdentifier("watchWorkoutProgress")

                        if let activeSet {
                            Text("\(activeSet.exercise.name)・セット\(activeSet.set.setOrder)")
                                .font(.caption.bold())
                                .foregroundStyle(WatchAppTheme.positive)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("実績 \(formatWeight(activeSet.set.actualWeight, unit: session.weightUnit)) × \(activeSet.set.actualReps)回")
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
                                        Label("重量", systemImage: "dial.medium")
                                    }
                                    .accessibilityLabel("実行中セットの重量を変更")
                                    .accessibilityIdentifier("watchActiveWeightEntry")

                                    Button {
                                        activeRepsEditor = WatchActiveRepsEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Label("回数", systemImage: "number")
                                    }
                                    .accessibilityLabel("実行中セットの回数を変更")
                                    .accessibilityIdentifier("watchActiveRepsEntry")

                                    Button {
                                        activeTempoEditor = WatchActiveTempoEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Label("テンポ", systemImage: "metronome")
                                    }
                                    .accessibilityLabel("実行中セットのテンポを変更")
                                    .accessibilityIdentifier("watchActiveTempoEntry")

                                    Button {
                                        activeRPEEditor = WatchActiveRPEEditor(
                                            exercise: activeSet.exercise,
                                            set: activeSet.set
                                        )
                                    } label: {
                                        Text("RPE")
                                    }
                                    .accessibilityLabel("実行中セットのRPEを変更")
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
                                        Label("取消", systemImage: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("セット開始を取り消す")
                                    .accessibilityIdentifier("watchCancelActiveSetButton")

                                    Button {
                                        workoutStore.setCompletion(
                                            exerciseID: activeSet.exercise.id,
                                            setID: activeSet.set.id,
                                            isCompleted: true
                                        )
                                    } label: {
                                        Label("完了", systemImage: "checkmark")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(WatchAppTheme.positive)
                                    .accessibilityLabel("セットを完了")
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
                            Picker("次の種目", selection: $selectedExerciseID) {
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
                                .accessibilityLabel("開始前にテンポを設定")
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
                                    activeSet == nil ? "セットを開始" : "選択セットへ切替",
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
                                    "完了セット \(session.completedSetCount)件",
                                    systemImage: "archivebox.fill"
                                )
                            }
                            .accessibilityIdentifier("watchCompletedSetsArchiveLink")
                        }

                        if let suggestion = workoutStore.setStartSuggestion {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("動作候補: \(suggestion.exerciseName)", systemImage: "sensor.tag.radiowaves.forward")
                                    .font(.caption.bold())
                                Text("信頼度 \(Int(suggestion.confidence * 100))%・\(suggestion.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(WatchAppTheme.mutedInk)
                                HStack {
                                    Button("開始") {
                                        workoutStore.acceptSetStartSuggestion()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(WatchAppTheme.positive)
                                    .accessibilityIdentifier("watchAcceptSetStartSuggestion")

                                    Button("違う") {
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
                                    Label("休憩 \(formatDuration(workoutStore.restRemaining))", systemImage: "timer")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(WatchAppTheme.positive)
                                        .accessibilityIdentifier("watchRestTimer")

                                    Spacer()

                                    Button {
                                        workoutStore.stopRestTimer()
                                    } label: {
                                        Image(systemName: "forward.end.fill")
                                    }
                                    .accessibilityLabel("休憩をスキップ")
                                }

                                Button {
                                    isEditingRestTimer = true
                                } label: {
                                    Label("時間を変更", systemImage: "dial.medium")
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
                                            "次: \(suggestion.exerciseName) \(formatWeight(suggestion.suggestedWeight, unit: session.weightUnit)) × \(suggestion.suggestedReps)回"
                                        )
                                            .font(.caption.bold())
                                        Text(suggestion.reason)
                                            .font(.caption2)
                                            .foregroundStyle(WatchAppTheme.mutedInk)
                                        Button("提案を反映") {
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
                            workoutStore.isWorkoutPaused ? "再開" : "一時停止",
                            systemImage: workoutStore.isWorkoutPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .accessibilityIdentifier("watchPauseWorkoutButton")

                    Button {
                        isEditingWorkoutNote = true
                    } label: {
                        Label(session.note == nil ? "音声・文字メモ" : "メモを編集", systemImage: "mic")
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
                        Label("完了して送信", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchAppTheme.positive)
                    .accessibilityIdentifier("watchFinishWorkoutButton")

                    Button(role: .destructive) {
                        isConfirmingCancel = true
                    } label: {
                        Label("破棄", systemImage: "xmark.circle")
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
        .navigationTitle("記録中")
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
                    currentRPE: editor.set.rpe
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
        .confirmationDialog("ワークアウトを完了しますか？", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("完了してiPhoneへ送信") {
                workoutStore.finishWorkout()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("未完了セットも含めて現在の内容を保存します。")
        }
        .confirmationDialog("記録を破棄しますか？", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("破棄", role: .destructive) {
                workoutStore.cancelWorkout()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("Watch上の実行中記録は削除されます。")
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
            return "テンポを設定"
        }
        return "上\(concentric)s・下\(eccentric)s・\(set.resolvedTempoBeatSpeed)回/秒"
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
                .accessibilityValue("\(target.beatSpeed)回/秒")
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
                    .accessibilityLabel(workoutStore.isTempoGuidePaused ? "テンポ案内を再開" : "テンポ案内を一時停止")
                    .accessibilityIdentifier("watchTempoPauseButton")

                    Button {
                        workoutStore.skipTempoPhase()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .accessibilityLabel("現在の動作をスキップ")
                    .accessibilityIdentifier("watchTempoSkipButton")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusText: String {
        if workoutStore.isTempoGuideFinished {
            return "目標テンポ完了"
        }
        if workoutStore.isTempoGuidePaused {
            return "一時停止・上げ\(target.concentricSeconds)秒／下げ\(target.eccentricSeconds)秒"
        }
        return workoutStore.tempoCue?.displayText
            ?? "上げ\(target.concentricSeconds)秒／下げ\(target.eccentricSeconds)秒"
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
                                Text("セット \(set.setOrder)")
                                    .font(.caption.bold())
                                Text(
                                    "\(formatWeight(set.actualWeight, unit: session.weightUnit)) × "
                                        + "\(set.actualReps)回"
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
        .navigationTitle("完了セット")
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
                TextField("メモ", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("watchWorkoutNoteField")

                Button("保存") {
                    workoutStore.setWorkoutNote(note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchWorkoutNoteButton")
            }
        }
        .navigationTitle("メモ")
    }
}
