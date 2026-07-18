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
                                Text("トレーニング分析")
                                    .font(.headline)
                                Text("負荷・セット品質・心拍回復・停滞候補")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sensorTrainingAnalysisLink")

                if healthDataManager.accessState == .notRequested {
                    HealthPermissionCard {
                        Task { await healthDataManager.requestAuthorization() }
                    }
                } else {
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
        .navigationTitle("コンディション")
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
                .accessibilityLabel("Healthデータを更新")
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
                        Label("コンディション", systemImage: "heart.text.square")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Text(healthDataManager.accessState == .notRequested ? "Apple Healthを連携" : assessment.level.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(tint)
                    Text(healthDataManager.accessState == .notRequested ? "睡眠・回復・活動量をまとめて確認できます。" : assessment.summary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2)
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

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "gauge.with.dots.needle.33percent", tint: AppTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日の体感疲労")
                        .font(.headline)
                    Text(currentLabel)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                }
                Spacer()
                Menu {
                    ForEach(Self.options, id: \.level) { option in
                        Button(option.label) {
                            appStore.saveSubjectiveFatigue(option.level)
                        }
                    }
                } label: {
                    Label("記録", systemImage: "dial.medium")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("subjectiveFatigueMenu")
            }
        }
    }

    private var currentLabel: String {
        guard let level = appStore.todaySubjectiveRecovery?.fatigueLevel else {
            return "未記録。体感も準備度の根拠に加えられます"
        }
        return Self.options.first(where: { $0.level == level })?.label ?? "記録済み"
    }

    private static let options: [(level: Int, label: String)] = [
        (1, "かなり元気"),
        (2, "元気"),
        (3, "普通"),
        (4, "疲れている"),
        (5, "かなり疲れている")
    ]
}

private struct SleepDetailsCard: View {
    let summary: SleepSummary?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("昨夜の睡眠", systemImage: "bed.double.fill")
                        .font(.headline)
                    Spacer()
                    Text(summary?.qualityScore.map { "品質 \($0)" } ?? "品質 -")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.purple)
                }

                if let summary {
                    HStack {
                        CompactHealthValue(title: "合計", value: hours(summary.totalHours))
                        Divider()
                        CompactHealthValue(title: "深い", value: hours(summary.deepHours))
                        Divider()
                        CompactHealthValue(title: "REM", value: hours(summary.remHours))
                        Divider()
                        CompactHealthValue(
                            title: "中途覚醒",
                            value: summary.interruptionCount.map { "\($0)回" } ?? "-"
                        )
                    }
                    .frame(height: 44)

                    Text(summary.hasDetailedStages
                         ? "時間、深い睡眠、REM、中途覚醒から端末内で算出した参考スコアです。"
                         : "睡眠ステージが未取得のため、合計時間を中心にした参考スコアです。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text("睡眠データは未取得です。未取得値を0として評価しません。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .accessibilityIdentifier("sleepDetailsCard")
    }

    private func hours(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "時間" } ?? "-"
    }
}

private struct HealthPermissionCard: View {
    let onRequest: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                IconBadge(systemImage: "heart.text.square.fill", tint: AppTheme.critical)
                Text("Apple Healthと連携")
                    .font(.title3.bold())
                Text("歩数、アクティビティ、睡眠、安静時心拍、HRV、呼吸数、手首皮膚温を必要な項目ごとに許可できます。許可しない項目は未取得として扱い、手入力はそのまま使えます。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)

                Button(action: onRequest) {
                    Label("連携する項目を選ぶ", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .accessibilityIdentifier("requestHealthAuthorizationButton")
            }
        }
    }
}

