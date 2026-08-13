import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WatchTutorialView.completedVersionKey) private var completedTutorialVersion = ""
    @State private var isShowingTutorial = false

    var body: some View {
        NavigationStack {
            Group {
                if let activeSession = workoutStore.activeSession {
                    WatchActiveWorkoutView()
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
            .navigationTitle("BodyMode")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingTutorial = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Apple Watchの使い方")
                    .accessibilityIdentifier("watchTutorialHelpButton")
                }
            }
        }
        .sheet(isPresented: $isShowingTutorial) {
            WatchTutorialView {
                markTutorialHandled()
            }
        }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--show-watch-tutorial") {
                completedTutorialVersion = ""
                isShowingTutorial = true
            } else if !arguments.contains("--seed-watch-ui-test-plan"),
                      completedTutorialVersion != WatchTutorialView.currentVersion {
                isShowingTutorial = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            WatchDiagnostics.shared.record(
                category: "lifecycle",
                message: "Watch app left foreground",
                metadata: ["phase": String(describing: newPhase)]
            )
            workoutStore.flushDiagnostics()
        }
    }

    private func markTutorialHandled() {
        let version = WatchTutorialView.currentVersion
        UserDefaults.standard.set(version, forKey: WatchTutorialView.completedVersionKey)
        completedTutorialVersion = version
        isShowingTutorial = false
    }
}

struct WatchTutorialView: View {
    static let currentVersion = "2"
    static let completedVersionKey = "watchTutorialCompletedVersion"

    let onComplete: () -> Void
    @State private var page = 0

