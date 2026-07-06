import Charts
import SwiftUI

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
                    ContentUnavailableView("分析データがありません", systemImage: "chart.bar.xaxis")
                } else {
                    Chart(weeklyVolumes) { item in
                        BarMark(
                            x: .value("週", item.weekStart, unit: .weekOfYear),
                            y: .value("ボリューム", item.volume)
                        )
                    }
                    .chartYAxisLabel(appStore.userProfile.weightUnit.displayName)
                    .frame(height: 220)
                }
            }

            Section("週別") {
                ForEach(weeklyVolumes.reversed()) { item in
                    LabeledContent(
                        AppFormatters.shortDate.string(from: item.weekStart),
                        value: "\(AppFormatters.volume(item.volume, unit: appStore.userProfile.weightUnit)) / \(item.sessionCount)回"
                    )
                }
            }
        }
        .navigationTitle("週次ボリューム")
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
                            Label("\(summary.count)回", systemImage: "number")
                            Label(AppFormatters.volume(summary.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("種目別履歴")
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
                    SummaryMetric(title: "実施回数", value: "\(records.count)")
                    Spacer()
                    SummaryMetric(title: "自己ベスト", value: bestSet.map { AppFormatters.weight($0.actualWeight, unit: appStore.userProfile.weightUnit) } ?? "-")
                    Spacer()
                    SummaryMetric(title: "推定1RM", value: estimatedOneRepMax.map { AppFormatters.weight($0, unit: appStore.userProfile.weightUnit) } ?? "-")
                }
                .padding(.vertical, 8)
            }

            Section("重量推移") {
                if records.isEmpty {
                    ContentUnavailableView("履歴がありません", systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    Chart(records) { record in
                        LineMark(
                            x: .value("日付", record.date),
                            y: .value("最大重量", record.maxWeight)
                        )
                        PointMark(
                            x: .value("日付", record.date),
                            y: .value("最大重量", record.maxWeight)
                        )
                    }
                    .chartYAxisLabel(appStore.userProfile.weightUnit.displayName)
                    .frame(height: 220)
                }
            }

            Section("履歴") {
                ForEach(records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppFormatters.shortDate.string(from: record.date))
                            .font(.headline)
                        Text("\(AppFormatters.weight(record.maxWeight, unit: appStore.userProfile.weightUnit)) / \(AppFormatters.volume(record.exercise.totalVolume, unit: appStore.userProfile.weightUnit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
