import SwiftUI
import MapKit

struct ConditionDashboardView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var gymLocationManager: GymLocationManager

    private var readiness: ReadinessAssessment {
        healthDataManager.readinessAssessment(
            recentWorkouts: appStore.workoutHistory,
            subjectiveRecovery: appStore.todaySubjectiveRecovery
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    SensorTrainingAnalysisView()
                } label: {
                    CardContainer {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "chart.xyaxis.line", tint: AppTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.string("health_meals_body_ai.4e27cb296a97", fallback: "トレーニング分析"))
                                    .font(.headline)
                                Text(L10n.string("health_meals_body_ai.b9428ba987dc", fallback: "負荷・セット品質・心拍回復・停滞候補"))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.bold())
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sensorTrainingAnalysisLink")

                HealthKitDisclosureCard(accessState: healthDataManager.accessState) {
                    Task { await healthDataManager.requestAuthorization() }
                }

                if healthDataManager.accessState == .requesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("healthAuthorizationProgress")
                } else if healthDataManager.accessState != .notRequested {
                    ReadinessCard(assessment: readiness)
                    SubjectiveRecoveryCard()
                    SleepDetailsCard(summary: healthDataManager.snapshot.sleepSummary)
                    ActivityProgressCard(
                        progress: healthDataManager.snapshot.activityProgress,
                        steps: healthDataManager.snapshot.steps,
                        distance: healthDataManager.snapshot.walkingRunningDistanceKilometers,
                        flights: healthDataManager.snapshot.flightsClimbed
                    )
                    EnergyBalanceCard(
                        mealCalories: appStore.mealEntries().reduce(0) { $0 + $1.calories },
                        activeEnergy: healthDataManager.snapshot.activeEnergyKilocalories,
                        restingEnergy: healthDataManager.snapshot.restingEnergyKilocalories
                    )
                    RecoveryMetricsSection(snapshot: healthDataManager.snapshot)
                    EnvironmentMetricsSection(snapshot: healthDataManager.snapshot)
                    OutdoorRouteCard(route: healthDataManager.snapshot.latestOutdoorRoute)
                    HealthDataQualityCard(snapshot: healthDataManager.snapshot)
                }

                GymVisitCard()
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(TrainingBackground())
        .navigationTitle(L10n.string("health_meals_body_ai.e8c88bb7608c", fallback: "コンディション"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await healthDataManager.refresh() }
                } label: {
                    if healthDataManager.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(healthDataManager.isRefreshing || healthDataManager.accessState == .notRequested)
                .accessibilityLabel(L10n.string("health_meals_body_ai.fe02dc7991e6", fallback: "Healthデータを更新"))
                .accessibilityIdentifier("refreshHealthDataButton")
            }
        }
        .task {
            guard healthDataManager.accessState != .notRequested else { return }
            await healthDataManager.refresh()
        }
    }
}