private struct ReadinessCard: View {
    let assessment: ReadinessAssessment

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日の準備度")
                            .font(.headline)
                        Text(assessment.level.title)
                            .font(.title2.bold())
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Text(assessment.score.map { "\($0)" } ?? "-")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }

                Text(assessment.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)

                ForEach(assessment.factors.prefix(4), id: \.self) { factor in
                    Label(factor, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                        .symbolRenderingMode(.hierarchical)
                }

                Text("医療的な判定ではなく、取得できたデータの傾向をまとめた参考値です。")
                    .font(.caption2)
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
                Text("今日のアクティビティ")
                    .font(.headline)

                HStack(spacing: 16) {
                    ActivityProgressRings(progress: progress)
                        .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 9) {
                        ActivityLegendRow(
                            title: "ムーブ",
                            value: progressText(progress?.moveKilocalories, goal: progress?.moveGoalKilocalories, unit: "kcal"),
                            tint: AppTheme.accent
                        )
                        ActivityLegendRow(
                            title: "運動",
                            value: progressText(progress?.exerciseMinutes, goal: progress?.exerciseGoalMinutes, unit: "分"),
                            tint: AppTheme.secondaryAccent
                        )
                        ActivityLegendRow(
                            title: "スタンド",
                            value: progressText(progress?.standHours, goal: progress?.standGoalHours, unit: "時間"),
                            tint: AppTheme.tertiaryAccent
                        )
                    }
                }

                Divider()

                HStack {
                    CompactHealthValue(title: "歩数", value: steps.map { Int($0).formatted() } ?? "-")
                    Divider()
                    CompactHealthValue(title: "距離", value: distance.map { $0.formatted(.number.precision(.fractionLength(1))) + " km" } ?? "-")
                    Divider()
                    CompactHealthValue(title: "上った階数", value: flights.map { Int($0).formatted() } ?? "-")
                }
                .frame(height: 42)
            }
        }
        .accessibilityIdentifier("activityProgressCard")
    }

    private func progressText(_ value: Double?, goal: Double?, unit: String) -> String {
        guard let value else { return "未取得" }
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
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedInk)
                Text(value)
                    .font(.caption.bold())
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
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecoveryMetricsSection: View {
    let snapshot: DailyHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("回復")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                HealthMetricCard(title: "睡眠", value: format(snapshot.sleepHours, suffix: "時間", digits: 1), icon: "bed.double.fill", tint: AppTheme.purple)
                HealthMetricCard(title: "安静時心拍", value: format(snapshot.restingHeartRate?.value, suffix: "bpm", digits: 0), icon: "heart.fill", tint: AppTheme.critical)
                HealthMetricCard(title: "HRV", value: format(snapshot.heartRateVariabilityMilliseconds?.value, suffix: "ms", digits: 0), icon: "waveform.path.ecg", tint: AppTheme.blue)
                HealthMetricCard(title: "呼吸数", value: format(snapshot.respiratoryRate?.value, suffix: "回/分", digits: 1), icon: "lungs.fill", tint: AppTheme.tertiaryAccent)
                HealthMetricCard(title: "手首皮膚温", value: format(snapshot.wristTemperatureCelsius?.value, suffix: "°C", digits: 1), icon: "thermometer.medium", tint: AppTheme.orange)
                HealthMetricCard(title: "心拍回復", value: format(snapshot.heartRateRecovery?.value, suffix: "bpm", digits: 0), icon: "arrow.down.heart.fill", tint: AppTheme.positive)
            }

            if let current = snapshot.respiratoryRate?.value,
               let baseline = snapshot.baselines.respiratoryRate {
                Text("呼吸数は14日平均 \(baseline.formatted(.number.precision(.fractionLength(1))))回/分に対して \(signed(current - baseline))回/分")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    private func format(_ value: Double?, suffix: String, digits: Int) -> String {
        guard let value else { return "未取得" }
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
                Label("今日のエネルギー収支", systemImage: "scale.3d")
                    .font(.headline)

                HStack {
                    CompactHealthValue(title: "食事記録", value: mealCalories > 0 ? "\(Int(mealCalories)) kcal" : "未記録")
                    Divider()
                    CompactHealthValue(title: "推定消費", value: expenditure.map { "\(Int($0)) kcal" } ?? "未取得")
                    Divider()
                    CompactHealthValue(title: "差", value: balance.map(formatBalance) ?? "-")
                }
                .frame(height: 44)

                Text(detailText)
                    .font(.caption2)
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
        guard mealCalories > 0 else { return "食事を記録すると、Apple Healthの安静時・活動時エネルギーとの差を確認できます。" }
        guard expenditure != nil else { return "Healthの消費エネルギーが未取得です。食事記録だけは保存されています。" }
        return "食事写真の量推定とHealthの消費エネルギーはいずれも参考値です。1日だけでなく週平均で確認してください。"
    }
}

