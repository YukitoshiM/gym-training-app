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
                        Label(L10n.string("training.4a9b3adb6c14", fallback: "Apple Watchから同期"), systemImage: "applewatch")
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

            if let cardio = currentSession.outdoorCardio {
                Section(L10n.string("training.outdoor_summary", fallback: "屋外有酸素")) {
                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                        SummaryMetric(title: L10n.string("training.outdoor_distance", fallback: "距離"), value: AppFormatters.distance(kilometers: cardio.distanceKilometers))
                        SummaryMetric(title: L10n.string("training.137012e67a97", fallback: "時間"), value: formatSetDuration(currentSession.sensorSummary?.durationSeconds ?? currentSessionDuration))
                        SummaryMetric(title: L10n.string("training.outdoor_pace", fallback: "平均ペース"), value: cardio.averagePaceSecondsPerKilometer.map(AppFormatters.pace) ?? L10n.string("training.29d0d2b3bbd0", fallback: "未取得"))
                        SummaryMetric(title: L10n.string("training.e79acd05d832", fallback: "達成率"), value: cardio.progress(elapsedSeconds: currentSessionDuration).map(AppFormatters.percent) ?? "-")
                    }
                    .padding(.vertical, 8)

                    Label(
                        cardio.routeStoredInHealthKit
                            ? L10n.string("training.outdoor_route_health", fallback: "ルートはApple Healthに保存済み")
                            : L10n.string("training.outdoor_route_unavailable", fallback: "ルートは未取得"),
                        systemImage: cardio.routeStoredInHealthKit ? "map.fill" : "map"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                }
            } else {
                Section {
                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                        SummaryMetric(title: L10n.string("training.e79acd05d832", fallback: "達成率"), value: AppFormatters.percent(currentSession.achievementRate))
                        SummaryMetric(title: L10n.string("training.a85ababac45e", fallback: "計画セット"), value: "\(currentSession.completedPlannedSetCount)/\(currentSession.plannedSetCount)")
                        SummaryMetric(title: L10n.string("training.922870c3ac56", fallback: "総ボリューム"), value: AppFormatters.volume(currentSession.totalVolume, unit: appStore.userProfile.weightUnit))
                        SummaryMetric(title: L10n.string("training.f85857b6a867", fallback: "目標差"), value: AppFormatters.signedVolume(currentSession.volumeDelta, unit: appStore.userProfile.weightUnit))
                    }
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("historyPlanDeltaSummary")
                }
            }

            if let sensorSummary = currentSession.sensorSummary {
                Section(L10n.string("training.54ba864f9b13", fallback: "Apple Watch計測")) {
                    LazyVGrid(columns: summaryColumns, spacing: 12) {
                        SummaryMetric(title: L10n.string("training.137012e67a97", fallback: "時間"), value: formatSetDuration(sensorSummary.durationSeconds))
                        SummaryMetric(title: L10n.string("training.586036cfde65", fallback: "消費"), value: sensorSummary.activeEnergyKilocalories.map { "\(Int($0)) kcal" } ?? L10n.string("training.29d0d2b3bbd0", fallback: "未取得"))
                        SummaryMetric(title: L10n.string("training.116d7c49a7ee", fallback: "平均心拍"), value: sensorSummary.averageHeartRate.map { "\(Int($0)) bpm" } ?? L10n.string("training.29d0d2b3bbd0", fallback: "未取得"))
                        SummaryMetric(title: L10n.string("training.09b15b45b062", fallback: "最大心拍"), value: sensorSummary.maximumHeartRate.map { "\(Int($0)) bpm" } ?? L10n.string("training.29d0d2b3bbd0", fallback: "未取得"))
                    }
                    .padding(.vertical, 8)

                    if let estimatedReps = sensorSummary.estimatedReps {
                        Label(L10n.string("training.3d76a425a0b1", fallback: "動作推定 合計{{value1}}回", values: [String(describing: estimatedReps)]), systemImage: "sensor.tag.radiowaves.forward")
                    }

                    Label(healthSaveTitle, systemImage: healthSaveSystemImage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            ForEach(currentSession.exercises) { exercise in
                Section {
                    if exercise.isSkipped {
                        Label(L10n.string("training.17135f0f1ac6", fallback: "スキップ"), systemImage: "forward.end")
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
                        Text(exercise.isSkipped ? L10n.string("training.17135f0f1ac6", fallback: "スキップ") : L10n.string("training.efc343f41739", fallback: "{{value1}}/{{value2}}セット {{value3}}", values: [String(describing: exercise.completedPlannedSetCount), String(describing: exercise.plannedSetCount), String(describing: AppFormatters.percent(exercise.achievementRate))]))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("training.dfb4aa016e77", fallback: "履歴詳細"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(L10n.string("training.029dbfd15c77", fallback: "履歴を編集"))

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L10n.string("training.5e6ee388a66f", fallback: "履歴を削除"))
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            HistoryEditView(session: currentSession)
        }
        .confirmationDialog(L10n.string("training.5a03b277c63d", fallback: "この履歴を削除しますか？"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(L10n.string("training.ac806fcfe196", fallback: "削除"), role: .destructive) {
                appStore.deleteWorkout(currentSession)
                dismiss()
            }
            Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル"), role: .cancel) {}
        }
    }

    private var currentSessionDuration: TimeInterval {
        max(0, (currentSession.endedAt ?? Date()).timeIntervalSince(currentSession.startedAt))
    }

    private var healthSaveTitle: String {
        switch currentSession.healthWorkoutSaveState {
        case .saved: L10n.string("training.6427e2eb8c0c", fallback: "Apple Healthへ保存済み")
        case .permissionDenied: L10n.string("training.5f2538c97a2c", fallback: "Health未許可・アプリ履歴のみ保存")
        case .failed: L10n.string("training.e4bf5e7357de", fallback: "Health保存失敗・アプリ履歴は保存済み")
        case .unavailable: L10n.string("training.5472591c5dd4", fallback: "アプリ履歴のみ保存")
        case .collecting: L10n.string("training.93bdb35325e7", fallback: "Health保存状態を確認中")
        case nil: L10n.string("training.7a9ab7fdc8a1", fallback: "Health保存情報なし")
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
        HStack {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(set.isAchieved ? AppTheme.positive.opacity(0.18) : AppTheme.ink.opacity(0.09), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("training.cfbf8016ae16", fallback: "実績 {{value1}} × {{value2}}回", values: [String(describing: AppFormatters.weight(set.actualWeight, unit: appStore.userProfile.weightUnit)), String(describing: set.actualReps)]))
                    .font(.headline)

                Text(L10n.string("training.ad1d41e268ba", fallback: "目標 {{value1}} × {{value2}}回", values: [String(describing: AppFormatters.weight(set.targetWeight, unit: appStore.userProfile.weightUnit)), String(describing: set.targetReps)]))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                if let tempo = set.tempoPerformance {
                    Label(
                        tempoOutcomeText(tempo, beatSpeed: set.plannedTempoBeatSpeed),
                        systemImage: "metronome"
                    )
                        .font(.footnote.bold())
                        .foregroundStyle(tempo.achievement == .onTarget ? AppTheme.positive : AppTheme.mutedInk)
                        .accessibilityIdentifier("historyTempoOutcome-\(set.setOrder)")
                } else if let up = set.plannedConcentricSeconds,
                          let down = set.plannedEccentricSeconds {
                    let speed = min(3, max(1, set.plannedTempoBeatSpeed ?? 1))
                    Label(
                        L10n.string("training.6ac8a3e464be", fallback: "テンポ計画 上げ{{value1}}秒・下げ{{value2}}秒・{{value3}}回/秒", values: [String(describing: up), String(describing: down), String(describing: speed)]),
                        systemImage: "metronome"
                    )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .accessibilityIdentifier("historyPlannedTempo-\(set.setOrder)")
                }

                Text(L10n.string("training.e0f05832f7f0", fallback: "重量差 {{value1}} / 回数差 {{value2}}", values: [String(describing: AppFormatters.signedWeight(set.weightDelta, unit: appStore.userProfile.weightUnit)), String(describing: AppFormatters.signedReps(set.repsDelta))]))
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
                    Text(L10n.string("training.7556f1c352e7", fallback: "セット時間 {{value1}}", values: [String(describing: formatSetDuration(duration))]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                if let sensorSummary = set.sensorSummary {
                    HStack(spacing: 8) {
                        if let averageHeartRate = sensorSummary.averageHeartRate {
                            Label("\(Int(averageHeartRate)) bpm", systemImage: "heart.fill")
                        }
                        if let estimatedReps = sensorSummary.estimatedReps {
                            Label(L10n.string("training.86351613651a", fallback: "推定{{value1}}回", values: [String(describing: estimatedReps)]), systemImage: "waveform.path")
                        }
                        if let consistency = sensorSummary.movementConsistency {
                            Label(L10n.string("training.9f51331cdcae", fallback: "安定{{value1}}%", values: [String(describing: Int(consistency * 100))]), systemImage: "checkmark.circle")
                    }

                    if let up = sensorSummary.averageConcentricDuration,
                       let down = sensorSummary.averageEccentricDuration {
                        Label(
                            L10n.string("training.1150f3eb9a23", fallback: "実測テンポ 上げ{{value1}}秒・下げ{{value2}}秒", values: [String(describing: up.formatted(.number.precision(.fractionLength(1)))), String(describing: down.formatted(.number.precision(.fractionLength(1))))]),
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
        return L10n.string("training.7a2a62b34f78", fallback: "{{value1}}秒", values: [String(describing: seconds)])
    }

    return L10n.string("training.2caf706359d6", fallback: "{{value1}}分{{value2}}秒", values: [String(describing: minutes), String(describing: seconds)])
}

private func tempoOutcomeText(_ performance: TempoPerformance, beatSpeed: Int?) -> String {
    let outcome: String
    switch performance.achievement {
    case .onTarget:
        outcome = L10n.string("training.84f4ceb9bc7b", fallback: "計画どおり")
    case .faster:
        outcome = L10n.string("training.742f77fb799f", fallback: "計画より速め")
    case .slower:
        outcome = L10n.string("training.1823e96b3cdc", fallback: "計画よりゆっくり")
    case .mixed:
        outcome = L10n.string("training.d3dc45699b72", fallback: "上下で差あり")
    }

    let up = String(format: "%+.1f", performance.concentricDifferenceSeconds)
    let down = String(format: "%+.1f", performance.eccentricDifferenceSeconds)
    let speed = min(3, max(1, beatSpeed ?? 1))
    let corrected = performance.wasManuallyCorrected ? L10n.string("training.b29f639d55b9", fallback: "・補正済み") : ""
    return L10n.string("training.dcd2a5e619a3", fallback: "{{value1}} 上げ{{value2}}秒 / 下げ{{value3}}秒・{{value4}}回/秒{{value5}}", values: [String(describing: outcome), String(describing: up), String(describing: down), String(describing: speed), String(describing: corrected)])
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            session: WorkoutSession(plan: TrainingPlan(
                name: L10n.string("training.d30ca9b91ccb", fallback: "胸の日"),
                exercises: [
                    PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
                ]
            ))
        )
    }
    .environmentObject(AppStore())
}