struct ConditionSummaryCard: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    private var assessment: ReadinessAssessment {
        healthDataManager.readinessAssessment(
            recentWorkouts: appStore.workoutHistory,
            subjectiveRecovery: appStore.todaySubjectiveRecovery
        )
    }

    var body: some View {
        CardContainer {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: Double(assessment.score ?? 0) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(assessment.score.map(String.init) ?? "-")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(L10n.string("health_meals_body_ai.e8c88bb7608c", fallback: "コンディション"), systemImage: "heart.text.square")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Text(healthDataManager.accessState == .notRequested ? L10n.string("health_meals_body_ai.4597562046d9", fallback: "Apple Healthを連携") : assessment.level.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(tint)
                    Text(healthDataManager.accessState == .notRequested ? L10n.string("health_meals_body_ai.051a5a9c5eea", fallback: "睡眠・回復・活動量をまとめて確認できます。") : assessment.summary)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tint: Color {
        guard healthDataManager.accessState != .notRequested else { return AppTheme.blue }
        return switch assessment.level {
        case .good: AppTheme.positive
        case .moderate: AppTheme.blue
        case .recover: AppTheme.orange
        }
    }
}

private struct SubjectiveRecoveryCard: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingEditor = false

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "gauge.with.dots.needle.33percent", tint: AppTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("health_meals_body_ai.e2d8e613515a", fallback: "今日の体感疲労"))
                        .font(.headline)
                    Text(currentLabel)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
                Spacer()
                Button {
                    isShowingEditor = true
                } label: {
                    Label(L10n.string("health_meals_body_ai.88346340fae8", fallback: "記録"), systemImage: "dial.medium")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("subjectiveFatigueMenu")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            SubjectiveRecoveryEditor(options: Self.options)
                .environmentObject(appStore)
        }
    }

    private var currentLabel: String {
        guard let level = appStore.todaySubjectiveRecovery?.fatigueLevel else {
            return L10n.string("health_meals_body_ai.7453de0b9772", fallback: "未記録。体感も準備度の根拠に加えられます")
        }
        return Self.options.first(where: { $0.level == level })?.label ?? L10n.string("health_meals_body_ai.212c4e7d1abf", fallback: "記録済み")
    }

    private static let options: [(level: Int, label: String)] = [
        (1, L10n.string("health_meals_body_ai.5de8b517bd37", fallback: "かなり元気")),
        (2, L10n.string("health_meals_body_ai.5ea6be912e53", fallback: "元気")),
        (3, L10n.string("health_meals_body_ai.9058a5e61c76", fallback: "普通")),
        (4, L10n.string("health_meals_body_ai.7ca7c3729503", fallback: "疲れている")),
        (5, L10n.string("health_meals_body_ai.73102423924e", fallback: "かなり疲れている"))
    ]
}

private struct SubjectiveRecoveryEditor: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    let options: [(level: Int, label: String)]

    @State private var recordedAt = Date()
    @State private var fatigueLevel = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        L10n.string("health_meals_body_ai.c5deaf60f00d", fallback: "記録日"),
                        selection: $recordedAt,
                        in: RecordDatePolicy.allowedRange(),
                        displayedComponents: .date
                    )
                    Picker(L10n.string("health_meals_body_ai.e2d8e613515a", fallback: "体感疲労"), selection: $fatigueLevel) {
                        ForEach(options, id: \.level) { option in
                            Text(option.label).tag(option.level)
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.e2d8e613515a", fallback: "体感疲労"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) {
                        appStore.saveSubjectiveFatigue(fatigueLevel, at: RecordDatePolicy.normalizedDay(recordedAt))
                        dismiss()
                    }
                }
            }
            .onAppear {
                recordedAt = RecordDatePolicy.normalizedDay(recordedAt)
            }
        }
    }
}

