import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    var body: some View {
        NavigationStack {
            Group {
                if let activeSession = workoutStore.activeSession {
                    WatchActiveWorkoutView(session: activeSession)
                } else if let plan = workoutStore.selectedPlan {
                    WatchPlanDetailView(
                        plan: plan,
                        statusMessage: workoutStore.statusMessage,
                        pendingSession: workoutStore.pendingFinishedSession
                    )
                } else if !workoutStore.plans.isEmpty {
                    WatchMenuSelectionView(
                        plans: workoutStore.plans,
                        statusMessage: workoutStore.statusMessage,
                        pendingSession: workoutStore.pendingFinishedSession
                    )
                } else {
                    WatchEmptyPlanView(statusMessage: workoutStore.statusMessage)
                }
            }
            .navigationTitle("Gym")
        }
    }
}

private struct WatchEmptyPlanView: View {
    let statusMessage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("メニュー待ち")
                .font(.headline)

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("iPhoneの記録タブからApple Watchへメニューを同期します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct WatchMenuSelectionView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    let plans: [WatchWorkoutPlanSnapshot]
    let statusMessage: String
    let pendingSession: WatchWorkoutSessionSnapshot?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日のメニュー")
                        .font(.headline)
                    Text("\(plans.count)件から選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("メニュー") {
                ForEach(plans) { plan in
                    Button {
                        workoutStore.selectPlan(plan)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(planOverview(plan))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchMenu-\(plan.name)")
                }
            }

            if let pendingSession {
                Section("未送信") {
                    Button {
                        workoutStore.resendPendingSession()
                    } label: {
                        Label("\(pendingSession.title) を再送", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("watchResendPendingSessionButton")
                }
            }
        }
    }
}

private struct WatchPlanDetailView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    let plan: WatchWorkoutPlanSnapshot
    let statusMessage: String
    let pendingSession: WatchWorkoutSessionSnapshot?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                    Text(planOverview(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    workoutStore.startWorkout()
                } label: {
                    Label("開始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watchStartWorkoutButton")

                Button {
                    workoutStore.clearPlanSelection()
                } label: {
                    Label("メニュー変更", systemImage: "arrow.left.circle")
                }
                .accessibilityIdentifier("watchChangeMenuButton")

                if let pendingSession {
                    Button {
                        workoutStore.resendPendingSession()
                    } label: {
                        Label("\(pendingSession.title) を再送", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("watchResendPendingSessionButton")
                }
            }

            ForEach(plan.exercises) { exercise in
                NavigationLink {
                    WatchExercisePreviewView(exercise: exercise, unit: plan.weightUnit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(targetSummary(for: exercise, unit: plan.weightUnit))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct WatchExercisePreviewView: View {
    let exercise: WatchPlanExerciseSnapshot
    let unit: WatchWeightUnit

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                    Text(exercise.primaryMuscleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("休憩 \(exercise.restSeconds)秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("セット") {
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setOrder)")
                            .font(.headline)
                            .frame(width: 26, height: 26)
                            .background(.green.opacity(0.2), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatWeight(set.targetWeight, unit: unit))
                                .font(.headline)
                            Text("\(set.targetReps)回")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}

private struct WatchActiveWorkoutView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false
    @State private var isEditingRestTimer = false
    @State private var isEditingWorkoutNote = false

    let session: WatchWorkoutSessionSnapshot

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.headline)
                    Text("\(session.completedSetCount)/\(session.totalSetCount)セット・\(session.completedRepCount)回記録")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watchWorkoutProgress")

                    if let nextSet {
                        Button {
                            workoutStore.startSet(exerciseID: nextSet.exerciseID, setID: nextSet.setID)
                        } label: {
                            Label("次のセットを開始", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityIdentifier("watchStartNextSetButton")
                    }

                    ProgressView(
                        value: Double(session.completedSetCount),
                        total: Double(max(session.totalSetCount, 1))
                    )
                    .tint(.green)

                    WatchLiveMetricsView(
                        metrics: workoutStore.liveMetrics,
                        statusMessage: workoutStore.healthStatusMessage,
                        powerModeMessage: workoutStore.sensorPowerModeMessage
                    )

                    if let suggestion = workoutStore.setStartSuggestion {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("動作候補: \(suggestion.exerciseName)", systemImage: "sensor.tag.radiowaves.forward")
                                .font(.caption.bold())
                            Text("信頼度 \(Int(suggestion.confidence * 100))%・\(suggestion.reason)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("開始") {
                                    workoutStore.acceptSetStartSuggestion()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
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

            if workoutStore.isRestTimerRunning {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("休憩 \(formatDuration(workoutStore.restRemaining))", systemImage: "timer")
                                .font(.headline)
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
                        .font(.caption)
                        .accessibilityIdentifier("watchRestTimerEntry")

                        if let restReadinessMessage = workoutStore.restReadinessMessage {
                            Text(restReadinessMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let suggestion = workoutStore.nextSetLoadSuggestion {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("次: \(suggestion.exerciseName) \(formatWeight(suggestion.suggestedWeight, unit: session.weightUnit)) × \(suggestion.suggestedReps)回")
                                    .font(.caption.bold())
                                Text(suggestion.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button("提案を反映") {
                                    workoutStore.applyNextSetLoadSuggestion()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .accessibilityIdentifier("watchApplyNextLoadSuggestion")
                            }
                        }
                    }
                }
            }

            ForEach(session.exercises) { exercise in
                Section(exercise.name) {
                    ForEach(exercise.sets) { set in
                        WatchSetControlRow(exercise: exercise, set: set, unit: session.weightUnit)
                    }
                }
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
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Button {
                    isConfirmingFinish = true
                } label: {
                    Label("完了して送信", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("watchFinishWorkoutButton")

                Button(role: .destructive) {
                    isConfirmingCancel = true
                } label: {
                    Label("破棄", systemImage: "xmark.circle")
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

    private var nextSet: (exerciseID: UUID, setID: UUID)? {
        let hasActiveSet = session.exercises.contains { exercise in
            exercise.sets.contains { $0.startedAt != nil && !$0.isCompleted }
        }
        guard !hasActiveSet else { return nil }

        for exercise in session.exercises {
            if let set = exercise.sets.first(where: { $0.startedAt == nil && !$0.isCompleted }) {
                return (exercise.id, set.id)
            }
        }
        return nil
    }
}

private struct WatchWorkoutNoteEntryView: View {
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
                .tint(.green)
                .accessibilityIdentifier("saveWatchWorkoutNoteButton")
            }
        }
        .navigationTitle("メモ")
    }
}

private struct WatchSetControlRow: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    @State private var activeEditor: WatchSetEditor?

    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot
    let unit: WatchWeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(set.setOrder)")
                    .font(.headline)
                    .frame(width: 26, height: 26)
                    .background(set.isCompleted ? .green.opacity(0.22) : .secondary.opacity(0.16), in: Circle())

                Text("目標 \(formatWeight(set.targetWeight, unit: unit)) × \(set.targetReps)回")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(statusTitle)
                    .font(.caption2.bold())
                    .foregroundStyle(statusTint)
            }

            if set.startedAt == nil && !set.isCompleted {
                Button {
                    workoutStore.startSet(exerciseID: exercise.id, setID: set.id)
                } label: {
                    Label("セット開始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("watchSetStart-\(exercise.sortOrder)-\(set.setOrder)")
            } else {
                Text("実績 \(formatWeight(set.actualWeight, unit: unit)) × \(set.actualReps)回")
                    .font(.headline)
                    .accessibilityIdentifier("watchSetActual-\(exercise.sortOrder)-\(set.setOrder)")

                if set.isCompleted {
                    VStack(alignment: .leading, spacing: 7) {
                        if let sensorSummary = set.sensorSummary {
                            WatchSetSensorSummaryView(summary: sensorSummary)
                            if let estimatedReps = sensorSummary.estimatedReps,
                               estimatedReps != set.actualReps,
                               (sensorSummary.confidence ?? 0) >= 0.35 {
                                Button {
                                    workoutStore.applyEstimatedReps(exerciseID: exercise.id, setID: set.id)
                                } label: {
                                    Label("推定\(estimatedReps)回を反映", systemImage: "arrow.uturn.backward.circle")
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .accessibilityIdentifier("watchApplyEstimatedReps")
                            }
                        }

                        HStack {
                        if set.rpe != nil {
                            Label(rpeTitle, systemImage: "gauge")
                                .font(.caption)
                        }

                        Spacer()

                        Button {
                            workoutStore.setCompletion(
                                exerciseID: exercise.id,
                                setID: set.id,
                                isCompleted: false
                            )
                        } label: {
                            Label("修正", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("watchSetComplete-\(exercise.sortOrder)-\(set.setOrder)")
                        }
                    }
                } else {
                    actualValueControls

                    if let estimate = workoutStore.motionEstimate(exerciseID: exercise.id, setID: set.id) {
                        Label(
                            "動作推定 \(estimate.estimatedReps)回・信頼度 \(Int(estimate.confidence * 100))%",
                            systemImage: "sensor.tag.radiowaves.forward"
                        )
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("watchMotionEstimate")
                    }

                    if workoutStore.isSetCompletionSuggested,
                       workoutStore.motionEstimate(exerciseID: exercise.id, setID: set.id) != nil {
                        Label("動作停止を検知しました", systemImage: "checkmark.circle")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("watchSetCompletionSuggestion")
                    }

                    HStack {
                        Button {
                            activeEditor = .rpe
                        } label: {
                            Label(rpeTitle, systemImage: "gauge")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("watchSetRPE-\(exercise.sortOrder)-\(set.setOrder)")

                        Spacer()

                        Button {
                            workoutStore.setCompletion(
                                exerciseID: exercise.id,
                                setID: set.id,
                                isCompleted: true
                            )
                        } label: {
                            Label("完了", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityIdentifier("watchSetComplete-\(exercise.sortOrder)-\(set.setOrder)")
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $activeEditor) { editor in
            NavigationStack {
                switch editor {
                case .weight:
                    WatchWeightEntryView(
                        exerciseID: exercise.id,
                        setID: set.id,
                        currentWeight: set.actualWeight,
                        unit: unit
                    )
                case .reps:
                    WatchRepsEntryView(
                        exerciseID: exercise.id,
                        setID: set.id,
                        currentReps: set.actualReps
                    )
                case .rpe:
                    WatchRPESelectionView(
                        exerciseID: exercise.id,
                        setID: set.id,
                        currentRPE: set.rpe
                    )
                }
            }
        }
    }

    private var actualValueControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("重量")
                    .frame(width: 32, alignment: .leading)

                Spacer()

                Button {
                    activeEditor = .weight
                } label: {
                    Label(formatWeight(set.actualWeight, unit: unit), systemImage: "dial.medium")
                }
                .accessibilityLabel("重量をリールで設定")
                .accessibilityIdentifier("watchSetWeightEntry-\(exercise.sortOrder)-\(set.setOrder)")
            }

            HStack {
                Text("回数")
                    .frame(width: 32, alignment: .leading)

                Spacer()

                Button {
                    activeEditor = .reps
                } label: {
                    Label("\(set.actualReps)回", systemImage: "dial.medium")
                }
                .accessibilityLabel("回数をリールで設定")
                .accessibilityIdentifier("watchSetRepsEntry-\(exercise.sortOrder)-\(set.setOrder)")
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private var statusTitle: String {
        if set.isCompleted { return "完了" }
        if set.startedAt != nil { return "実績入力中" }
        return "未開始"
    }

    private var statusTint: Color {
        if set.isCompleted { return .green }
        if set.startedAt != nil { return .orange }
        return .secondary
    }

    private var rpeTitle: String {
        guard let rpe = set.rpe else {
            return "RPE"
        }

        return "RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))"
    }
}

private struct WatchLiveMetricsView: View {
    let metrics: WatchLiveWorkoutMetrics
    let statusMessage: String
    let powerModeMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                CompactWatchLiveMetric(
                    value: metrics.currentHeartRate.map { "\(Int($0))" } ?? "-",
                    systemImage: "heart.fill",
                    tint: .red
                )
                CompactWatchLiveMetric(
                    value: metrics.averageHeartRate.map { "平均\(Int($0))" } ?? "平均-",
                    systemImage: "heart",
                    tint: .pink
                )
                CompactWatchLiveMetric(
                    value: metrics.maximumHeartRate.map { "最大\(Int($0))" } ?? "最大-",
                    systemImage: "heart.circle",
                    tint: .orange
                )
            }
            HStack(spacing: 8) {
                CompactWatchLiveMetric(
                    value: formatElapsed(metrics.elapsedSeconds),
                    systemImage: "timer",
                    tint: .green
                )
                CompactWatchLiveMetric(
                    value: metrics.activeEnergyKilocalories.map { "\(Int($0))" } ?? "-",
                    systemImage: "flame.fill",
                    tint: .orange
                )
                CompactWatchLiveMetric(
                    value: zoneValue,
                    systemImage: "gauge.with.dots.needle.50percent",
                    tint: .cyan
                )
            }

            if statusMessage != "センサー計測中" {
                Text(statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Text(powerModeMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityIdentifier("watchLiveMetrics")
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private var zoneValue: String {
        guard let zone = metrics.heartRateZone else { return "Z-" }
        let seconds = metrics.heartRateZoneDurations[zone, default: 0]
        return "Z\(zone) \(formatElapsed(seconds))"
    }
}

private struct CompactWatchLiveMetric: View {
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(value)
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchSetSensorSummaryView: View {
    let summary: WatchSetSensorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let estimatedReps = summary.estimatedReps {
                Label("動作推定 \(estimatedReps)回", systemImage: "sensor.tag.radiowaves.forward")
            }
            if let averageHeartRate = summary.averageHeartRate {
                Label("セット平均 \(Int(averageHeartRate)) bpm", systemImage: "heart.fill")
            }
            if let consistency = summary.movementConsistency {
                Label("動作の安定 \(Int(consistency * 100))%", systemImage: "waveform.path")
            }
            if let concentric = summary.averageConcentricDuration,
               let eccentric = summary.averageEccentricDuration {
                Label(
                    "挙上 \(concentric.formatted(.number.precision(.fractionLength(1))))秒・下降 \(eccentric.formatted(.number.precision(.fractionLength(1))))秒",
                    systemImage: "metronome"
                )
            }
            if let range = summary.relativeRangeOfMotion,
               let consistency = summary.rangeOfMotionConsistency {
                Label("相対可動域 \(Int(range * 100))%・一貫性 \(Int(consistency * 100))%", systemImage: "arrow.up.and.down")
            }
            if let velocityLoss = summary.velocityLossPercent {
                Label("動作速度変化 \(velocityLoss.formatted(.number.precision(.fractionLength(0))))%", systemImage: "speedometer")
            }
            if let candidate = summary.exerciseCandidateName,
               let confidence = summary.exerciseCandidateConfidence {
                Label("種目候補 \(candidate) \(Int(confidence * 100))%", systemImage: "checkmark.circle")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private enum WatchSetEditor: String, Identifiable {
    case weight
    case reps
    case rpe

    var id: String { rawValue }
}

private struct WatchWeightEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID
    let unit: WatchWeightUnit

    @State private var displayedWeight: Double

    init(exerciseID: UUID, setID: UUID, currentWeight: Double, unit: WatchWeightUnit) {
        self.exerciseID = exerciseID
        self.setID = setID
        self.unit = unit
        _displayedWeight = State(
            initialValue: unit == .kg ? currentWeight : currentWeight * 2.2046226218
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("整数", selection: wholePart) {
                        ForEach(0...maximumWholePart, id: \.self) { value in
                            Text("\(value)")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 72, height: 76)
                    .clipped()
                    .accessibilityLabel("重量の整数")
                    .accessibilityIdentifier("watchWeightWholePicker")

                    Text(".")
                        .font(.headline)

                    Picker("小数", selection: tenthsPart) {
                        ForEach(0...9, id: \.self) { value in
                            Text("\(value)")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 48, height: 76)
                    .clipped()
                    .accessibilityLabel("重量の小数")
                    .accessibilityIdentifier("watchWeightTenthsPicker")

                    Text(unit.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }

                HStack(spacing: 6) {
                    TextField(
                        "手入力",
                        value: $displayedWeight,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchWeightField")

                    Text(unit.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("反映") {
                    let kilograms = unit == .kg ? displayedWeight : displayedWeight / 2.2046226218
                    workoutStore.setWeight(exerciseID: exerciseID, setID: setID, weight: kilograms)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("saveWatchWeightButton")
            }
        }
        .navigationTitle("重量")
    }

    private var maximumWholePart: Int {
        unit == .kg ? 999 : 2_202
    }

    private var wholePart: Binding<Int> {
        Binding(
            get: { min(maximumWholePart, max(0, Int(displayedWeight.rounded(.down)))) },
            set: { displayedWeight = Double($0) + Double(tenthsPart.wrappedValue) / 10 }
        )
    }

    private var tenthsPart: Binding<Int> {
        Binding(
            get: { max(0, min(9, Int((displayedWeight * 10).rounded()) % 10)) },
            set: { displayedWeight = Double(wholePart.wrappedValue) + Double($0) / 10 }
        )
    }
}

private struct WatchRepsEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID

    @State private var reps: Int

    init(exerciseID: UUID, setID: UUID, currentReps: Int) {
        self.exerciseID = exerciseID
        self.setID = setID
        _reps = State(initialValue: currentReps)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("回数", selection: $reps) {
                        ForEach(0...999, id: \.self) { value in
                            Text("\(value)")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 104, height: 80)
                    .clipped()
                    .accessibilityLabel("回数")
                    .accessibilityIdentifier("watchRepsPicker")

                    Text("回")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                }

                TextField("手入力", value: $reps, format: .number)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("watchRepsField")

                Button("反映") {
                    workoutStore.setReps(exerciseID: exerciseID, setID: setID, reps: reps)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("saveWatchRepsButton")
            }
        }
        .navigationTitle("回数")
    }
}

private struct WatchRestTimerEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var seconds: Int

    init(currentSeconds: Int) {
        let normalized = min(600, max(5, Int((Double(currentSeconds) / 5).rounded()) * 5))
        _seconds = State(initialValue: normalized)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("休憩時間", selection: $seconds) {
                        ForEach(Array(stride(from: 5, through: 600, by: 5)), id: \.self) { value in
                            Text(formatDuration(value))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 112, height: 76)
                    .clipped()
                    .accessibilityLabel("休憩時間")
                    .accessibilityIdentifier("watchRestSecondsPicker")

                    Text("分:秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                }

                HStack(spacing: 6) {
                    TextField("手入力", value: $seconds, format: .number)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("watchRestSecondsField")

                    Text("秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("反映") {
                    workoutStore.setRestTimer(seconds: seconds)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("saveWatchRestSecondsButton")
            }
        }
        .navigationTitle("休憩時間")
    }
}

private struct WatchRPESelectionView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID

    @State private var rpe: Double

    init(exerciseID: UUID, setID: UUID, currentRPE: Double?) {
        self.exerciseID = exerciseID
        self.setID = setID
        _rpe = State(initialValue: currentRPE ?? 8)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("RPE", selection: $rpe) {
                        ForEach(2...20, id: \.self) { halfStep in
                            let value = Double(halfStep) / 2
                            Text(value.formatted(.number.precision(.fractionLength(0...1))))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 104, height: 80)
                    .clipped()
                    .accessibilityLabel("RPE")
                    .accessibilityIdentifier("watchRPEPicker")

                    Text("RPE")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                }

                TextField(
                    "手入力",
                    value: $rpe,
                    format: .number.precision(.fractionLength(0...1))
                )
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("watchRPEField")

                Button("反映") {
                    workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: rpe)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("saveWatchRPEButton")

                Button("RPEなし") {
                    workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: nil)
                    dismiss()
                }
                .font(.caption)
                .accessibilityIdentifier("clearWatchRPEButton")
            }
        }
        .navigationTitle("RPE")
    }
}

private func formatWeight(_ value: Double, unit: WatchWeightUnit) -> String {
    switch unit {
    case .kg:
        value.formatted(.number.precision(.fractionLength(0...1))) + " kg"
    case .lb:
        (value * 2.2046226218).formatted(.number.precision(.fractionLength(0...1))) + " lb"
    }
}

private func targetSummary(for exercise: WatchPlanExerciseSnapshot, unit: WatchWeightUnit) -> String {
    guard let firstSet = exercise.sets.first else {
        return "セット未設定"
    }

    let hasSameTarget = exercise.sets.allSatisfy {
        $0.targetWeight == firstSet.targetWeight && $0.targetReps == firstSet.targetReps
    }

    if hasSameTarget {
        return "\(formatWeight(firstSet.targetWeight, unit: unit)) × \(firstSet.targetReps)回 × \(exercise.sets.count)セット"
    }

    let totalReps = exercise.sets.reduce(0) { $0 + $1.targetReps }
    return "\(exercise.sets.count)セット・目標 合計\(totalReps)回"
}

private func planOverview(_ plan: WatchWorkoutPlanSnapshot) -> String {
    if let exercise = plan.exercises.first, plan.exercises.count == 1 {
        return "\(exercise.name)・\(exercise.sets.count)セット・計\(plan.totalTargetRepCount)回"
    }

    return "\(plan.exercises.count)種目・\(plan.totalSetCount)セット・計\(plan.totalTargetRepCount)回"
}

private func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):" + String(format: "%02d", seconds)
}

#Preview {
    WatchContentView()
        .environmentObject(WatchWorkoutStore())
}
