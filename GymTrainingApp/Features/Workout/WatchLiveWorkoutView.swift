import SwiftUI

struct WatchLiveWorkoutCard: View {
    let snapshot: WatchLiveWorkoutSnapshot

    var body: some View {
        NavigationLink {
            WatchLiveWorkoutView()
        } label: {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "applewatch.radiowaves.left.and.right", tint: AppTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.string("training.148b91e44188", fallback: "WATCHで記録中"))
                                .font(.footnote.bold())
                                .foregroundStyle(AppTheme.accent)
                            Text(snapshot.session.title)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                        }

                        Spacer()

                        Text("\(snapshot.session.completedSetCount)/\(snapshot.session.totalSetCount)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(AppTheme.ink)
                    }

                    ProgressView(
                        value: Double(snapshot.session.completedSetCount),
                        total: Double(max(1, snapshot.session.totalSetCount))
                    )
                    .tint(AppTheme.accent)

                    HStack(spacing: 14) {
                        Label(formatDuration(snapshot.liveMetrics.elapsedSeconds), systemImage: "clock")
                        if let heartRate = snapshot.liveMetrics.currentHeartRate {
                            Label("\(Int(heartRate.rounded())) bpm", systemImage: "heart.fill")
                        }
                        if snapshot.isRestTimerRunning {
                            Label(formatDuration(Double(snapshot.restRemaining)), systemImage: "timer")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchLiveWorkoutCard")
    }
}

struct WatchLiveWorkoutView: View {
    @EnvironmentObject private var watchSyncService: WatchPlanSyncService
    @State private var editor: LiveSetEditor?
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false