private struct SleepDetailsCard: View {
    let summary: SleepSummary?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.string("health_meals_body_ai.5c0466a0d2f3", fallback: "昨夜の睡眠"), systemImage: "bed.double.fill")
                        .font(.headline)
                    Spacer()
                    Text(summary?.qualityScore.map { L10n.string("health_meals_body_ai.e7357be38956", fallback: "品質 {{value1}}", values: [String(describing: $0)]) } ?? L10n.string("health_meals_body_ai.98a1dbcbd2a8", fallback: "品質 -"))
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.purple)
                }

                if let summary {
                    if let startedAt = summary.startedAt, let endedAt = summary.endedAt {
                        Text("\(startedAt.formatted(date: .abbreviated, time: .shortened))〜\(endedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                            .accessibilityIdentifier("sleepPeriod")
                    }

                    HStack {
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.b2312d1c369b", fallback: "合計"), value: hours(summary.totalHours))
                        Divider()
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.fe80292cae43", fallback: "深い"), value: hours(summary.deepHours))
                        Divider()
                        CompactHealthValue(title: "REM", value: hours(summary.remHours))
                        Divider()
                        CompactHealthValue(
                            title: L10n.string("health_meals_body_ai.5849c46696c5", fallback: "中途覚醒"),
                            value: summary.interruptionCount.map { L10n.string("health_meals_body_ai.f20927268a6d", fallback: "{{value1}}回", values: [String(describing: $0)]) } ?? "-"
                        )
                    }
                    .frame(height: 44)

                    Text(summary.hasDetailedStages
                         ? L10n.string("health_meals_body_ai.cf65f2670394", fallback: "時間、深い睡眠、REM、中途覚醒から端末内で算出した参考スコアです。")
                         : L10n.string("health_meals_body_ai.0cce0b71e377", fallback: "睡眠ステージが未取得のため、合計時間を中心にした参考スコアです。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text(L10n.string("health_meals_body_ai.4060e1dc437c", fallback: "睡眠データは未取得です。未取得値を0として評価しません。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .accessibilityIdentifier("sleepDetailsCard")
    }

    private func hours(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + L10n.string("health_meals_body_ai.041784c72fcd", fallback: "時間") } ?? "-"
    }
}

private struct HealthKitDisclosureCard: View {
    let accessState: HealthAccessState
    let onRequest: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemImage: "heart.text.square.fill", tint: AppTheme.critical)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Apple Health (HealthKit)")
                            .font(.title3.bold())
                        Text(accessState.title)
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Text(healthReadDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(healthWriteDescription)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                if accessState == .notRequested || accessState == .deniedOrLimited || isFailed {
                    Button(action: onRequest) {
                        Label(L10n.string("health_meals_body_ai.8601f9d25351", fallback: "連携する項目を選ぶ"), systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(accessState == .unavailable)
                    .accessibilityIdentifier("requestHealthAuthorizationButton")
                }
            }
        }
        .accessibilityIdentifier("healthKitDisclosureCard")
    }

    private var isFailed: Bool {
        if case .failed = accessState { return true }
        return false
    }

    private var healthReadDescription: String {
        localizedInfoValue(
            key: "NSHealthShareUsageDescription",
            fallback: "BodyMode reads steps, activity, sleep, and heart-rate data from Apple Health to show condition and training trends."
        )
    }

    private var healthWriteDescription: String {
        localizedInfoValue(
            key: "NSHealthUpdateUsageDescription",
            fallback: "BodyMode saves Apple Watch workouts and body measurements to Apple Health."
        )
    }

    private func localizedInfoValue(key: String, fallback: String) -> String {
        (Bundle.main.localizedInfoDictionary?[key] as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String)
            ?? fallback
    }
}

private struct ReadinessCard: View {
    let assessment: ReadinessAssessment

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("health_meals_body_ai.3b27f523d6f1", fallback: "今日の準備度"))
                            .font(.headline)
                        Text(assessment.level.title)
                            .font(.title2.bold())
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Text(assessment.score.map { "\($0)" } ?? "-")
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }

                Text(assessment.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)

                ForEach(assessment.factors.prefix(4), id: \.self) { factor in
                    Label(factor, systemImage: "circle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .symbolRenderingMode(.hierarchical)
                }

                Text(L10n.string("health_meals_body_ai.b20615d50842", fallback: "医療的な判定ではなく、取得できたデータの傾向をまとめた参考値です。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityIdentifier("readinessCard")
    }

    private var tint: Color {
        switch assessment.level {
        case .good: AppTheme.positive
        case .moderate: AppTheme.blue
        case .recover: AppTheme.orange
        }
    }
}

private struct ActivityProgressCard: View {
    let progress: ActivityProgress?
    let steps: Double?
    let distance: Double?
    let flights: Double?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("health_meals_body_ai.24d95a3f7ec3", fallback: "今日のアクティビティ"))
                    .font(.headline)

                HStack(spacing: 16) {
                    ActivityProgressRings(progress: progress)
                        .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 9) {
                        ActivityLegendRow(
                            title: L10n.string("health_meals_body_ai.8519bcac90ba", fallback: "ムーブ"),
                            value: progressText(progress?.moveKilocalories, goal: progress?.moveGoalKilocalories, unit: "kcal"),
                            tint: AppTheme.accent
                        )
                        ActivityLegendRow(
                            title: L10n.string("health_meals_body_ai.76a8b51a97f4", fallback: "運動"),
                            value: progressText(progress?.exerciseMinutes, goal: progress?.exerciseGoalMinutes, unit: L10n.string("health_meals_body_ai.4e07f10d1d26", fallback: "分")),
                            tint: AppTheme.secondaryAccent
                        )
                        ActivityLegendRow(
                            title: L10n.string("health_meals_body_ai.482b99ee1cad", fallback: "スタンド"),
                            value: progressText(progress?.standHours, goal: progress?.standGoalHours, unit: L10n.string("health_meals_body_ai.041784c72fcd", fallback: "時間")),
                            tint: AppTheme.tertiaryAccent
                        )
                    }
                }

                Divider()

                HStack {
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.a64954d4ecda", fallback: "歩数"), value: steps.map { Int($0).formatted() } ?? "-")
                    Divider()
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.ea2c7c407ab9", fallback: "距離"), value: distance.map { AppFormatters.distance(kilometers: $0) } ?? "-")
                    Divider()
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.dc7014ca09f7", fallback: "上った階数"), value: flights.map { Int($0).formatted() } ?? "-")
                }
                .frame(height: 42)
            }
        }
        .accessibilityIdentifier("activityProgressCard")
    }

    private func progressText(_ value: Double?, goal: Double?, unit: String) -> String {
        guard let value else { return L10n.string("health_meals_body_ai.e7150bf221cb", fallback: "未取得") }
        let current = Int(value).formatted()
        guard let goal, goal > 0 else { return "\(current) \(unit)" }
        return "\(current) / \(Int(goal).formatted()) \(unit)"
    }
}