    private let steps = [
        WatchTutorialStep(
            icon: "list.bullet.rectangle",
            title: "メニューを選ぶ",
            detail: "iPhoneから届いた今日のメニューを選び、開始します。"
        ),
        WatchTutorialStep(
            icon: "play.fill",
            title: "セットを開始",
            detail: "種目とセットを選んで開始。間違えた時は取消で未実行に戻せます。"
        ),
        WatchTutorialStep(
            icon: "dial.medium",
            title: "実績を合わせる",
            detail: "重量・回数・RPEは完了前にリールで変更できます。"
        ),
        WatchTutorialStep(
            icon: "metronome",
            title: "テンポを合わせる",
            detail: "計画に動作時間があるセットは、上げ下げを1秒ごとの触覚で案内します。"
        ),
        WatchTutorialStep(
            icon: "timer",
            title: "休憩する",
            detail: "完了すると休憩タイマーが開始。次の種目は順番を変えて選べます。"
        ),
        WatchTutorialStep(
            icon: "iphone.and.arrow.forward",
            title: "終了して同期",
            detail: "最後に終了するとiPhoneへ送信。未送信の記録はあとから再送できます。"
        )
    ]

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 2)

            Image(systemName: steps[page].icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(WatchAppTheme.positive)
                .frame(height: 42)

            Text(steps[page].title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("watchTutorialPage-\(page + 1)")

            Text(steps[page].detail)
                .font(.caption)
                .foregroundStyle(WatchAppTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? WatchAppTheme.positive : WatchAppTheme.mutedInk.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                Button("スキップ", action: onComplete)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("チュートリアルをスキップ")
                    .accessibilityIdentifier("skipWatchTutorialButton")

                Button {
                    if page == steps.count - 1 {
                        onComplete()
                    } else {
                        page += 1
                    }
                } label: {
                    Label(page == steps.count - 1 ? "使い始める" : "次へ", systemImage: page == steps.count - 1 ? "checkmark" : "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(page == steps.count - 1 ? "completeWatchTutorialButton" : "nextWatchTutorialButton")
            }
            .font(.footnote)
        }
        .padding(.horizontal, 10)
        .navigationTitle("使い方 \(page + 1)/\(steps.count)")
    }
}

private struct WatchTutorialStep {
    let icon: String
    let title: String
    let detail: String
}

struct WatchEmptyPlanView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    let statusMessage: String

    var body: some View {
        VStack(spacing: 10) {
            if let recommendation = workoutStore.dailyRecommendation {
                HStack {
                    Text(recommendation.readiness)
                        .font(.headline)
                        .foregroundStyle(WatchAppTheme.positive)
                    Spacer()
                    Text("\(recommendation.actions.filter(\.isCompleted).count)/\(recommendation.actions.count)")
                        .font(.caption.monospacedDigit())
                }
                ForEach(recommendation.actions.prefix(3)) { action in
                    Label(action.title, systemImage: action.isCompleted ? "checkmark.circle.fill" : action.systemImage)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Image(systemName: "applewatch")
                    .font(.largeTitle)
                    .foregroundStyle(WatchAppTheme.positive)

                Text("メニュー待ち")
                    .font(.headline)
            }

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(WatchAppTheme.mutedInk)
                .multilineTextAlignment(.center)

            Text("iPhoneのホームから今日の内容を同期します。")
                .font(.caption2)
                .foregroundStyle(WatchAppTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct WatchMenuSelectionView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    let plans: [WatchWorkoutPlanSnapshot]
    let statusMessage: String
    let pendingSession: WatchWorkoutSessionSnapshot?

    var body: some View {
        List {
            if let recommendation = workoutStore.dailyRecommendation {
                WatchDailyRecommendationSection(recommendation: recommendation, showsStart: true)
            }

            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日のメニュー")
                        .font(.headline)
                    Text("\(plans.count)件から選択")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }
            }

            if let lastCompletedSession = workoutStore.lastCompletedSession {
                WatchRecentSessionSection(session: lastCompletedSession)
            }

            Section("メニュー") {
                ForEach(plans) { plan in
                    Button {
                        workoutStore.selectPlan(plan)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(WatchAppTheme.positive)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.name)
                                    .font(.headline)
                                    .foregroundStyle(WatchAppTheme.ink)
                                    .lineLimit(1)
                                Text(planOverview(plan))
                                    .font(.caption2)
                                    .foregroundStyle(WatchAppTheme.mutedInk)
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

struct WatchPlanDetailView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore

    let plan: WatchWorkoutPlanSnapshot
    let statusMessage: String
    let pendingSession: WatchWorkoutSessionSnapshot?

    var body: some View {
        List {
            if let recommendation = workoutStore.dailyRecommendation {
                WatchDailyRecommendationSection(recommendation: recommendation, showsStart: false)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                    Text(planOverview(plan))
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.mutedInk)
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

            if let lastCompletedSession = workoutStore.lastCompletedSession {
                WatchRecentSessionSection(session: lastCompletedSession)
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
                            .foregroundStyle(WatchAppTheme.mutedInk)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct WatchDailyRecommendationSection: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    let recommendation: WatchDailyRecommendationSnapshot
    let showsStart: Bool

    var body: some View {
        Section("今日") {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(recommendation.readiness)
                        .font(.headline)
                        .foregroundStyle(WatchAppTheme.positive)
                    Spacer()
                    Text("\(completedCount)/\(recommendation.actions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }
                ForEach(recommendation.actions.prefix(3)) { action in
                    Label {
                        Text(action.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: action.isCompleted ? "checkmark.circle.fill" : action.systemImage)
                    }
                    .font(.caption)
                    .foregroundStyle(action.isCompleted ? WatchAppTheme.mutedInk : WatchAppTheme.ink)
                }
            }

            if showsStart, recommendation.preferredPlanID != nil {
                Button {
                    workoutStore.startRecommendedWorkout()
                } label: {
                    Label("開始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watchRecommendedStartButton")
            }
        }
    }

    private var completedCount: Int {
        recommendation.actions.filter(\.isCompleted).count
    }
}

struct WatchRecentSessionSection: View {
    let session: WatchWorkoutSessionSnapshot

    var body: some View {
        Section("前回の記録") {
            NavigationLink {
                WatchCompletedSetsArchiveView(session: session)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text(
                        "\(session.completedSetCount)セット・"
                            + "\(session.completedRepCount)回・"
                            + "\(session.totalVolume.formatted(.number.precision(.fractionLength(0...1))))kg"
                    )
                    .font(.caption2)
                    .foregroundStyle(WatchAppTheme.mutedInk)
                }
            }
            .accessibilityIdentifier("watchRecentSession")
        }
    }
}

struct WatchExercisePreviewView: View {
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
                        .foregroundStyle(WatchAppTheme.mutedInk)
                    Text("休憩 \(exercise.restSeconds)秒")
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }
            }

            Section("セット") {
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setOrder)")
                            .font(.headline)
                            .frame(width: 26, height: 26)
                            .background(WatchAppTheme.positive.opacity(0.2), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatWeight(set.targetWeight, unit: unit))
                                .font(.headline)
                            Text("\(set.targetReps)回")
                                .font(.caption)
                                .foregroundStyle(WatchAppTheme.mutedInk)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchWorkoutStore())
}
