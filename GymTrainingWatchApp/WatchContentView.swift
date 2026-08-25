import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WatchTutorialView.completedVersionKey) private var completedTutorialVersion = ""
    @State private var isShowingTutorial = false

    var body: some View {
        NavigationStack {
            Group {
                if workoutStore.activeSession != nil {
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
                    .accessibilityLabel(L10n.string("watch_widget.762361d25a0e", fallback: "Apple Watchの使い方"))
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
            if arguments.contains("--reset-watch-ui-test-data")
                || arguments.contains("--show-watch-tutorial") {
                completedTutorialVersion = ""
            }
            if arguments.contains("--show-watch-tutorial") {
                isShowingTutorial = true
            } else if !arguments.contains("--suppress-watch-tutorial"),
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
    static let currentVersion = "3"
    static let completedVersionKey = "watchTutorialCompletedVersion"

    let onComplete: () -> Void
    @State private var page = 0

    private let steps = [
        WatchTutorialStep(
            icon: "list.bullet.rectangle",
            title: L10n.string("watch_widget.2b5f588ea836", fallback: "メニューを選ぶ"),
            detail: L10n.string("watch_widget.172b72b0e366", fallback: "iPhoneから届いた今日のメニューを選び、開始します。")
        ),
        WatchTutorialStep(
            icon: "play.fill",
            title: L10n.string("watch_widget.864ffb74d301", fallback: "セットを開始"),
            detail: L10n.string("watch_widget.e71bb44afc57", fallback: "種目とセットを選んで開始。間違えた時は「キャンセル」で未実行に戻せます。")
        ),
        WatchTutorialStep(
            icon: "dial.medium",
            title: L10n.string("watch_widget.11f4022e0437", fallback: "実績を合わせる"),
            detail: L10n.string("watch_widget.50b4d8445e1e", fallback: "重量・回数・RPE・休憩は開始前後にリールで変更できます。")
        ),
        WatchTutorialStep(
            icon: "metronome",
            title: L10n.string("watch_widget.19550a012210", fallback: "テンポを合わせる"),
            detail: L10n.string("watch_widget.9a3e26289146", fallback: "上げ・下げ時間をセットごとに設定。Apple Watchが1秒あたり1〜3回の触覚で案内します。")
        ),
        WatchTutorialStep(
            icon: "timer",
            title: L10n.string("watch_widget.c69c7fb85f9b", fallback: "休憩する"),
            detail: L10n.string("watch_widget.8dbc8435b124", fallback: "完了すると休憩タイマーが開始。次の種目は順番を変えて選べます。")
        ),
        WatchTutorialStep(
            icon: "iphone.and.arrow.forward",
            title: L10n.string("watch_widget.64b1330508b2", fallback: "終了して同期"),
            detail: L10n.string("watch_widget.7b80546b6322", fallback: "最後に終了するとiPhoneへ送信。未送信の記録はあとから再送できます。")
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
                Button(L10n.string("watch_widget.5e1713107aae", fallback: "スキップ"), action: onComplete)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L10n.string("watch_widget.db540f633c8c", fallback: "チュートリアルをスキップ"))
                    .accessibilityIdentifier("skipWatchTutorialButton")

                Button {
                    if page == steps.count - 1 {
                        onComplete()
                    } else {
                        page += 1
                    }
                } label: {
                    Label(page == steps.count - 1 ? L10n.string("watch_widget.afec905a94f5", fallback: "使い始める") : L10n.string("watch_widget.c8c2bdae1bbc", fallback: "次へ"), systemImage: page == steps.count - 1 ? "checkmark" : "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(page == steps.count - 1 ? "completeWatchTutorialButton" : "nextWatchTutorialButton")
            }
            .font(.footnote)
        }
        .padding(.horizontal, 10)
        .accessibilityLabel(L10n.string("watch_widget.508051ad5c0a", fallback: "使い方 {{value1}}/{{value2}}", values: [String(describing: page + 1), String(describing: steps.count)]))
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

                Text(L10n.string("watch_widget.12ffae136992", fallback: "メニュー待ち"))
                    .font(.headline)
            }

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(WatchAppTheme.mutedInk)
                .multilineTextAlignment(.center)

            Text(L10n.string("watch_widget.8e03ffd59ca7", fallback: "iPhoneのホームから今日の内容を同期します。"))
                .font(.caption2)
                .foregroundStyle(WatchAppTheme.mutedInk)
                .multilineTextAlignment(.center)

            NavigationLink {
                WatchOutdoorWorkoutSetupView()
            } label: {
                Label(L10n.string("watch_widget.outdoor_start", fallback: "屋外運動を始める"), systemImage: "figure.run")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("watchOutdoorWorkoutLink")
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
                    Text(L10n.string("watch_widget.686a6c522309", fallback: "今日のメニュー"))
                        .font(.headline)
                    Text(L10n.string("watch_widget.3148813301ee", fallback: "{{value1}}件から選択", values: [String(describing: plans.count)]))
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

            Section(L10n.string("watch_widget.54ef1a234c86", fallback: "メニュー")) {
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

            Section(L10n.string("watch_widget.outdoor", fallback: "屋外有酸素")) {
                NavigationLink {
                    WatchOutdoorWorkoutSetupView()
                } label: {
                    Label(L10n.string("watch_widget.outdoor_start", fallback: "屋外運動を始める"), systemImage: "figure.run")
                }
                .accessibilityIdentifier("watchOutdoorWorkoutLink")
            }

            if let pendingSession {
                Section(L10n.string("watch_widget.51caea1e57ce", fallback: "未送信")) {
                    Button {
                        workoutStore.resendPendingSession()
                    } label: {
                        Label(L10n.string("watch_widget.8a6e496052a2", fallback: "{{value1}} を再送", values: [pendingSession.title]), systemImage: "arrow.clockwise")
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
                    Label(L10n.string("watch_widget.73efe52b65c2", fallback: "開始"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watchStartWorkoutButton")

                Button {
                    workoutStore.clearPlanSelection()
                } label: {
                    Label(L10n.string("watch_widget.137725ad45aa", fallback: "メニュー変更"), systemImage: "arrow.left.circle")
                }
                .accessibilityIdentifier("watchChangeMenuButton")

                if let pendingSession {
                    Button {
                        workoutStore.resendPendingSession()
                    } label: {
                        Label(L10n.string("watch_widget.8a6e496052a2", fallback: "{{value1}} を再送", values: [pendingSession.title]), systemImage: "arrow.clockwise")
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
        Section(L10n.string("watch_widget.9890a0a76fc6", fallback: "今日")) {
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
                    Label(L10n.string("watch_widget.73efe52b65c2", fallback: "開始"), systemImage: "play.fill")
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
        Section(L10n.string("watch_widget.a6830bdb3dd4", fallback: "前回の記録")) {
            NavigationLink {
                WatchCompletedSetsArchiveView(session: session)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text(recentSummary)
                    .font(.caption2)
                    .foregroundStyle(WatchAppTheme.mutedInk)
                }
            }
            .accessibilityIdentifier("watchRecentSession")
        }
    }

    private var recentSummary: String {
        if let cardio = session.outdoorCardio {
            let distance = cardio.distanceKilometers.formatted(.number.precision(.fractionLength(1)))
            let duration = Int(max(0, (session.endedAt ?? Date()).timeIntervalSince(session.startedAt)) / 60)
            return "\(distance) km・\(duration) min"
        }
        return L10n.string("watch_widget.9ae2c6a9fa00", fallback: "{{value1}}セット・", values: [String(describing: session.completedSetCount)])
            + L10n.string("watch_widget.d1749584e623", fallback: "{{value1}}回・", values: [String(describing: session.completedRepCount)])
            + "\(session.totalVolume.formatted(.number.precision(.fractionLength(0...1))))kg"
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
                    Text(L10n.string("watch_widget.09998c5a6ec8", fallback: "休憩 {{value1}}秒", values: [String(describing: exercise.restSeconds)]))
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }
            }

            Section(L10n.string("watch_widget.558199564f3f", fallback: "セット")) {
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setOrder)")
                            .font(.headline)
                            .frame(width: 26, height: 26)
                            .background(WatchAppTheme.positive.opacity(0.2), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatWeight(set.targetWeight, unit: unit))
                                .font(.headline)
                            Text(L10n.string("watch_widget.672403542889", fallback: "{{value1}}回", values: [String(describing: set.targetReps)]))
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