private struct ActivityProgressRings: View {
    let progress: ActivityProgress?

    var body: some View {
        ZStack {
            ring(progress: ratio(progress?.moveKilocalories, progress?.moveGoalKilocalories), tint: AppTheme.accent, inset: 0)
            ring(progress: ratio(progress?.exerciseMinutes, progress?.exerciseGoalMinutes), tint: AppTheme.secondaryAccent, inset: 12)
            ring(progress: ratio(progress?.standHours, progress?.standGoalHours), tint: AppTheme.tertiaryAccent, inset: 24)
        }
    }

    private func ring(progress: Double, tint: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(tint.opacity(0.16), lineWidth: 8)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func ratio(_ value: Double?, _ goal: Double?) -> Double {
        guard let value, let goal, goal > 0 else { return 0 }
        return value / goal
    }
}

private struct ActivityLegendRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                Text(value)
                    .font(.footnote.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct CompactHealthValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecoveryMetricsSection: View {
    let snapshot: DailyHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("health_meals_body_ai.5602244ffb3a", fallback: "回復"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                HealthMetricCard(title: L10n.string("health_meals_body_ai.8878e4c5b97f", fallback: "睡眠"), value: format(snapshot.sleepHours, suffix: L10n.string("health_meals_body_ai.041784c72fcd", fallback: "時間"), digits: 1), icon: "bed.double.fill", tint: AppTheme.purple)
                HealthMetricCard(title: L10n.string("health_meals_body_ai.d8323e0a0c6c", fallback: "安静時心拍"), value: format(snapshot.restingHeartRate?.value, suffix: "bpm", digits: 0), icon: "heart.fill", tint: AppTheme.critical)
                HealthMetricCard(title: "HRV", value: format(snapshot.heartRateVariabilityMilliseconds?.value, suffix: "ms", digits: 0), icon: "waveform.path.ecg", tint: AppTheme.blue)
                HealthMetricCard(title: L10n.string("health_meals_body_ai.f7e084d26a4b", fallback: "呼吸数"), value: format(snapshot.respiratoryRate?.value, suffix: L10n.string("health_meals_body_ai.3bbe0e753f4d", fallback: "回/分"), digits: 1), icon: "lungs.fill", tint: AppTheme.tertiaryAccent)
                HealthMetricCard(title: L10n.string("health_meals_body_ai.17557a3ae4cb", fallback: "手首皮膚温"), value: format(snapshot.wristTemperatureCelsius?.value, suffix: "°C", digits: 1), icon: "thermometer.medium", tint: AppTheme.orange)
                HealthMetricCard(title: L10n.string("health_meals_body_ai.7a101c9b7ca5", fallback: "心拍回復"), value: format(snapshot.heartRateRecovery?.value, suffix: "bpm", digits: 0), icon: "arrow.down.heart.fill", tint: AppTheme.positive)
            }

            if let current = snapshot.respiratoryRate?.value,
               let baseline = snapshot.baselines.respiratoryRate {
                Text(L10n.string("health_meals_body_ai.aec3a3416e01", fallback: "呼吸数は14日平均 {{value1}}回/分に対して {{value2}}回/分", values: [String(describing: baseline.formatted(.number.precision(.fractionLength(1)))), String(describing: signed(current - baseline))]))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    private func format(_ value: Double?, suffix: String, digits: Int) -> String {
        guard let value else { return L10n.string("health_meals_body_ai.e7150bf221cb", fallback: "未取得") }
        return value.formatted(.number.precision(.fractionLength(digits))) + " " + suffix
    }

    private func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct EnergyBalanceCard: View {
    let mealCalories: Double
    let activeEnergy: Double?
    let restingEnergy: Double?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.string("health_meals_body_ai.7267f6d11355", fallback: "今日のエネルギー収支"), systemImage: "scale.3d")
                    .font(.headline)

                HStack {
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.131d65f0becd", fallback: "食事記録"), value: mealCalories > 0 ? "\(Int(mealCalories)) kcal" : L10n.string("health_meals_body_ai.220b27fdd9bd", fallback: "未記録"))
                    Divider()
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.ceb6a96246a0", fallback: "推定消費"), value: expenditure.map { "\(Int($0)) kcal" } ?? L10n.string("health_meals_body_ai.e7150bf221cb", fallback: "未取得"))
                    Divider()
                    CompactHealthValue(title: L10n.string("health_meals_body_ai.26b7c3fa5902", fallback: "差"), value: balance.map(formatBalance) ?? "-")
                }
                .frame(height: 44)

                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityIdentifier("energyBalanceCard")
    }

    private var expenditure: Double? {
        guard activeEnergy != nil || restingEnergy != nil else { return nil }
        return (activeEnergy ?? 0) + (restingEnergy ?? 0)
    }

    private var balance: Double? {
        guard mealCalories > 0, let expenditure else { return nil }
        return mealCalories - expenditure
    }

    private func formatBalance(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + Int(value).formatted() + " kcal"
    }

    private var detailText: String {
        guard mealCalories > 0 else { return L10n.string("health_meals_body_ai.14d3b7bdf022", fallback: "食事を記録すると、Apple Healthの安静時・活動時エネルギーとの差を確認できます。") }
        guard expenditure != nil else { return L10n.string("health_meals_body_ai.08b433c8bd55", fallback: "Healthの消費エネルギーが未取得です。食事記録だけは保存されています。") }
        return L10n.string("health_meals_body_ai.aa2ce729eb99", fallback: "食事写真の量推定とHealthの消費エネルギーはいずれも参考値です。1日だけでなく週平均で確認してください。")
    }
}

private struct EnvironmentMetricsSection: View {
    let snapshot: DailyHealthSnapshot

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: audioIcon, tint: audioTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("health_meals_body_ai.0ea53fa197bc", fallback: "環境音への曝露"))
                        .font(.headline)
                    Text(audioValue)
                        .font(.subheadline.bold())
                    Text(audioGuidance)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
    }

