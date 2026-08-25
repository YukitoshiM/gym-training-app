import SwiftUI

struct WatchOutdoorWorkoutSetupView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var activity: OutdoorCardioActivity = .running
    @State private var goalKind: OutdoorCardioGoalKind = .distance
    @State private var distanceKilometers = 5.0
    @State private var durationMinutes = 30
    @State private var paceSeconds = 360

    var body: some View {
        List {
            Picker(L10n.string("watch_widget.outdoor_activity", fallback: "種類"), selection: $activity) {
                ForEach(OutdoorCardioActivity.allCases, id: \.self) { value in
                    Label(activityName(value), systemImage: activityIcon(value)).tag(value)
                }
            }

            Picker(L10n.string("watch_widget.outdoor_goal", fallback: "目標"), selection: $goalKind) {
                Text(L10n.string("watch_widget.outdoor_open", fallback: "自由")).tag(OutdoorCardioGoalKind.open)
                Text(L10n.string("watch_widget.outdoor_distance", fallback: "距離")).tag(OutdoorCardioGoalKind.distance)
                Text(L10n.string("watch_widget.outdoor_duration", fallback: "時間")).tag(OutdoorCardioGoalKind.duration)
            }

            if goalKind == .distance {
                Picker(L10n.string("watch_widget.outdoor_distance", fallback: "距離"), selection: $distanceKilometers) {
                    ForEach(Array(stride(from: 0.5, through: 50.0, by: 0.5)), id: \.self) { value in
                        Text("\(value.formatted(.number.precision(.fractionLength(1)))) km").tag(value)
                    }
                }
            } else if goalKind == .duration {
                Picker(L10n.string("watch_widget.outdoor_duration", fallback: "時間"), selection: $durationMinutes) {
                    ForEach(Array(stride(from: 5, through: 180, by: 5)), id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
            }

            Picker(L10n.string("watch_widget.outdoor_target_pace", fallback: "目標ペース"), selection: $paceSeconds) {
                ForEach(Array(stride(from: 180, through: 900, by: 15)), id: \.self) { value in
                    Text(pace(value)).tag(value)
                }
            }

            Button {
                workoutStore.startOutdoorWorkout(activity: activity, target: target)
                dismiss()
            } label: {
                Label(L10n.string("watch_widget.73efe52b65c2", fallback: "開始"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("watchStartOutdoorWorkoutButton")

            Text(L10n.string("watch_widget.outdoor_route_privacy", fallback: "ルートはApple Healthに保存され、AIや広告には送信されません。"))
                .font(.caption2)
                .foregroundStyle(WatchAppTheme.mutedInk)
        }
        .navigationTitle(L10n.string("watch_widget.outdoor", fallback: "屋外有酸素"))
    }

    private var target: OutdoorCardioTarget {
        OutdoorCardioTarget(
            kind: goalKind,
            distanceKilometers: goalKind == .distance ? distanceKilometers : nil,
            durationSeconds: goalKind == .duration ? Double(durationMinutes * 60) : nil,
            targetPaceSecondsPerKilometer: Double(paceSeconds)
        )
    }
}

struct WatchOutdoorActiveView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    let session: WatchWorkoutSessionSnapshot
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label(activityName(cardio.activity), systemImage: activityIcon(cardio.activity))
                    .font(.headline)

                Text(distanceText)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("watchOutdoorDistance")

                HStack {
                    metric(L10n.string("watch_widget.outdoor_duration", fallback: "時間"), elapsedText)
                    metric(L10n.string("watch_widget.outdoor_pace", fallback: "ペース"), paceText)
                }

                if let progress = cardio.progress(elapsedSeconds: workoutStore.liveMetrics.elapsedSeconds) {
                    ProgressView(value: progress)
                        .tint(WatchAppTheme.positive)
                    Text("\(Int(progress * 100))%")
                        .font(.caption.bold().monospacedDigit())
                }

                if let heartRate = workoutStore.liveMetrics.currentHeartRate {
                    Label("\(Int(heartRate)) bpm", systemImage: "heart.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WatchAppTheme.positive)
                }

                Button {
                    workoutStore.isWorkoutPaused ? workoutStore.resumeWorkout() : workoutStore.pauseWorkout()
                } label: {
                    Label(
                        workoutStore.isWorkoutPaused
                            ? L10n.string("watch_widget.0c6172650d06", fallback: "再開")
                            : L10n.string("watch_widget.68283c0be6f6", fallback: "一時停止"),
                        systemImage: workoutStore.isWorkoutPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button(role: .destructive) { isConfirmingCancel = true } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("watch_widget.49e3394121fb", fallback: "破棄"))

                    Button { isConfirmingFinish = true } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(L10n.string("watch_widget.5a4fab46f0a5", fallback: "完了してiPhoneへ送信"))
                }
            }
            .padding(.horizontal, 8)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            workoutStore.updateLiveElapsed()
        }
        .confirmationDialog(L10n.string("watch_widget.outdoor_finish_confirm", fallback: "屋外運動を完了しますか？"), isPresented: $isConfirmingFinish) {
            Button(L10n.string("watch_widget.5a4fab46f0a5", fallback: "完了してiPhoneへ送信")) {
                workoutStore.finishWorkout()
            }
        }
        .confirmationDialog(L10n.string("watch_widget.a9bcd1d54574", fallback: "記録を破棄しますか？"), isPresented: $isConfirmingCancel) {
            Button(L10n.string("watch_widget.49e3394121fb", fallback: "破棄"), role: .destructive) {
                workoutStore.cancelWorkout()
            }
        }
    }

    private var cardio: OutdoorCardioSnapshot {
        let currentDistance = workoutStore.liveMetrics.distanceKilometers ?? session.outdoorCardio?.distanceKilometers ?? 0
        return (session.outdoorCardio ?? OutdoorCardioSnapshot(activity: .running)).updating(
            distanceKilometers: currentDistance,
            elapsedSeconds: workoutStore.liveMetrics.elapsedSeconds
        )
    }

    private var distanceText: String {
        "\(cardio.distanceKilometers.formatted(.number.precision(.fractionLength(2)))) km"
    }

    private var elapsedText: String {
        let total = Int(max(0, workoutStore.liveMetrics.elapsedSeconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var paceText: String {
        guard let value = cardio.averagePaceSecondsPerKilometer else { return "--:--" }
        return pace(Int(value))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(WatchAppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private func activityName(_ activity: OutdoorCardioActivity) -> String {
    switch activity {
    case .running: L10n.string("watch_widget.outdoor_running_short", fallback: "ランニング")
    case .walking: L10n.string("watch_widget.outdoor_walking_short", fallback: "ウォーキング")
    case .cycling: L10n.string("watch_widget.outdoor_cycling_short", fallback: "サイクリング")
    }
}

private func activityIcon(_ activity: OutdoorCardioActivity) -> String {
    switch activity {
    case .running: "figure.run"
    case .walking: "figure.walk"
    case .cycling: "bicycle"
    }
}

private func pace(_ seconds: Int) -> String {
    let safe = max(0, seconds)
    return String(format: "%d:%02d /km", safe / 60, safe % 60)
}
