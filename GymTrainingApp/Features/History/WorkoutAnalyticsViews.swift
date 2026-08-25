import Charts
import SwiftUI

enum HistoryComparisonWindow: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .week: L10n.string("training.history_range_week", fallback: "1週間")
        case .month: L10n.string("training.history_range_month", fallback: "1か月")
        case .threeMonths: L10n.string("training.history_range_three_months", fallback: "3か月")
        case .sixMonths: L10n.string("training.history_range_six_months", fallback: "6か月")
        case .year: L10n.string("training.history_range_year", fallback: "1年")
        }
    }

    var groupingComponent: Calendar.Component {
        rawValue <= 30 ? .day : .weekOfYear
    }

    var movingAverageBinCount: Int {
        rawValue <= 30 ? 7 : 4
    }
}

struct HistoryPeriodSummary: Equatable {
    let sessionCount: Int
    let totalVolume: Double

    var averageVolumePerSession: Double {
        guard sessionCount > 0 else { return 0 }
        return totalVolume / Double(sessionCount)
    }
}

struct HistoryPeriodComparison {
    let current: HistoryPeriodSummary
    let previous: HistoryPeriodSummary
    let points: [HistoryVolumePoint]

    static func make(
        sessions: [WorkoutSession],
        window: HistoryComparisonWindow,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> HistoryPeriodComparison {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let currentStart = calendar.date(byAdding: .day, value: -window.rawValue, to: end) ?? end
        let previousStart = calendar.date(byAdding: .day, value: -window.rawValue, to: currentStart) ?? currentStart
        let currentSessions = sessions.filter { $0.startedAt >= currentStart && $0.startedAt < end }
        let previousSessions = sessions.filter { $0.startedAt >= previousStart && $0.startedAt < currentStart }

        let grouped = Dictionary(grouping: currentSessions) { session in
            periodStart(for: session.startedAt, component: window.groupingComponent, calendar: calendar)
        }
        let starts = periodStarts(
            from: currentStart,
            to: end,
            component: window.groupingComponent,
            calendar: calendar
        )
        let volumes = starts.map { start in
            grouped[start, default: []].reduce(0) { $0 + $1.totalVolume }
        }
        let points = starts.indices.map { index in
            let lowerBound = max(0, index - window.movingAverageBinCount + 1)
            let sample = volumes[lowerBound...index]
            return HistoryVolumePoint(
                date: starts[index],
                volume: volumes[index],
                movingAverage: sample.reduce(0, +) / Double(sample.count)
            )
        }

        return HistoryPeriodComparison(
            current: summary(for: currentSessions),
            previous: summary(for: previousSessions),
            points: points
        )
    }

    private static func summary(for sessions: [WorkoutSession]) -> HistoryPeriodSummary {
        HistoryPeriodSummary(
            sessionCount: sessions.count,
            totalVolume: sessions.reduce(0) { $0 + $1.totalVolume }
        )
    }

    private static func periodStart(
        for date: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> Date {
        if component == .day { return calendar.startOfDay(for: date) }
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func periodStarts(
        from start: Date,
        to end: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> [Date] {
        var result: [Date] = []
        var cursor = periodStart(for: start, component: component, calendar: calendar)
        while cursor < end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
}

struct HistoryVolumePoint: Identifiable, Equatable {
    let date: Date
    let volume: Double
    let movingAverage: Double

    var id: Date { date }
}

struct HistoryPeriodComparisonView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var window: HistoryComparisonWindow = .month

    private var comparison: HistoryPeriodComparison {
        .make(sessions: appStore.workoutHistory, window: window)
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.string("training.history_comparison_period", fallback: "比較期間"), selection: $window) {
                    ForEach(HistoryComparisonWindow.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("historyComparisonRangePicker")
            }

            Section(L10n.string("training.history_previous_period_section", fallback: "前の同期間との比較")) {
                HistoryComparisonMetricRow(
                    title: L10n.string("training.6e8b76e77952", fallback: "実施回数"),
                    current: Double(comparison.current.sessionCount),
                    previous: Double(comparison.previous.sessionCount),
                    value: comparison.current.sessionCount.formatted()
                )
                HistoryComparisonMetricRow(
                    title: L10n.string("training.922870c3ac56", fallback: "総ボリューム"),
                    current: comparison.current.totalVolume,
                    previous: comparison.previous.totalVolume,
                    value: AppFormatters.volume(comparison.current.totalVolume, unit: appStore.userProfile.weightUnit)
                )
                HistoryComparisonMetricRow(
                    title: L10n.string("training.history_average_volume", fallback: "1回あたり平均"),
                    current: comparison.current.averageVolumePerSession,
                    previous: comparison.previous.averageVolumePerSession,
                    value: AppFormatters.volume(comparison.current.averageVolumePerSession, unit: appStore.userProfile.weightUnit)
                )
            }

            Section(L10n.string("training.history_volume_trend", fallback: "ボリューム推移")) {
                if comparison.current.sessionCount == 0 {
                    ContentUnavailableView(
                        L10n.string("training.3294eead40cd", fallback: "履歴がありません"),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    Chart(comparison.points) { point in
                        BarMark(
                            x: .value(L10n.string("training.3f9f5b28c76e", fallback: "日付"), point.date),
                            y: .value(L10n.string("training.b43a38f668a7", fallback: "ボリューム"), point.volume)
                        )
                        .foregroundStyle(AppTheme.accent.opacity(0.25))

                        LineMark(
                            x: .value(L10n.string("training.3f9f5b28c76e", fallback: "日付"), point.date),
                            y: .value(L10n.string("training.history_moving_average", fallback: "移動平均"), point.movingAverage)
                        )
                        .foregroundStyle(AppTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    .chartYAxisLabel(appStore.userProfile.weightUnit.displayName)
                    .frame(height: 240)

                    Text(
                        window.groupingComponent == .day
                            ? L10n.string("training.history_seven_day_average", fallback: "線は7日移動平均")
                            : L10n.string("training.history_four_week_average", fallback: "線は4週移動平均")
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("training.history_period_comparison", fallback: "期間比較"))
    }
}

private struct HistoryComparisonMetricRow: View {
    let title: String
    let current: Double
    let previous: Double
    let value: String

    private var changeText: String {
        guard previous != 0 else {
            return current == 0 ? "0%" : L10n.string("training.history_new_activity", fallback: "新規")
        }
        let percentage = (current - previous) / abs(previous)
        return percentage.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Text(changeText)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel(L10n.string("training.history_previous_period_change", fallback: "前期比 {{value1}}", values: [changeText]))
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeeklyVolumeView: View {
    @EnvironmentObject private var appStore: AppStore

    private var weeklyVolumes: [WeeklyVolume] {
        Dictionary(grouping: appStore.workoutHistory, by: { Calendar.current.startOfWeek(for: $0.startedAt) })
            .map { weekStart, sessions in
                WeeklyVolume(weekStart: weekStart, volume: sessions.reduce(0) { $0 + $1.totalVolume }, sessionCount: sessions.count)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        List {
            Section {
                if weeklyVolumes.isEmpty {
                    ContentUnavailableView(L10n.string("training.1a7841dadb88", fallback: "分析データがありません"), systemImage: "chart.bar.xaxis")
                } else {
                    Chart(weeklyVolumes) { item in
                        BarMark(
                            x: .value(L10n.string("training.a9629f892deb", fallback: "週"), item.weekStart, unit: .weekOfYear),
                            y: .value(L10n.string("training.b43a38f668a7", fallback: "ボリューム"), item.volume)
                        )
                    }
                    .chartYAxisLabel(appStore.userProfile.weightUnit.displayName)
                    .frame(height: 220)
                }
            }

            Section(L10n.string("training.902c06373dc5", fallback: "週別")) {
                ForEach(weeklyVolumes.reversed()) { item in
                    LabeledContent(
                        AppFormatters.shortDate.string(from: item.weekStart),
                        value: L10n.string("training.22db347214b9", fallback: "{{value1}} / {{value2}}回", values: [String(describing: AppFormatters.volume(item.volume, unit: appStore.userProfile.weightUnit)), String(describing: item.sessionCount)])
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("training.5efc858e0f9e", fallback: "週次ボリューム"))
    }
}

struct ExerciseHistoryListView: View {
    @EnvironmentObject private var appStore: AppStore

    private var summaries: [ExerciseSummary] {
        Dictionary(grouping: appStore.workoutHistory.flatMap(\.exercises), by: { $0.exercise.name })
            .map { name, exercises in
                let completedSets = exercises.flatMap { $0.sets }.filter(\.isCompleted)
                let bestSet = completedSets.max { $0.volume < $1.volume }
                let totalVolume = completedSets.reduce(0) { $0 + $1.volume }
                return ExerciseSummary(name: name, totalVolume: totalVolume, bestSet: bestSet, count: exercises.count)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(summaries) { summary in
                NavigationLink {
                    ExerciseHistoryDetailView(exerciseName: summary.name)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.name)
                            .font(.headline)
                        HStack(spacing: 10) {
                            Label(L10n.string("training.b76f27bcd552", fallback: "{{value1}}回", values: [String(describing: summary.count)]), systemImage: "number")
                            Label(AppFormatters.volume(summary.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass")
                        }
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("training.f3db21504894", fallback: "種目別履歴"))
    }
}

struct ExerciseHistoryDetailView: View {
    @EnvironmentObject private var appStore: AppStore
    let exerciseName: String

    private var records: [ExerciseRecord] {
        appStore.workoutHistory.compactMap { session in
            guard let exercise = session.exercises.first(where: { $0.exercise.name == exerciseName }) else {
                return nil
            }
            return ExerciseRecord(date: session.startedAt, exercise: exercise)
        }
        .sorted { $0.date < $1.date }
    }

    private var completedSets: [WorkoutSet] {
        records.flatMap { $0.exercise.sets }.filter(\.isCompleted)
    }

    private var bestSet: WorkoutSet? {
        completedSets.max { $0.volume < $1.volume }
    }

    private var estimatedOneRepMax: Double? {
        guard let set = completedSets.max(by: { estimateOneRepMax($0) < estimateOneRepMax($1) }) else {
            return nil
        }
        return estimateOneRepMax(set)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    SummaryMetric(title: L10n.string("training.6e8b76e77952", fallback: "実施回数"), value: "\(records.count)")
                    Spacer()
                    SummaryMetric(title: L10n.string("training.ed189402693b", fallback: "自己ベスト"), value: bestSet.map { AppFormatters.weight($0.actualWeight, unit: appStore.userProfile.weightUnit) } ?? "-")
                    Spacer()
                    SummaryMetric(title: L10n.string("training.f57690abba57", fallback: "推定1RM"), value: estimatedOneRepMax.map { AppFormatters.weight($0, unit: appStore.userProfile.weightUnit) } ?? "-")
                }
                .padding(.vertical, 8)
            }

            Section(L10n.string("training.7d51185bb279", fallback: "重量推移")) {
                if records.isEmpty {
                    ContentUnavailableView(L10n.string("training.3294eead40cd", fallback: "履歴がありません"), systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    Chart(records) { record in
                        LineMark(
                            x: .value(L10n.string("training.3f9f5b28c76e", fallback: "日付"), record.date),
                            y: .value(L10n.string("training.cdbec49a500c", fallback: "最大重量"), record.maxWeight)
                        )
                        PointMark(
                            x: .value(L10n.string("training.3f9f5b28c76e", fallback: "日付"), record.date),
                            y: .value(L10n.string("training.cdbec49a500c", fallback: "最大重量"), record.maxWeight)
                        )
                    }
                    .chartYAxisLabel(appStore.userProfile.weightUnit.displayName)
                    .frame(height: 220)
                }
            }

            Section(L10n.string("training.6157f8cd2251", fallback: "履歴")) {
                ForEach(records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppFormatters.shortDate.string(from: record.date))
                            .font(.headline)
                        Text("\(AppFormatters.weight(record.maxWeight, unit: appStore.userProfile.weightUnit)) / \(AppFormatters.volume(record.exercise.totalVolume, unit: appStore.userProfile.weightUnit))")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(exerciseName)
    }

    private func estimateOneRepMax(_ set: WorkoutSet) -> Double {
        set.actualWeight * (1 + Double(set.actualReps) / 30)
    }
}

private struct WeeklyVolume: Identifiable {
    let weekStart: Date
    let volume: Double
    let sessionCount: Int

    var id: Date { weekStart }
}

private struct ExerciseSummary: Identifiable {
    let name: String
    let totalVolume: Double
    let bestSet: WorkoutSet?
    let count: Int

    var id: String { name }
}

private struct ExerciseRecord: Identifiable {
    let date: Date
    let exercise: WorkoutExercise

    var id: Date { date }

    var maxWeight: Double {
        exercise.sets.filter(\.isCompleted).map(\.actualWeight).max() ?? 0
    }
}

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