    private var audioValue: String {
        guard let value = snapshot.environmentalAudioExposureDecibels?.value else { return L10n.string("health_meals_body_ai.e7150bf221cb", fallback: "未取得") }
        return value.formatted(.number.precision(.fractionLength(0))) + " dBA"
    }

    private var audioGuidance: String {
        guard let value = snapshot.environmentalAudioExposureDecibels?.value else {
            return L10n.string("health_meals_body_ai.6e80ae6c0ed4", fallback: "Noiseアプリなどが記録した最新値。未取得は0にしません。")
        }
        if value >= 90 {
            return L10n.string("health_meals_body_ai.1d91da8d5c82", fallback: "高い曝露の記録です。音源から離れる、音量を下げる、聴覚保護具を使う判断材料にしてください。")
        }
        if value >= 85 {
            return L10n.string("health_meals_body_ai.755d793eabaa", fallback: "曝露が高めです。長時間続く場合は音量や滞在時間を抑える参考にしてください。")
        }
        return L10n.string("health_meals_body_ai.9a20afa66267", fallback: "直近値は85 dBA未満です。継続時間とあわせて確認してください。")
    }

    private var audioTint: Color {
        guard let value = snapshot.environmentalAudioExposureDecibels?.value else { return AppTheme.mutedInk }
        return value >= 85 ? AppTheme.orange : AppTheme.positive
    }

