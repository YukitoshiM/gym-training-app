import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    var body: some View {
        NavigationStack {
            Group {
                if let activeSession = workoutStore.activeSession {
                    WatchActiveWorkoutView(session: activeSession)
                } else if let plan = workoutStore.plan {
                    WatchPlanDetailView(
                        plan: plan,
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

            Text("計画待ち")
                .font(.headline)

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("iPhoneの記録タブからApple Watchへ送信します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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

                    ProgressView(
                        value: Double(session.completedSetCount),
                        total: Double(max(session.totalSetCount, 1))
                    )
                    .tint(.green)
                }
            }

            if workoutStore.isRestTimerRunning {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("休憩 \(formatDuration(workoutStore.restRemaining))", systemImage: "timer")
                                .font(.headline)

                            Spacer()

                            Button {
                                workoutStore.stopRestTimer()
                            } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            .accessibilityLabel("休憩をスキップ")
                        }

                        HStack(spacing: 8) {
                            Button("-15秒") {
                                workoutStore.adjustRestTimer(by: -15)
                            }

                            Button("+30秒") {
                                workoutStore.adjustRestTimer(by: 30)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .accessibilityIdentifier("watchRestTimer")
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
}

private struct WatchSetControlRow: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

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
                } else {
                    actualValueControls

                    HStack {
                        NavigationLink {
                            WatchRPESelectionView(exerciseID: exercise.id, setID: set.id, currentRPE: set.rpe)
                        } label: {
                            Label(rpeTitle, systemImage: "gauge")
                        }
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
    }

    private var actualValueControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("重量")
                    .frame(width: 32, alignment: .leading)

                Button {
                    workoutStore.adjustWeight(exerciseID: exercise.id, setID: set.id, delta: -2.5)
                } label: {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("重量を下げる")

                Text(formatWeight(set.actualWeight, unit: unit))
                    .frame(minWidth: 48)

                Button {
                    workoutStore.adjustWeight(exerciseID: exercise.id, setID: set.id, delta: 2.5)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("重量を上げる")
            }

            HStack {
                Text("回数")
                    .frame(width: 32, alignment: .leading)

                Button {
                    workoutStore.adjustReps(exerciseID: exercise.id, setID: set.id, delta: -1)
                } label: {
                    Image(systemName: "minus")
                }
                .accessibilityLabel("回数を下げる")

                Text("\(set.actualReps)回")
                    .frame(minWidth: 48)

                Button {
                    workoutStore.adjustReps(exerciseID: exercise.id, setID: set.id, delta: 1)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("回数を上げる")
                .accessibilityIdentifier("watchSetRepsPlus-\(exercise.sortOrder)-\(set.setOrder)")
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

private struct WatchRPESelectionView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID
    let currentRPE: Double?

    var body: some View {
        List {
            Button {
                workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: nil)
                dismiss()
            } label: {
                Label("なし", systemImage: currentRPE == nil ? "checkmark.circle.fill" : "circle")
            }
            .accessibilityIdentifier("watchRPE-none")

            ForEach(6...10, id: \.self) { value in
                Button {
                    workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: Double(value))
                    dismiss()
                } label: {
                    Label("RPE \(value)", systemImage: currentRPE == Double(value) ? "checkmark.circle.fill" : "circle")
                }
                .accessibilityIdentifier("watchRPE-\(value)")
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
