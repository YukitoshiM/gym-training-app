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
                        .foregroundStyle(.secondary)

                    if currentSession.sourceDevice == .appleWatch {
                        Label("Apple Watchから同期", systemImage: "applewatch")
                            .font(.caption.bold())
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(currentSession.exercises) { exercise in
                Section {
                    if exercise.isSkipped {
                        Label("スキップ", systemImage: "forward.end")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(exercise.sets) { set in
                            HistorySetRow(set: set)
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

    private var resultText: String {
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
        HStack {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(set.isAchieved ? Color.green.opacity(0.18) : Color(.secondarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("実績 \(AppFormatters.weight(set.actualWeight, unit: appStore.userProfile.weightUnit)) × \(set.actualReps)回")
                    .font(.headline)

                Text("目標 \(AppFormatters.weight(set.targetWeight, unit: appStore.userProfile.weightUnit)) × \(set.targetReps)回")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("重量差 \(AppFormatters.signedWeight(set.weightDelta, unit: appStore.userProfile.weightUnit)) / 回数差 \(AppFormatters.signedReps(set.repsDelta))")
                    .font(.caption.bold())
                    .foregroundStyle(statusTint)
                    .accessibilityIdentifier("historySetDelta-\(set.setOrder)")

                if let rpe = set.rpe {
                    Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("historySetRPE-\(set.setOrder)")
                }

                if let duration = set.duration {
                    Text("セット時間 \(formatSetDuration(duration))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