    private var audioIcon: String {
        (snapshot.environmentalAudioExposureDecibels?.value ?? 0) >= 85
            ? "ear.trianglebadge.exclamationmark"
            : "ear.badge.waveform"
    }
}

private struct OutdoorRouteCard: View {
    let route: OutdoorWorkoutRouteSummary?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Label(routeTitle, systemImage: routeIcon)
                    .font(.headline)

                if let route, route.points.count >= 2 {
                    Map(initialPosition: .region(region(for: route.points))) {
                        MapPolyline(coordinates: route.points.map(coordinate))
                            .stroke(AppTheme.accent, lineWidth: 5)
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)

                    HStack {
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.ea2c7c407ab9", fallback: "距離"), value: route.distanceKilometers.map { AppFormatters.distance(kilometers: $0) } ?? "-")
                        Divider()
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.a25deb7e2e15", fallback: "平均速度"), value: route.averageSpeedKilometersPerHour.map { AppFormatters.speed(kilometersPerHour: $0) } ?? "-")
                        Divider()
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.6e0a448de044", fallback: "高度差"), value: value(route.elevationGainMeters, suffix: "m", digits: 0))
                        Divider()
                        CompactHealthValue(title: L10n.string("health_meals_body_ai.041784c72fcd", fallback: "時間"), value: duration(route.durationSeconds))
                    }
                    .frame(height: 44)

                    Text(L10n.string("health_meals_body_ai.fa00a282a7bd", fallback: "Apple Healthに保存された最新の屋外ルートを表示しています。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text(L10n.string("health_meals_body_ai.7dca00d85e73", fallback: "ルート付きの屋外運動が見つかると、距離・速度・高度差を表示します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .accessibilityIdentifier("outdoorRouteCard")
    }

    private var routeTitle: String {
        guard let route else {
            return L10n.string("health_meals_body_ai.83b4c9182250", fallback: "最新の屋外運動")
        }
        return L10n.string(
            "health_meals_body_ai.outdoor_route_title",
            fallback: "最新の{{value1}}",
            values: [route.activity.localizedName]
        )
    }

    private var routeIcon: String {
        switch route?.activity {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case nil: "map"
        }
    }

    private func coordinate(_ point: OutdoorRoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private func region(for points: [OutdoorRoutePoint]) -> MKCoordinateRegion {
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.005, (latitudes.max() ?? 0) - (latitudes.min() ?? 0) + 0.003),
                longitudeDelta: max(0.005, (longitudes.max() ?? 0) - (longitudes.min() ?? 0) + 0.003)
            )
        )
    }

    private func value(_ value: Double?, suffix: String, digits: Int) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(digits))) + " " + suffix } ?? "-"
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return L10n.string("health_meals_body_ai.e3e557893569", fallback: "{{value1}}分", values: [String(describing: minutes)])
    }
}