    var body: some View {
        Group {
            if let snapshot = watchSyncService.liveWatchWorkout {
                List {
                    Section {
                        LiveWorkoutSummary(snapshot: snapshot)
                    }

                    ForEach(snapshot.session.exercises.sorted { $0.sortOrder < $1.sortOrder }) { exercise in
                        Section {
                            ForEach(exercise.sets.sorted { $0.setOrder < $1.setOrder }) { set in
                                LiveSetRow(
                                    exercise: exercise,
                                    set: set,
                                    unit: snapshot.session.weightUnit,
                                    onEdit: {
                                        editor = LiveSetEditor(
                                            exercise: exercise,
                                            set: set,
                                            unit: snapshot.session.weightUnit
                                        )
                                    },
                                    onCommand: watchSyncService.send(command:)
                                )
                            }

                            if snapshot.isRestTimerRunning,
                               snapshot.restExerciseID == exercise.id {
                                HStack {
                                    Label(
                                        L10n.string("training.a0b0ff58b87b", fallback: "休憩 {{value1}}", values: [String(describing: formatDuration(Double(snapshot.restRemaining)))]),
                                        systemImage: "timer"
                                    )
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(AppTheme.accent)
                                    Spacer()
                                    Button(L10n.string("training.fd89f4db4ef1", fallback: "終了")) {
                                        watchSyncService.send(command: WatchWorkoutCommand(action: .stopRestTimer))
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .accessibilityIdentifier("liveRestTimer-\(exercise.id)")
                            }
                } header: {
                    Text(exercise.name)
                } footer: {
                    Text(L10n.string("training.1c33183e078a", fallback: "{{value1}}/{{value2}}セット完了", values: [String(describing: exercise.completedSetCount), String(describing: exercise.sets.count)]))
                }
                    }

                    Section {
                        Button {
                            isConfirmingFinish = true
                        } label: {
                            Label(L10n.string("training.3a77d7bcf1a1", fallback: "トレーニングを完了"), systemImage: "checkmark.circle.fill")
                        }
                        .foregroundStyle(AppTheme.positive)

                        Button(role: .destructive) {
                            isConfirmingCancel = true
                        } label: {
                            Label(L10n.string("training.be6165c4a524", fallback: "記録を破棄"), systemImage: "xmark.circle")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(TrainingBackground())
                .sheet(item: $editor) { editor in
                    LiveSetEditorView(editor: editor)
                }
                .confirmationDialog(
                    L10n.string("training.3e098891145f", fallback: "Watchのトレーニングを完了しますか？"),
                    isPresented: $isConfirmingFinish,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("training.45a16902aa22", fallback: "完了して履歴へ保存")) {
                        watchSyncService.send(command: WatchWorkoutCommand(action: .finishWorkout))
                    }
                    Button(L10n.string("training.ab9657692a70", fallback: "続ける"), role: .cancel) {}
                }
                .confirmationDialog(
                    L10n.string("training.f1fc156b78fb", fallback: "Watchの記録を破棄しますか？"),
                    isPresented: $isConfirmingCancel,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("training.804773e6316f", fallback: "破棄"), role: .destructive) {
                        watchSyncService.send(command: WatchWorkoutCommand(action: .cancelWorkout))
                    }
                    Button(L10n.string("training.ab9657692a70", fallback: "続ける"), role: .cancel) {}
                }
            } else {
                ContentUnavailableView(
                    L10n.string("training.1815a117bafa", fallback: "Watchの記録は終了しました"),
                    systemImage: "applewatch",
                    description: Text(L10n.string("training.e3290760a2fd", fallback: "完了した記録は履歴から確認できます。"))
                )
            }
        }
        .navigationTitle(L10n.string("training.e9af98302821", fallback: "Watchライブ"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LiveWorkoutSummary: View {
    let snapshot: WatchLiveWorkoutSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.session.title)
                .font(.title3.bold())

            HStack(spacing: 16) {
                summaryValue(
                    title: L10n.string("training.b7bac668058e", fallback: "経過"),
                    value: formatDuration(snapshot.liveMetrics.elapsedSeconds),
                    image: "clock"
                )
                summaryValue(
                    title: L10n.string("training.a667d8bcf664", fallback: "セット"),
                    value: "\(snapshot.session.completedSetCount)/\(snapshot.session.totalSetCount)",
                    image: "checkmark.circle"
                )
                if let heartRate = snapshot.liveMetrics.currentHeartRate {
                    summaryValue(title: L10n.string("training.1b75451060ca", fallback: "心拍"), value: "\(Int(heartRate.rounded()))", image: "heart.fill")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryValue(title: String, value: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: image)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            Text(value)
                .font(.headline.monospacedDigit())
        }
    }
}

private struct LiveSetRow: View {
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot
    let unit: WatchWeightUnit
    let onEdit: () -> Void
    let onCommand: (WatchWorkoutCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SET \(set.setOrder)")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
                Spacer()
                Text(status)
                    .font(.footnote.bold())
                    .foregroundStyle(statusTint)
            }

            HStack {
                Text(L10n.string("training.9fcc2f46457a", fallback: "{{value1}} {{value2}} × {{value3}}回", values: [String(describing: formatWeight(set.actualWeight, unit: unit)), String(describing: unit.displayName), String(describing: set.actualReps)]))
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("liveSetActual-\(exercise.sortOrder)-\(set.setOrder)")
                Spacer()
                if set.startedAt != nil, !set.isCompleted {
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.string("training.cda9a6386691", fallback: "実績値を編集"))
                }
            }

            if !set.isCompleted {
                HStack {
                    if set.startedAt == nil {
                        Button {
                            onCommand(
                                WatchWorkoutCommand(
                                    action: .startSet,
                                    exerciseID: exercise.id,
                                    setID: set.id
                                )
                            )
                        } label: {
                            Label(L10n.string("training.92f3acd01a38", fallback: "開始"), systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(role: .destructive) {
                            onCommand(
                                WatchWorkoutCommand(
                                    action: .cancelSet,
                                    exerciseID: exercise.id,
                                    setID: set.id
                                )
                            )
                        } label: {
                            Label(L10n.string("training.b9a458e7a4a8", fallback: "開始取消"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            onCommand(
                                WatchWorkoutCommand(
                                    action: .completeSet,
                                    exerciseID: exercise.id,
                                    setID: set.id
                                )
                            )
                        } label: {
                            Label(L10n.string("training.4dce1b477edb", fallback: "完了"), systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                    .font(.footnote)

                    if let concentric = set.plannedConcentricSeconds,
                       let eccentric = set.plannedEccentricSeconds,
                       let beatSpeed = set.plannedTempoBeatSpeed {
                        Text(L10n.string("training.5299c5bbedaa", fallback: "上げ{{value1}}秒・下げ{{value2}}秒・{{value3}}回/秒", values: [String(describing: concentric), String(describing: eccentric), String(describing: beatSpeed)]))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("liveSet-\(exercise.sortOrder)-\(set.setOrder)")
    }

    private var status: String {
        if set.isCompleted { return L10n.string("training.4dce1b477edb", fallback: "完了") }
        if set.startedAt != nil { return L10n.string("training.1784283f2316", fallback: "実施中") }
        return L10n.string("training.5c4f3b18a99c", fallback: "待機")
    }

    private var statusTint: Color {
        if set.isCompleted { return AppTheme.positive }
        if set.startedAt != nil { return AppTheme.accent }
        return AppTheme.mutedInk
    }

    private func formatWeight(_ kilograms: Double, unit: WatchWeightUnit) -> String {
        let displayValue = unit == .kg ? kilograms : kilograms * 2.2046226218
        return displayValue.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct LiveSetEditor: Identifiable {
    let id = UUID()
    let exercise: WatchWorkoutExerciseSnapshot
    let set: WatchWorkoutSetSnapshot
    let unit: WatchWeightUnit
}

private struct LiveSetEditorView: View {
    @EnvironmentObject private var watchSyncService: WatchPlanSyncService
    @Environment(\.dismiss) private var dismiss
    let editor: LiveSetEditor

    @State private var weight: Double
    @State private var reps: Int
    @State private var rpeText: String
    @State private var concentricSeconds: Int
    @State private var eccentricSeconds: Int
    @State private var beatSpeed: Int

    init(editor: LiveSetEditor) {
        self.editor = editor
        _weight = State(initialValue: editor.set.actualWeight)
        _reps = State(initialValue: editor.set.actualReps)
        _rpeText = State(initialValue: editor.set.rpe.map {
            $0.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "8")
        _concentricSeconds = State(initialValue: max(1, min(10, editor.set.plannedConcentricSeconds ?? 2)))
        _eccentricSeconds = State(initialValue: max(1, min(10, editor.set.plannedEccentricSeconds ?? 3)))
        _beatSpeed = State(initialValue: max(1, min(3, editor.set.plannedTempoBeatSpeed ?? 1)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(editor.exercise.name) {
                    WeightInputControl(
                        weightInKilograms: $weight,
                        unit: editor.unit == .kg ? .kg : .lb,
                        kilogramRange: editor.exercise.supportsAssistedLoad
                            ? AssistedLoadSupport.kilogramRange
                            : 0...999,
                        accessibilityIdentifier: "liveSetWeight"
                    )
                    RepsInputControl(reps: $reps, accessibilityIdentifier: "liveSetReps")
                    NumericTextInputControl(
                        text: $rpeText,
                        title: "RPE",
                        unit: "",
                        range: 1...10,
                        step: 0.5,
                        defaultValue: 8,
                        accessibilityIdentifier: "liveSetRPE"
                    )

                    Picker(L10n.string("training.3bf410eec240", fallback: "上げ秒"), selection: $concentricSeconds) {
                        ForEach(1...10, id: \.self) { value in
                            Text(L10n.string("training.7a2a62b34f78", fallback: "{{value1}}秒", values: [value.formatted()])).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(L10n.string("training.6350c70cf355", fallback: "下げ秒"), selection: $eccentricSeconds) {
                        ForEach(1...10, id: \.self) { value in
                            Text(L10n.string("training.7a2a62b34f78", fallback: "{{value1}}秒", values: [value.formatted()])).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(L10n.string("training.6532391678cf", fallback: "振動速度"), selection: $beatSpeed) {
                        ForEach(1...3, id: \.self) { value in
                            Text(L10n.string("training.4d980bac73d4", fallback: "{{value1}}回/秒", values: [String(describing: value)])).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle(L10n.string("training.45231573ad1d", fallback: "セット実績"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("training.e1472f598358", fallback: "反映")) {
                        watchSyncService.send(
                            command: WatchWorkoutCommand(
                                action: .updateSet,
                                exerciseID: editor.exercise.id,
                                setID: editor.set.id,
                                actualWeight: weight,
                                actualReps: reps,
                                rpe: Double(rpeText.replacingOccurrences(of: ",", with: ".")),
                                plannedConcentricSeconds: concentricSeconds,
                                plannedEccentricSeconds: eccentricSeconds,
                                plannedTempoBeatSpeed: beatSpeed
                            )
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", total / 60, total % 60)
}
