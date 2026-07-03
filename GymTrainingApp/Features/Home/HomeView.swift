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
            .background(TrainingBackground())
            .navigationTitle("Gym Training")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $activeSession) { session in
                WorkoutSessionView(session: session)
            }
        }
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
                    Text("TODAY'S SESSION")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                        .tracking(1.2)

                    Text(plan?.name ?? "計画を作成しましょう")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer()

                Text(plan == nil ? "未設定" : "Ready")
                    .font(.caption.bold())
                    .foregroundStyle(plan == nil ? .white.opacity(0.65) : AppTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(plan == nil ? Color.white.opacity(0.12) : AppTheme.accent, in: Capsule())
            }

            if let plan {
                HStack(spacing: 10) {
                    Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                    Label("\(plan.totalSetCount)セット", systemImage: "checklist")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

                Text(plan.exercises.map { $0.exercise.name }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
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
                .foregroundStyle(AppTheme.ink)
            } else {
                Text("計画タブで種目とセット目標を登録すると、ここからすぐ開始できます。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(20)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.gymFloor,
                                Color(red: 0.18, green: 0.22, blue: 0.17)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 8) {
                    ForEach(0..<5) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 150, height: 1)
                    }
                }
                .rotationEffect(.degrees(-28))
                .offset(x: 18, y: -18)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: AppTheme.gymFloor.opacity(0.28), radius: 24, x: 0, y: 16)
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
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 14, x: 0, y: 8)
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
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(0.08), radius: 14, x: 0, y: 8)
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