private struct HealthMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HealthDataQualityCard: View {
    let snapshot: DailyHealthSnapshot

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("health_meals_body_ai.3b5b91c5855d", fallback: "データ品質"), systemImage: "checkmark.shield")
                    .font(.headline)
                Text(L10n.string("health_meals_body_ai.8ba8689d50cb", fallback: "取得できた主要項目 (availableCount)/8"))
                    .font(.subheadline.bold())
                Text(L10n.string("health_meals_body_ai.097c8a28c9eb", fallback: "Apple Watchを適度にフィットさせて装着し、睡眠中も着用すると回復指標がそろいやすくなります。値がない項目は推測で補完しません。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    private var availableCount: Int {
        [
            snapshot.sleepHours,
            snapshot.restingHeartRate?.value,
            snapshot.heartRateVariabilityMilliseconds?.value,
            snapshot.respiratoryRate?.value,
            snapshot.wristTemperatureCelsius?.value,
            snapshot.heartRateRecovery?.value,
            snapshot.steps,
            snapshot.activeEnergyKilocalories
        ].compactMap { $0 }.count
    }
}

private struct GymVisitCard: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var gymLocationManager: GymLocationManager

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "mappin.and.ellipse", tint: AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appStore.gymLocation?.name ?? L10n.string("health_meals_body_ai.cf3d3dbdd0f6", fallback: "ジム訪問"))
                            .font(.headline)
                        Text(visitSummary)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Spacer()
                    if gymLocationManager.isAtGym {
                        Text(L10n.string("health_meals_body_ai.fb5cc9f666a3", fallback: "滞在中"))
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.positive)
                    }
                }

                Text(gymLocationManager.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                if appStore.gymLocation == nil {
                    Button {
                        gymLocationManager.registerCurrentLocationAsGym()
                    } label: {
                        Label(
                            gymLocationManager.isLocating ? L10n.string("health_meals_body_ai.2e02f2290c71", fallback: "現在地を確認中") : L10n.string("health_meals_body_ai.a83447b11951", fallback: "現在地をマイジムに登録"),
                            systemImage: "location.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(gymLocationManager.isLocating)
                    .accessibilityIdentifier("registerCurrentGymButton")
                } else {
                    HStack {
                        Button {
                            if gymLocationManager.isAtGym {
                                gymLocationManager.manualCheckOut()
                            } else {
                                gymLocationManager.manualCheckIn()
                            }
                        } label: {
                            Label(
                                gymLocationManager.isAtGym ? L10n.string("health_meals_body_ai.fe32e34696b6", fallback: "退出") : L10n.string("health_meals_body_ai.8ed8b430d180", fallback: "到着"),
                                systemImage: gymLocationManager.isAtGym ? "figure.walk.departure" : "figure.walk.arrival"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(gymLocationManager.isAtGym ? AppTheme.orange : AppTheme.positive)
                        .accessibilityIdentifier("manualGymCheckButton")

                        Button {
                            gymLocationManager.enableBackgroundVisitDetection()
                        } label: {
                            Label(L10n.string("health_meals_body_ai.1bb8b3868e2e", fallback: "自動検知"), systemImage: "location.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("enableGymDetectionButton")
                    }

                    Button(role: .destructive) {
                        gymLocationManager.removeGymLocation()
                    } label: {
                        Label(L10n.string("health_meals_body_ai.506832e552c5", fallback: "登録場所を削除"), systemImage: "trash")
                    }
                    .font(.footnote)
                }
            }
        }
        .accessibilityIdentifier("gymVisitCard")
    }

    private var visitSummary: String {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let weeklyCount = appStore.gymVisits.filter { $0.arrivedAt >= weekStart }.count
        if let distance = gymLocationManager.currentDistanceMeters {
            return L10n.string("health_meals_body_ai.b1113781c4b4", fallback: "今週 {{value1}}回・現在 {{value2}}m", values: [String(describing: weeklyCount), String(describing: Int(distance))])
        }
        return L10n.string("health_meals_body_ai.16365b4215a3", fallback: "今週 {{value1}}回・累計 {{value2}}回", values: [String(describing: weeklyCount), String(describing: appStore.gymVisits.count)])
    }
}

#Preview {
    NavigationStack {
        ConditionDashboardView()
            .environmentObject(AppStore())
            .environmentObject(HealthDataManager())
            .environmentObject(GymLocationManager())
    }
}
