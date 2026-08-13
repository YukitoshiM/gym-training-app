import SwiftUI

struct WatchSetControlRow: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    @State private var activeEditor: WatchSetEditor?

    let exerciseID: UUID
    let setID: UUID
    let unit: WatchWeightUnit

    private var exercise: WatchWorkoutExerciseSnapshot? {
        guard let session = workoutStore.activeSession else {
            return nil
        }
        return session.exercises.first { $0.id == exerciseID }
    }

    private var workoutSet: WatchWorkoutSetSnapshot? {
        guard let exercise else {
            return nil
        }
        return exercise.sets.first { $0.id == setID }
    }

    private var setSortOrder: Int {
        workoutSet?.setOrder ?? 0
    }

    private var exerciseSortOrder: Int {
        exercise?.sortOrder ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(setSortOrder)")
                    .font(.headline)
                    .frame(width: 26, height: 26)
                    .background(
                        isSetCompleted
                            ? WatchAppTheme.positive.opacity(0.22)
                            : WatchAppTheme.mutedInk.opacity(0.16),
                        in: Circle()
                    )

                Text("目標 \(formatWeight(targetWeight, unit: unit)) × \(targetReps)回")
                    .font(.caption2)
                    .foregroundStyle(WatchAppTheme.mutedInk)
                    .accessibilityIdentifier("watchSetTarget-\(exerciseSortOrder)-\(setSortOrder)")

                Spacer()

                Text(statusTitle)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
            }

            if workoutSet?.startedAt == nil && !isSetCompleted {
                if let set = workoutSet {
                    Button {
                        activeEditor = .tempo
                    } label: {
                        Label(tempoStatusTitle(for: set), systemImage: "metronome")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .accessibilityLabel("開始前にテンポを設定")
                    .accessibilityValue(tempoStatusTitle(for: set))
                    .accessibilityIdentifier("watchSetTempoEntry-\(exerciseSortOrder)-\(setSortOrder)")
                }

                Button {
                    if let exercise, let set = workoutSet {
                        workoutStore.startSet(exerciseID: exercise.id, setID: set.id)
                    }
                } label: {
                    Label("セット開始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("watchSetStart-\(exerciseSortOrder)-\(setSortOrder)")
            } else {
                if let set = workoutSet {
                    Text("実績 \(formatWeight(set.actualWeight, unit: unit)) × \(set.actualReps)回")
                        .font(.headline)
                        .accessibilityIdentifier("watchSetActual-\(exerciseSortOrder)-\(setSortOrder)")
                }

                if isSetCompleted {
                    completedSetFooter
                } else {
                    activeSetControls
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $activeEditor) { editor in
            if let exercise, let set = workoutSet {
                NavigationStack {
                    switch editor {
                    case .weight:
                        WatchWeightEntryView(
                            exerciseID: exercise.id,
                            setID: set.id,
                            currentWeight: set.actualWeight,
                            unit: unit,
                            supportsAssistedLoad: exercise.supportsAssistedLoad
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
                    case .tempo:
                        WatchTempoEntryView(
                            exerciseID: exercise.id,
                            setID: set.id,
                            concentricSeconds: set.plannedConcentricSeconds,
                            eccentricSeconds: set.plannedEccentricSeconds,
                            beatSpeed: set.plannedTempoBeatSpeed
                        )
                    }
                }
            }
        }
    }

    private var isSetCompleted: Bool {
        workoutSet?.isCompleted ?? false
    }

    private var statusTitle: String {
        guard let set = workoutSet else {
            return ""
        }
        if set.isCompleted {
            return "完了"
        }
        if set.startedAt != nil {
            return "実績入力中"
        }
        return "未開始"
    }

    private var statusColor: Color {
        guard let set = workoutSet else {
            return WatchAppTheme.mutedInk
        }
        if set.isCompleted { return WatchAppTheme.positive }
        if set.startedAt != nil { return WatchAppTheme.warning }
        return WatchAppTheme.mutedInk
    }

    private var targetWeight: Double {
        workoutSet?.targetWeight ?? 0
    }

    private var targetReps: Int {
        workoutSet?.targetReps ?? 0
    }

    private var completedSetFooter: some View {
        Group {
            if let set = workoutSet {
                VStack(alignment: .leading, spacing: 7) {
                    if let sensorSummary = set.sensorSummary {
                        WatchSetSensorSummaryView(summary: sensorSummary)

                        if let estimatedReps = sensorSummary.estimatedReps,
                           estimatedReps != set.actualReps,
                           (sensorSummary.confidence ?? 0) >= 0.35 {
                            Button {
                                workoutStore.applyEstimatedReps(
                                    exerciseID: setIDPair.exerciseID,
                                    setID: setIDPair.setID
                                )
                            } label: {
                                Label(
                                    "推定\(estimatedReps)回を反映",
                                    systemImage: "arrow.uturn.backward.circle"
                                )
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .accessibilityIdentifier("watchApplyEstimatedReps")
                        }
                    }

                    HStack {
                        if let rpe = set.rpe {
                            Label("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))", systemImage: "gauge")
                                .font(.caption)
                        }

                        Spacer()

                        Button {
                            workoutStore.setCompletion(
                                exerciseID: setIDPair.exerciseID,
                                setID: setIDPair.setID,
                                isCompleted: false
                            )
                        } label: {
                            Label("修正", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("watchSetComplete-\(exerciseSortOrder)-\(setSortOrder)")
                    }
                }
            }
        }
    }

    private var activeSetControls: some View {
        Group {
            if let set = workoutSet {
                VStack(spacing: 8) {
                    actualValueControls(for: set)

                    Button {
                        activeEditor = .tempo
                    } label: {
                        Label(
                            tempoStatusTitle(for: set),
                            systemImage: "metronome"
                        )
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .accessibilityLabel("テンポを設定")
                    .accessibilityIdentifier("watchSetTempoEntry-\(exerciseSortOrder)-\(setSortOrder)")

                    if let estimate = workoutStore.motionEstimate(exerciseID: setIDPair.exerciseID, setID: setIDPair.setID) {
                        Label(
                            "動作推定 \(estimate.estimatedReps)回・信頼度 \(Int(estimate.confidence * 100))%",
                            systemImage: "sensor.tag.radiowaves.forward"
                        )
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.positive)
                        .accessibilityIdentifier("watchMotionEstimate")
                    }

                    if workoutStore.isSetCompletionSuggested,
                       workoutStore.motionEstimate(exerciseID: setIDPair.exerciseID, setID: setIDPair.setID) != nil {
                        Label("動作停止を検知しました", systemImage: "checkmark.circle")
                            .font(.caption2.bold())
                            .foregroundStyle(WatchAppTheme.warning)
                            .accessibilityIdentifier("watchSetCompletionSuggestion")
                    }

                    HStack {
                        Button {
                            activeEditor = .rpe
                        } label: {
                            Label(rpeTitle(for: set), systemImage: "gauge")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("watchSetRPE-\(exerciseSortOrder)-\(setSortOrder)")

                        Spacer()

                        Button {
                            workoutStore.setCompletion(
                                exerciseID: setIDPair.exerciseID,
                                setID: setIDPair.setID,
                                isCompleted: true
                            )
                        } label: {
                            Label("完了", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchAppTheme.positive)
                        .accessibilityIdentifier("watchSetComplete-\(exerciseSortOrder)-\(setSortOrder)")
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var setIDPair: (exerciseID: UUID, setID: UUID) {
        guard let exercise else {
            return (UUID(), UUID())
        }
        return (exercise.id, setID)
    }

    private func actualValueControls(for set: WatchWorkoutSetSnapshot) -> some View {
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
                .accessibilityIdentifier("watchSetWeightEntry-\(exerciseSortOrder)-\(setSortOrder)")
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
                .accessibilityIdentifier("watchSetRepsEntry-\(exerciseSortOrder)-\(setSortOrder)")
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func rpeTitle(for set: WatchWorkoutSetSnapshot) -> String {
        guard let rpe = set.rpe else {
            return "RPE"
        }

        return "RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private func tempoStatusTitle(for set: WatchWorkoutSetSnapshot) -> String {
        guard let concentric = set.plannedConcentricSeconds,
              let eccentric = set.plannedEccentricSeconds,
              let beatSpeed = set.plannedTempoBeatSpeed else {
            return "テンポ"
        }

        return "上\(concentric)s・下\(eccentric)s・\(beatSpeed)回/秒"
    }
}

struct WatchLiveMetricsView: View {
    let metrics: WatchLiveWorkoutMetrics
    let statusMessage: String
    let powerModeMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                CompactWatchLiveMetric(
                    value: metrics.currentHeartRate.map { "\(Int($0))" } ?? "-",
                    systemImage: "heart.fill",
                    tint: WatchAppTheme.critical
                )
                CompactWatchLiveMetric(
                    value: metrics.averageHeartRate.map { "平均\(Int($0))" } ?? "平均-",
                    systemImage: "heart",
                    tint: WatchAppTheme.secondaryAccent
                )
                CompactWatchLiveMetric(
                    value: metrics.maximumHeartRate.map { "最大\(Int($0))" } ?? "最大-",
                    systemImage: "heart.circle",
                    tint: WatchAppTheme.warning
                )
            }
            HStack(spacing: 8) {
                CompactWatchLiveMetric(
                    value: formatElapsed(metrics.elapsedSeconds),
                    systemImage: "timer",
                    tint: WatchAppTheme.positive
                )
                CompactWatchLiveMetric(
                    value: metrics.activeEnergyKilocalories.map { "\(Int($0))" } ?? "-",
                    systemImage: "flame.fill",
                    tint: WatchAppTheme.warning
                )
                CompactWatchLiveMetric(
                    value: zoneValue,
                    systemImage: "gauge.with.dots.needle.50percent",
                    tint: WatchAppTheme.mutedInk
                )
            }

            if statusMessage != "センサー計測中" {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(WatchAppTheme.mutedInk)
                    .lineLimit(1)
            }
            Text(powerModeMessage)
                .font(.caption2)
                .foregroundStyle(WatchAppTheme.mutedInk)
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

struct CompactWatchLiveMetric: View {
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

struct WatchSetSensorSummaryView: View {
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
                    "上げ \(concentric.formatted(.number.precision(.fractionLength(1))))秒・下げ \(eccentric.formatted(.number.precision(.fractionLength(1))))秒",
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
        .foregroundStyle(WatchAppTheme.mutedInk)
    }
}

enum WatchSetEditor: String, Identifiable {
    case weight
    case reps
    case rpe
    case tempo

    var id: String { rawValue }
}
