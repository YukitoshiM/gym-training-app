import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var activeSession: WorkoutSession?

    private var nextPlan: TrainingPlan? {
        appStore.plans.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    TodayTrainingCard(plan: nextPlan) {
                        if let nextPlan {
                            activeSession = WorkoutSession(plan: nextPlan)
                        }
                    }

                    HStack(spacing: 10) {
                        CompactStat(title: "計画", value: "\(appStore.plans.count)", suffix: "件", tint: AppTheme.blue)
                        CompactStat(title: "履歴", value: "\(appStore.workoutHistory.count)", suffix: "件", tint: AppTheme.orange)
                        CompactStat(title: "直近", value: latestAchievementText, suffix: "", tint: AppTheme.accent)
                    }

                    BodyKPIDashboard(
                        kinds: BodyMetricKind.allCases,
                        latestEntry: { appStore.latestBodyMetricEntry(for: $0) },
                        goal: { appStore.bodyMetricGoal(for: $0) },
                        tint: metricTint(for:)
                    )
                }
                .padding(16)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("ホーム")
            .fullScreenCover(item: $activeSession) { session in
                WorkoutSessionView(session: session)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gym Training")
                .font(.title.bold())
            Text("今日やること、記録、身体KPIをすぐ確認できます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var latestAchievementText: String {
        guard let latest = appStore.workoutHistory.first else {
            return "-"
        }

        return AppFormatters.percent(latest.achievementRate)
    }

    private func metricTint(for kind: BodyMetricKind) -> Color {
        switch kind {
        case .bodyWeight: AppTheme.blue
        case .waist: AppTheme.orange
        case .bodyFatPercentage: AppTheme.purple
        }
    }
}

private struct TodayTrainingCard: View {
    let plan: TrainingPlan?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("次のトレーニング")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(plan?.name ?? "計画を作成しましょう")
                        .font(.title2.bold())
                        .lineLimit(2)
                }

                Spacer()

                Text(plan == nil ? "未設定" : "Ready")
                    .font(.caption.bold())
                    .foregroundStyle(plan == nil ? .secondary : AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }

            if let plan {
                HStack(spacing: 10) {
                    Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                    Label("\(plan.totalSetCount)セット", systemImage: "checklist")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(plan.exercises.map { $0.exercise.name }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Button(action: onStart) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("この計画で記録を開始")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
            } else {
                Text("計画タブで種目とセット目標を登録すると、ここからすぐ開始できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct CompactStat: View {
    let title: String
    let value: String
    let suffix: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Capsule()
                .fill(tint)
                .frame(width: 28, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct BodyKPIDashboard: View {
    let kinds: [BodyMetricKind]
    let latestEntry: (BodyMetricKind) -> BodyMetricEntry?
    let goal: (BodyMetricKind) -> BodyMetricGoal
    let tint: (BodyMetricKind) -> Color

    var body: some View {
        NavigationLink {
            BodyMetricListView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("身体KPI")
                            .font(.headline)
                        Text("目標差と推移をまとめて確認")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                ForEach(kinds) { kind in
                    BodyKPIProgressRow(
                        kind: kind,
                        entry: latestEntry(kind),
                        goal: goal(kind),
                        tint: tint(kind)
                    )
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bodyMetricListLink")
    }
}

private struct BodyKPIProgressRow: View {
    let kind: BodyMetricKind
    let entry: BodyMetricEntry?
    let goal: BodyMetricGoal
    let tint: Color

    private var progress: Double {
        guard let entry,
              let rate = goal.achievementRate(from: entry.value) else {
            return 0
        }

        return rate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.subheadline.bold())
            }

            ProgressView(value: progress)
                .tint(tint)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var valueText: String {
        guard let entry else {
            return "未記録"
        }

        return AppFormatters.metricValue(entry.value, unit: kind.unit)
    }

    private var detailText: String {
        guard let entry else {
            return "最初の値を記録してください"
        }

        guard let target = goal.targetValue,
              let delta = goal.delta(from: entry.value) else {
            return "目標未設定"
        }

        let sign = delta > 0 ? "+" : ""
        return "目標 \(AppFormatters.metricValue(target, unit: kind.unit)) / 差分 \(sign)\(AppFormatters.metricValue(delta, unit: kind.unit))"
    }
}

#Preview {
    HomeView()
        .environmentObject(AppStore())
}
