import SwiftUI

struct HistoryDetailView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isShowingEditor = false

    let session: WorkoutSession

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var currentSession: WorkoutSession {
        appStore.workoutHistory.first { $0.id == session.id } ?? session
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentSession.title)
                        .font(.title2.bold())

                    Text(AppFormatters.shortDateTime.string(from: currentSession.startedAt))
                        .foregroundStyle(AppTheme.mutedInk)

                    if currentSession.sourceDevice == .appleWatch {
                        Label("Apple Watchから同期", systemImage: "applewatch")
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.accent)
                    }

                    if let note = currentSession.note, !note.isEmpty {
                        Label(note, systemImage: "note.text")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LazyVGrid(columns: summaryColumns, spacing: 12) {
                    SummaryMetric(title: "達成率", value: AppFormatters.percent(currentSession.achievementRate))
                    SummaryMetric(title: "計画セット", value: "\(currentSession.completedPlannedSetCount)/\(currentSession.plannedSetCount)")
                    SummaryMetric(title: "総ボリューム", value: AppFormatters.volume(currentSession.totalVolume, unit: appStore.userProfile.weightUnit))
                    SummaryMetric(title: "目標差", value: AppFormatters.signedVolume(currentSession.volumeDelta, unit: appStore.userProfile.weightUnit))
                }
                .padding(.vertical, 8)
                .accessibilityIdentifier("historyPlanDeltaSummary")
            }

            if let sensorSummary = currentSession.sensorSummary {
                Section("Apple Watch計測") {
                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                        SummaryMetric(title: "時間", value: formatSetDuration(sensorSummary.durationSeconds))
                        SummaryMetric(title: "消費", value: sensorSummary.activeEnergyKilocalories.map { "\(Int($0)) kcal" } ?? "未取得")
                        SummaryMetric(title: "平均心拍", value: sensorSummary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "未取得")
                        SummaryMetric(title: "最大心拍", value: sensorSummary.maximumHeartRate.map { "\(Int($0)) bpm" } ?? "未取得")
                    }
                    .padding(.vertical, 8)

                    if let estimatedReps = sensorSummary.estimatedReps {
                        Label("動作推定 合計\(estimatedReps)回", systemImage: "sensor.tag.radiowaves.forward")
                    }

                    Label(healthSaveTitle, systemImage: healthSaveSystemImage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            ForEach(currentSession.exercises) { exercise in
                Section {
                    if exercise.isSkipped {
                        Label("スキップ", systemImage: "forward.end")
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        ForEach(exercise.sets) { set in
                            HistorySetRow(
                                set: set,
                                exercise: exercise.exercise,
                                bodyWeight: appStore.bodyWeight(on: currentSession.startedAt)
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text(exercise.exercise.name)
                        Spacer()
                        Text(exercise.isSkipped ? "スキップ" : "\(exercise.completedPlannedSetCount)/\(exercise.plannedSetCount)セット \(AppFormatters.percent(exercise.achievementRate))")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("履歴を編集")

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("履歴を削除")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            HistoryEditView(session: currentSession)
        }
        .confirmationDialog("この履歴を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                appStore.deleteWorkout(currentSession)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var healthSaveTitle: String {
        switch currentSession.healthWorkoutSaveState {
        case .saved: "Apple Healthへ保存済み"
        case .permissionDenied: "Health未許可・アプリ履歴のみ保存"
        case .failed: "Health保存失敗・アプリ履歴は保存済み"
        case .unavailable: "アプリ履歴のみ保存"
        case .collecting: "Health保存状態を確認中"
        case nil: "Health保存情報なし"
        }
    }

    private var healthSaveSystemImage: String {
        currentSession.healthWorkoutSaveState == .saved ? "heart.fill" : "heart.slash"
    }
}

private struct HistorySetRow: View {
    @EnvironmentObject private var appStore: AppStore

    let set: WorkoutSet
    let exercise: Exercise
    let bodyWeight: Double?

    private var resultText: String {
        if !set.isCompleted {
            return "未完了"
        }

        return set.isAchieved ? "達成" : "未達"
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
        HStack {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(set.isAchieved ? AppTheme.positive.opacity(0.18) : AppTheme.ink.opacity(0.09), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("実績 \(AppFormatters.weight(set.actualWeight, unit: appStore.userProfile.weightUnit)) × \(set.actualReps)回")
                    .font(.headline)

                Text("目標 \(AppFormatters.weight(set.targetWeight, unit: appStore.userProfile.weightUnit)) × \(set.targetReps)回")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                if let tempo = set.tempoPerformance {
                    Label(tempoOutcomeText(tempo), systemImage: "metronome")
                        .font(.footnote.bold())
                        .foregroundStyle(tempo.achievement == .onTarget ? AppTheme.positive : AppTheme.mutedInk)
                        .accessibilityIdentifier("historyTempoOutcome-\(set.setOrder)")
                } else if let up = set.plannedConcentricSeconds,
                          let down = set.plannedEccentricSeconds {
                    Label("テンポ計画 上げ\(up)秒・下げ\(down)秒", systemImage: "metronome")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .accessibilityIdentifier("historyPlannedTempo-\(set.setOrder)")
                }

                Text("重量差 \(AppFormatters.signedWeight(set.weightDelta, unit: appStore.userProfile.weightUnit)) / 回数差 \(AppFormatters.signedReps(set.repsDelta))")
                    .font(.footnote.bold())
                    .foregroundStyle(statusTint)
                    .accessibilityIdentifier("historySetDelta-\(set.setOrder)")

                if let rpe = set.rpe {
                    Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("historySetRPE-\(set.setOrder)")
                }

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
                    .accessibilityIdentifier("historyDipLoadSummary-\(set.setOrder)")
                }

                if let duration = set.duration {
                    Text("セット時間 \(formatSetDuration(duration))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                if let sensorSummary = set.sensorSummary {
                    HStack(spacing: 8) {
                        if let averageHeartRate = sensorSummary.averageHeartRate {
                            Label("\(Int(averageHeartRate)) bpm", systemImage: "heart.fill")
                        }
                        if let estimatedReps = sensorSummary.estimatedReps {
                            Label("推定\(estimatedReps)回", systemImage: "waveform.path")
                        }
                        if let consistency = sensorSummary.movementConsistency {
                            Label("安定\(Int(consistency * 100))%", systemImage: "checkmark.circle")
                    }

                    if let up = sensorSummary.averageConcentricDuration,
                       let down = sensorSummary.averageEccentricDuration {
                        Label(
                            "実測テンポ 上げ\(up.formatted(.number.precision(.fractionLength(1))))秒・下げ\(down.formatted(.number.precision(.fractionLength(1))))秒",
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .accessibilityIdentifier("historyObservedTempo-\(set.setOrder)")
                    }
                }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                }
            }

            Spacer()

            Text(resultText)
                .font(.subheadline.bold())
                .foregroundStyle(statusTint)
        }
        .padding(.vertical, 4)
    }
}

private func formatSetDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60

    if minutes == 0 {
        return "\(seconds)秒"
    }

    return "\(minutes)分\(seconds)秒"
}

private func tempoOutcomeText(_ performance: TempoPerformance) -> String {
    let outcome: String
    switch performance.achievement {
    case .onTarget:
        outcome = "計画どおり"
    case .faster:
        outcome = "計画より速め"
    case .slower:
        outcome = "計画よりゆっくり"
    case .mixed:
        outcome = "上下で差あり"
    }

    let up = String(format: "%+.1f", performance.concentricDifferenceSeconds)
    let down = String(format: "%+.1f", performance.eccentricDifferenceSeconds)
    let corrected = performance.wasManuallyCorrected ? "・補正済み" : ""
    return "\(outcome) 上げ\(up)秒 / 下げ\(down)秒\(corrected)"
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            session: WorkoutSession(plan: TrainingPlan(
                name: "胸の日",
                exercises: [
                    PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
                ]
            ))
        )
    }
    .environmentObject(AppStore())
}