private struct EnvironmentMetricsSection: View {
    let snapshot: DailyHealthSnapshot

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: audioIcon, tint: audioTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("環境音への曝露")
                        .font(.headline)
                    Text(audioValue)
                        .font(.subheadline.bold())
                    Text(audioGuidance)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
    }

    private var audioValue: String {
        guard let value = snapshot.environmentalAudioExposureDecibels?.value else { return "未取得" }
        return value.formatted(.number.precision(.fractionLength(0))) + " dBA"
    }

    private var audioGuidance: String {
        guard let value = snapshot.environmentalAudioExposureDecibels?.value else {
            return "Noiseアプリなどが記録した最新値。未取得は0にしません。"
        }
        if value >= 90 {
            return "高い曝露の記録です。音源から離れる、音量を下げる、聴覚保護具を使う判断材料にしてください。"
        }
        if value >= 85 {
            return "曝露が高めです。長時間続く場合は音量や滞在時間を抑える参考にしてください。"
        }
        return "直近値は85 dBA未満です。継続時間とあわせて確認してください。"
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
                Label("最新の屋外ランニング", systemImage: "figure.run")
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
                        CompactHealthValue(title: "距離", value: value(route.distanceKilometers, suffix: "km", digits: 1))
                        Divider()
                        CompactHealthValue(title: "平均速度", value: value(route.averageSpeedKilometersPerHour, suffix: "km/h", digits: 1))
                        Divider()
                        CompactHealthValue(title: "高度差", value: value(route.elevationGainMeters, suffix: "m", digits: 0))
                        Divider()
                        CompactHealthValue(title: "時間", value: duration(route.durationSeconds))
                    }
                    .frame(height: 44)

                    Text("Apple Healthに保存された最新のランニングルートを表示しています。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text("ルート付きの屋外ランニングが見つかると、距離・速度・高度差を表示します。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .accessibilityIdentifier("outdoorRunningRouteCard")
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
        return "\(minutes)分"
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
                    .font(.caption)
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
                Label("データ品質", systemImage: "checkmark.shield")
                    .font(.headline)
                Text("取得できた主要項目 (availableCount)/8")
                    .font(.subheadline.bold())
                Text("Apple Watchを適度にフィットさせて装着し、睡眠中も着用すると回復指標がそろいやすくなります。値がない項目は推測で補完しません。")
                    .font(.caption)
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
                        Text(appStore.gymLocation?.name ?? "ジム訪問")
                            .font(.headline)
                        Text(visitSummary)
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Spacer()
                    if gymLocationManager.isAtGym {
                        Text("滞在中")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.positive)
                    }
                }

                Text(gymLocationManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedInk)

                if appStore.gymLocation == nil {
                    Button {
                        gymLocationManager.registerCurrentLocationAsGym()
                    } label: {
                        Label(
                            gymLocationManager.isLocating ? "現在地を確認中" : "現在地をマイジムに登録",
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
                                gymLocationManager.isAtGym ? "退出" : "到着",
                                systemImage: gymLocationManager.isAtGym ? "figure.walk.departure" : "figure.walk.arrival"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(gymLocationManager.isAtGym ? AppTheme.orange : AppTheme.positive)
                        .accessibilityIdentifier("manualGymCheckButton")

                        Button {
                            gymLocationManager.enableBackgroundVisitDetection()
                        } label: {
                            Label("自動検知", systemImage: "location.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("enableGymDetectionButton")
                    }

                    Button(role: .destructive) {
                        gymLocationManager.removeGymLocation()
                    } label: {
                        Label("登録場所を削除", systemImage: "trash")
                    }
                    .font(.caption)
                }
            }
        }
        .accessibilityIdentifier("gymVisitCard")
    }

    private var visitSummary: String {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let weeklyCount = appStore.gymVisits.filter { $0.arrivedAt >= weekStart }.count
        if let distance = gymLocationManager.currentDistanceMeters {
            return "今週 \(weeklyCount)回・現在 \(Int(distance))m"
        }
        return "今週 \(weeklyCount)回・累計 \(appStore.gymVisits.count)回"
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
