import SwiftUI

struct SensorTrainingAnalysisView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    private var analytics: SensorTrainingAnalytics {
        SensorTrainingAnalytics(
            sessions: appStore.workoutHistory,
            meals: appStore.mealEntries,
            recoveryHistory: healthDataManager.recoveryHistory
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TrainingLoadOverviewCard(analytics: analytics)

                HStack(spacing: 10) {
                    SensorAnalysisMetric(
                        title: L10n.string("health_meals_body_ai.f42eb4dd5c1d", fallback: "セット品質"),
                        value: analytics.setQuality.map { "\(Int($0 * 100))%" } ?? "-",
                        detail: L10n.string("health_meals_body_ai.5b8e684267ba", fallback: "目標達成と動作安定"),
                        tint: AppTheme.positive
                    )
                    SensorAnalysisMetric(
                        title: L10n.string("health_meals_body_ai.9cecb9de001c", fallback: "密度"),
                        value: analytics.volumeDensity.map { Int($0).formatted() } ?? "-",
                        detail: L10n.string("health_meals_body_ai.05fbc7a9d044", fallback: "kg / 分"),
                        tint: AppTheme.blue
                    )
                }

                HStack(spacing: 10) {
                    SensorAnalysisMetric(
                        title: L10n.string("health_meals_body_ai.7a101c9b7ca5", fallback: "心拍回復"),
                        value: analytics.averageHeartRateRecovery.map { "\(Int($0))" } ?? "-",
                        detail: L10n.string("health_meals_body_ai.ec8769bf01cc", fallback: "bpm / 30秒"),
                        tint: AppTheme.critical
                    )
                    SensorAnalysisMetric(
                        title: L10n.string("health_meals_body_ai.1a77000ba493", fallback: "計測率"),
                        value: "\(Int(analytics.sensorCoverage * 100))%",
                        detail: L10n.string("health_meals_body_ai.f7a0028b2b6a", fallback: "Watchセンサー付き"),
                        tint: AppTheme.purple
                    )
                }

                WeeklyComparisonCard(analytics: analytics)
                SetQualityBreakdownCard(dimensions: analytics.qualityDimensions)
                ConditionComparisonCard(insights: analytics.comparisonInsights)
                MovementQualityCard(analytics: analytics)
                PlateauCard(exerciseNames: analytics.plateauExerciseNames)
                PlateauEvidenceCard(factors: analytics.plateauFactors)
                TrainingSuggestionCard(analytics: analytics, goal: appStore.userProfile.goalType)
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(TrainingBackground())
        .navigationTitle(L10n.string("health_meals_body_ai.4e27cb296a97", fallback: "トレーニング分析"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetQualityBreakdownCard: View {
    let dimensions: [AnalysisDimension]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 11) {
                Label(L10n.string("health_meals_body_ai.fe9c10c97608", fallback: "セット品質の内訳"), systemImage: "checklist")
                    .font(.headline)
                ForEach(dimensions) { dimension in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(dimension.title)
                                .font(.footnote.bold())
                            Spacer()
                            Text(dimension.score.map { "\(Int($0 * 100))%" } ?? L10n.string("health_meals_body_ai.e7150bf221cb", fallback: "未取得"))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        ProgressView(value: dimension.score ?? 0)
                            .tint(dimension.score == nil ? AppTheme.mutedInk : AppTheme.accent)
                    }
                }
                Text(L10n.string("health_meals_body_ai.f411122ea062", fallback: "取得できた重量・回数・テンポ・相対可動域・RPEだけで算出し、欠測値は0点にしません。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityIdentifier("setQualityBreakdownCard")
    }
}

private struct ConditionComparisonCard: View {
    let insights: [AnalysisInsight]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("health_meals_body_ai.4d4309ebc66e", fallback: "条件別比較"), systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                if insights.isEmpty {
                    Text(L10n.string("health_meals_body_ai.c944b82d7eb8", fallback: "同じ種目・メニュー・時間帯の記録が増えると比較できます。"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    ForEach(insights.prefix(8)) { insight in
                        HStack(alignment: .top) {
                            Text(insight.category)
                                .font(.footnote.bold())
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(insight.title)
                                    .font(.subheadline.bold())
                                Text(insight.detail)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("conditionComparisonCard")
    }
}

private struct PlateauEvidenceCard: View {
    let factors: [AnalysisInsight]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("health_meals_body_ai.a7f7c52063ec", fallback: "停滞要因の材料"), systemImage: "scope")
                    .font(.headline)
                ForEach(factors) { factor in
                    HStack(alignment: .top) {
                        Text(factor.title)
                            .font(.footnote.bold())
                            .frame(width: 62, alignment: .leading)
                        Text(factor.detail)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
                Text(L10n.string("health_meals_body_ai.834d88de3434", fallback: "同時に変化した項目を候補として示すもので、原因や医療状態を断定しません。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityIdentifier("plateauEvidenceCard")
    }
}

private struct TrainingLoadOverviewCard: View {
    let analytics: SensorTrainingAnalytics

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("health_meals_body_ai.00801f6516ce", fallback: "直近7日"))
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(L10n.string("health_meals_body_ai.d652958253ce", fallback: "トレーニング負荷"))
                    .font(.title2.bold())

                HStack {
                    AnalysisCompactValue(title: L10n.string("health_meals_body_ai.7287fddb8374", fallback: "回数"), value: L10n.string("health_meals_body_ai.f20927268a6d", fallback: "{{value1}}回", values: [String(describing: analytics.currentWeekSessionCount)]))
                    Divider()
                    AnalysisCompactValue(title: L10n.string("health_meals_body_ai.4c46ceec68e0", fallback: "セット"), value: "\(analytics.currentWeekSetCount)")
                    Divider()
                    AnalysisCompactValue(title: L10n.string("health_meals_body_ai.041784c72fcd", fallback: "時間"), value: analytics.currentWeekMinutes.map { L10n.string("health_meals_body_ai.e3e557893569", fallback: "{{value1}}分", values: [String(describing: Int($0))]) } ?? "-")
                }
                .frame(height: 44)

                if let change = analytics.weeklyVolumeChange {
                    Label(
                        L10n.string("health_meals_body_ai.978741a28a39", fallback: "前週比 {{value1}}%", values: ["\(change >= 0 ? "+" : "")\(Int(change * 100))"]),
                        systemImage: change > 0.15 ? "arrow.up.right" : (change < -0.15 ? "arrow.down.right" : "arrow.right")
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(abs(change) > 0.3 ? AppTheme.orange : AppTheme.ink)
                }
            }
        }
    }
}

private struct SensorAnalysisMetric: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                Text(value)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AnalysisCompactValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyComparisonCard: View {
    let analytics: SensorTrainingAnalytics

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("health_meals_body_ai.f56ee73fb4dd", fallback: "週次比較"))
                    .font(.headline)
                ComparisonBar(title: L10n.string("health_meals_body_ai.8f6e8ec10218", fallback: "今週"), value: analytics.currentWeekVolume, maximum: maximumVolume, tint: AppTheme.accent)
                ComparisonBar(title: L10n.string("health_meals_body_ai.f41bf6a53cd4", fallback: "前週"), value: analytics.previousWeekVolume, maximum: maximumVolume, tint: AppTheme.blue)

                Text(L10n.string("health_meals_body_ai.8c75473ee509", fallback: "ボリュームは完了セットの重量 × 回数。種目構成が大きく違う週は単純比較しすぎないでください。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    private var maximumVolume: Double {
        max(analytics.currentWeekVolume, analytics.previousWeekVolume, 1)
    }
}

private struct ComparisonBar: View {
    let title: String
    let value: Double
    let maximum: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.footnote.bold())
                Spacer()
                Text(Int(value).formatted() + " kg")
                    .font(.footnote.monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(1, value / maximum))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct MovementQualityCard: View {
    let analytics: SensorTrainingAnalytics

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("health_meals_body_ai.3e054aa7cb45", fallback: "動作推定"), systemImage: "sensor.tag.radiowaves.forward")
                    .font(.headline)
                Text(analytics.motionSummary)
                    .font(.subheadline)
                if analytics.motionCorrectionCount > 0 {
                    Text(L10n.string("health_meals_body_ai.f8ca17da4fc3", fallback: "手入力との差があったセット {{value1}}件", values: [String(describing: analytics.motionCorrectionCount)]))
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.orange)
                }
                Text(L10n.string("health_meals_body_ai.ac7338c98088", fallback: "手首の動きだけでは種目やフォームを断定できません。推定回数は確認してから反映します。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

private struct PlateauCard: View {
    let exerciseNames: [String]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("health_meals_body_ai.4bfe07c53900", fallback: "停滞チェック"), systemImage: "chart.line.flattrend.xyaxis")
                    .font(.headline)
                if exerciseNames.isEmpty {
                    Text(L10n.string("health_meals_body_ai.65d6f899ad2f", fallback: "3回以上記録された種目に明確な停滞候補はありません。"))
                        .font(.subheadline)
                } else {
                    ForEach(exerciseNames, id: \.self) { name in
                        Label(name, systemImage: "exclamationmark.circle")
                            .font(.subheadline.bold())
                    }
                    Text(L10n.string("health_meals_body_ai.7bd42e67d0fc", fallback: "直近3回で最大使用重量が伸びていない候補です。フォーム、回数、RPEも合わせて判断してください。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
    }
}

private struct TrainingSuggestionCard: View {
    let analytics: SensorTrainingAnalytics
    let goal: GoalType

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 9) {
                Label(L10n.string("health_meals_body_ai.84b073b073ed", fallback: "次の調整"), systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text(analytics.suggestion(for: goal))
                    .font(.subheadline)
                Text(L10n.string("health_meals_body_ai.23786a963f38", fallback: "体調や痛みがある場合は数値より本人の感覚を優先してください。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

private struct SensorTrainingAnalytics {
    let sessions: [WorkoutSession]
    let meals: [MealEntry]
    let recoveryHistory: [DailyRecoveryTrendRecord]

    private var now: Date { Date() }
    private var currentStart: Date { Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast }
    private var previousStart: Date { Calendar.current.date(byAdding: .day, value: -14, to: now) ?? .distantPast }

    private var currentSessions: [WorkoutSession] {
        sessions.filter { $0.startedAt >= currentStart }
    }

    private var previousSessions: [WorkoutSession] {
        sessions.filter { $0.startedAt >= previousStart && $0.startedAt < currentStart }
    }

    private var allCompletedSets: [WorkoutSet] {
        sessions.flatMap(\.exercises).flatMap(\.sets).filter(\.isCompleted)
    }

    var currentWeekSessionCount: Int { currentSessions.count }
    var currentWeekSetCount: Int { currentSessions.reduce(0) { $0 + $1.completedSetCount } }
    var currentWeekVolume: Double { currentSessions.reduce(0) { $0 + $1.totalVolume } }
    var previousWeekVolume: Double { previousSessions.reduce(0) { $0 + $1.totalVolume } }

    var currentWeekMinutes: Double? {
        let durations = currentSessions.compactMap { $0.sensorSummary?.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / 60
    }

    var weeklyVolumeChange: Double? {
        guard previousWeekVolume > 0 else { return nil }
        return (currentWeekVolume - previousWeekVolume) / previousWeekVolume
    }

    var setQuality: Double? {
        let values = qualityDimensions.compactMap(\.score)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var qualityDimensions: [AnalysisDimension] {
        let weightedSets = allCompletedSets.filter { $0.targetWeight > 0 }
        let weight = average(weightedSets.map { min(1, $0.actualWeight / max($0.targetWeight, 0.1)) })
        let reps = average(allCompletedSets.filter { $0.targetReps > 0 }.map {
            min(1, Double($0.actualReps) / Double(max($0.targetReps, 1)))
        })
        let tempo = average(allCompletedSets.compactMap { set in
            guard let summary = set.sensorSummary,
                  summary.averageRepDuration != nil else { return nil }
            let loss = abs(summary.velocityLossPercent ?? 0)
            return min(1, max(0, 1 - loss / 40))
        })
        let range = average(allCompletedSets.compactMap {
            $0.sensorSummary?.rangeOfMotionConsistency ?? $0.sensorSummary?.movementConsistency
        })
        let rpe = average(allCompletedSets.compactMap { set in
            guard let rpe = set.rpe else { return nil }
            return min(1, max(0, 1 - abs(rpe - 8) / 4))
        })
        return [
            AnalysisDimension(title: L10n.string("health_meals_body_ai.8bfd55a4ed1d", fallback: "重量"), score: weight),
            AnalysisDimension(title: L10n.string("health_meals_body_ai.7287fddb8374", fallback: "回数"), score: reps),
            AnalysisDimension(title: L10n.string("health_meals_body_ai.4792fe290e90", fallback: "テンポ"), score: tempo),
            AnalysisDimension(title: L10n.string("health_meals_body_ai.8830d85c52ee", fallback: "相対可動域"), score: range),
            AnalysisDimension(title: "RPE", score: rpe)
        ]
    }

    var volumeDensity: Double? {
        let measured = sessions.compactMap { session -> (Double, Double)? in
            guard let duration = session.sensorSummary?.durationSeconds, duration >= 60 else { return nil }
            return (session.totalVolume, duration / 60)
        }
        guard !measured.isEmpty else { return nil }
        let volume = measured.reduce(0) { $0 + $1.0 }
        let minutes = measured.reduce(0) { $0 + $1.1 }
        return minutes > 0 ? volume / minutes : nil
    }

    var averageHeartRateRecovery: Double? {
        let values = allCompletedSets.compactMap { $0.sensorSummary?.heartRateRecovery }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var sensorCoverage: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(sessions.filter { $0.sensorSummary != nil }.count) / Double(sessions.count)
    }

    var motionCorrectionCount: Int {
        allCompletedSets.filter {
            guard let estimated = $0.sensorSummary?.estimatedReps else { return false }
            return estimated != $0.actualReps
        }.count
    }

    var motionSummary: String {
        let measured = allCompletedSets.compactMap { $0.sensorSummary?.movementConsistency }
        guard !measured.isEmpty else { return L10n.string("health_meals_body_ai.8b421501c6ce", fallback: "動作データはまだありません。Watchでセットを開始すると推定します。") }
        let average = measured.reduce(0, +) / Double(measured.count)
        return L10n.string("health_meals_body_ai.6917e81df8db", fallback: "{{value1}}セットの平均安定度は {{value2}}% です。", values: [String(describing: measured.count), String(describing: Int(average * 100))])
    }

    var plateauExerciseNames: [String] {
        let exerciseRecords = sessions
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { session in session.exercises.map { (session.startedAt, $0) } }
        let grouped = Dictionary(grouping: exerciseRecords, by: { $0.1.exercise.name })

        return grouped.compactMap { name, records in
            let latest = Array(records.prefix(3))
            guard latest.count == 3 else { return nil }
            let maximumWeights = latest.map { record in
                record.1.sets.filter(\.isCompleted).map(\.actualWeight).max() ?? 0
            }
            guard maximumWeights.allSatisfy({ $0 > 0 }) else { return nil }
            return (maximumWeights[0] - maximumWeights[2]) <= 0.1 ? name : nil
        }
        .sorted()
    }

    var comparisonInsights: [AnalysisInsight] {
        exerciseComparisons + menuComparisons + timeOfDayComparisons
    }

    var plateauFactors: [AnalysisInsight] {
        let recentRecovery = recoveryHistory.filter { $0.date >= previousStart }
        let sleepAverage = average(recentRecovery.compactMap(\.sleepHours))
        let hrvAverage = average(recentRecovery.compactMap(\.hrvRatio))
        let recentMeals = meals.filter { $0.recordedAt >= previousStart }
        let mealDays = Set(recentMeals.map { Calendar.current.startOfDay(for: $0.recordedAt) }).count
        let proteinAverage = mealDays > 0
            ? recentMeals.reduce(0) { $0 + $1.protein } / Double(mealDays)
            : nil
        let frequency = Double(currentWeekSessionCount)

        return [
            AnalysisInsight(
                category: L10n.string("health_meals_body_ai.625a53e73e40", fallback: "要因"),
                title: L10n.string("health_meals_body_ai.8878e4c5b97f", fallback: "睡眠"),
                detail: sleepAverage.map { L10n.string("health_meals_body_ai.af2cc7357835", fallback: "直近記録平均 {{value1}}時間", values: [String(describing: $0.formatted(.number.precision(.fractionLength(1))))]) } ?? L10n.string("health_meals_body_ai.4c5179b35822", fallback: "比較できる日次データがありません")
            ),
            AnalysisInsight(
                category: L10n.string("health_meals_body_ai.625a53e73e40", fallback: "要因"),
                title: L10n.string("health_meals_body_ai.5602244ffb3a", fallback: "回復"),
                detail: hrvAverage.map { L10n.string("health_meals_body_ai.953bd2bfe007", fallback: "HRV比の平均 {{value1}}%（個人基準比）", values: [String(describing: Int($0 * 100))]) } ?? L10n.string("health_meals_body_ai.a938c37a9c75", fallback: "HRVの継続データがありません")
            ),
            AnalysisInsight(
                category: L10n.string("health_meals_body_ai.625a53e73e40", fallback: "要因"),
                title: L10n.string("health_meals_body_ai.738844ab541c", fallback: "食事"),
                detail: proteinAverage.map { L10n.string("health_meals_body_ai.f66aeeafd500", fallback: "記録{{value1}}日・たんぱく質平均 {{value2}}g/記録日", values: [String(describing: mealDays), String(describing: Int($0))]) } ?? L10n.string("health_meals_body_ai.b3ac75dc7510", fallback: "食事記録がありません")
            ),
            AnalysisInsight(
                category: L10n.string("health_meals_body_ai.625a53e73e40", fallback: "要因"),
                title: L10n.string("health_meals_body_ai.e216609daeb6", fallback: "頻度"),
                detail: L10n.string("health_meals_body_ai.9ef3eebb8e35", fallback: "直近7日 {{value1}}回", values: [String(describing: Int(frequency))])
            ),
            AnalysisInsight(
                category: L10n.string("health_meals_body_ai.625a53e73e40", fallback: "要因"),
                title: L10n.string("health_meals_body_ai.90858d235fa5", fallback: "ボリューム"),
                detail: weeklyVolumeChange.map { L10n.string("health_meals_body_ai.41151468db96", fallback: "前週比 {{value1}}%", values: ["\($0 >= 0 ? "+" : "")\(Int($0 * 100))"]) } ?? L10n.string("health_meals_body_ai.a9058584802a", fallback: "前週との比較データが不足")
            )
        ]
    }

    private var exerciseComparisons: [AnalysisInsight] {
        let records = sessions.sorted { $0.startedAt > $1.startedAt }.flatMap { session in
            session.exercises.map { (session.startedAt, $0.exercise.name, $0.totalVolume) }
        }
        return Dictionary(grouping: records, by: { $0.1 }).compactMap { name, values in
            guard values.count >= 2, values[1].2 > 0 else { return nil }
            let change = (values[0].2 - values[1].2) / values[1].2
            return AnalysisInsight(category: L10n.string("health_meals_body_ai.897341c7f1b0", fallback: "種目"), title: name, detail: L10n.string("health_meals_body_ai.16a787976406", fallback: "前回比 {{value1}}", values: [signedPercent(change)]))
        }
        .sorted { $0.title < $1.title }
    }

    private var menuComparisons: [AnalysisInsight] {
        Dictionary(grouping: sessions.sorted { $0.startedAt > $1.startedAt }, by: \.title).compactMap { title, values in
            guard values.count >= 2, values[1].totalVolume > 0 else { return nil }
            let change = (values[0].totalVolume - values[1].totalVolume) / values[1].totalVolume
            return AnalysisInsight(category: L10n.string("health_meals_body_ai.b42ca3558100", fallback: "メニュー"), title: title, detail: L10n.string("health_meals_body_ai.16a787976406", fallback: "前回比 {{value1}}", values: [signedPercent(change)]))
        }
        .sorted { $0.title < $1.title }
    }

    private var timeOfDayComparisons: [AnalysisInsight] {
        let grouped = Dictionary(grouping: sessions, by: { timeBucket(for: $0.startedAt) })
        return [L10n.string("health_meals_body_ai.fb30f3e9ff8f", fallback: "朝"), L10n.string("health_meals_body_ai.4be68a8e4622", fallback: "昼"), L10n.string("health_meals_body_ai.74ba117a8319", fallback: "夜")].compactMap { bucket in
            guard let values = grouped[bucket], !values.isEmpty else { return nil }
            let achievement = average(values.map(\.achievementRate)) ?? 0
            return AnalysisInsight(
                category: L10n.string("health_meals_body_ai.1472efa74baa", fallback: "時間帯"),
                title: bucket,
                detail: L10n.string("health_meals_body_ai.50a93127c0f7", fallback: "{{value1}}回・平均達成率 {{value2}}%", values: [String(describing: values.count), String(describing: Int(achievement * 100))])
            )
        }
    }

    private func timeBucket(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: L10n.string("health_meals_body_ai.fb30f3e9ff8f", fallback: "朝")
        case 12..<18: L10n.string("health_meals_body_ai.4be68a8e4622", fallback: "昼")
        default: L10n.string("health_meals_body_ai.74ba117a8319", fallback: "夜")
        }
    }

    private func signedPercent(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(Int(value * 100))%"
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func suggestion(for goal: GoalType) -> String {
        if let change = weeklyVolumeChange, change > 0.3 {
            return L10n.string("health_meals_body_ai.a83b5bccdf24", fallback: "前週よりボリュームが30%以上増えています。次回は同程度を維持し、RPEと回復指標を確認しましょう。")
        }
        if !plateauExerciseNames.isEmpty {
            return L10n.string("health_meals_body_ai.6055fa3672d8", fallback: "停滞候補の種目は、重量を一度下げて目標回数をそろえるか、休憩を15〜30秒延ばして比較しましょう。")
        }
        if goal == .muscleGain, currentWeekSessionCount < 2 {
            return L10n.string("health_meals_body_ai.1a14ccfb8745", fallback: "筋肥大が目的なら、無理のない範囲で今週もう1回のトレーニングを検討できます。")
        }
        return L10n.string("health_meals_body_ai.0f9da1e37f0e", fallback: "大きな急増や停滞候補はありません。次回も目標回数とRPEをそろえて比較できる記録を増やしましょう。")
    }
}

private struct AnalysisDimension: Identifiable {
    let title: String
    let score: Double?
    var id: String { title }
}

private struct AnalysisInsight: Identifiable {
    let category: String
    let title: String
    let detail: String
    var id: String { category + title }
}

#Preview {
    NavigationStack {
        SensorTrainingAnalysisView()
            .environmentObject(AppStore())
            .environmentObject(HealthDataManager())
    }
}
