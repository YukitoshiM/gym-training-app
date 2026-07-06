import Charts
import SwiftUI

struct BodyMetricDetailView: View {
    @EnvironmentObject private var appStore: AppStore
    let kind: BodyMetricKind

    @State private var isShowingEntryEditor = false
    @State private var isShowingGoalEditor = false

    private var entries: [BodyMetricEntry] {
        appStore.bodyMetricEntries(for: kind)
    }

    private var chartEntries: [BodyMetricEntry] {
        entries.sorted { $0.recordedAt < $1.recordedAt }
    }

    private var weeklyAverages: [BodyMetricWeeklyAverage] {
        Dictionary(grouping: entries, by: { Calendar.current.startOfWeekForBodyMetric(for: $0.recordedAt) })
            .map { weekStart, entries in
                BodyMetricWeeklyAverage(
                    weekStart: weekStart,
                    value: entries.reduce(0) { $0 + $1.value } / Double(entries.count),
                    count: entries.count
                )
            }
            .sorted { $0.weekStart > $1.weekStart }
    }

    private var latestEntry: BodyMetricEntry? {
        entries.first
    }

    private var goal: BodyMetricGoal {
        appStore.bodyMetricGoal(for: kind)
    }

    var body: some View {
        List {
            Section {
                CurrentBodyMetricSummary(kind: kind, latestEntry: latestEntry, goal: goal)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section("推移") {
                if chartEntries.isEmpty {
                    ContentUnavailableView {
                        Label("記録がありません", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("値を追加すると、ここに推移が表示されます。")
                    }
                    .frame(minHeight: 180)
                } else {
                    Chart(chartEntries) { entry in
                        LineMark(
                            x: .value("日付", entry.recordedAt),
                            y: .value(kind.displayName, entry.value)
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日付", entry.recordedAt),
                            y: .value(kind.displayName, entry.value)
                        )
                    }
                    .chartYAxisLabel(kind.unit)
                    .frame(height: 220)
                    .accessibilityIdentifier("bodyMetricChart-\(kind.rawValue)")
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            Section("週次平均") {
                if weeklyAverages.isEmpty {
                    Text("週次平均はまだありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weeklyAverages) { average in
                        LabeledContent(
                            AppFormatters.shortDate.string(from: average.weekStart),
                            value: "\(AppFormatters.metricValue(average.value, unit: kind.unit)) / \(average.count)件"
                        )
                    }
                }
            }
            .listRowBackground(AppTheme.cardBackground)

            Section("記録") {
                if entries.isEmpty {
                    Text("まだ記録がありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(AppFormatters.metricValue(entry.value, unit: kind.unit))
                                    .font(.headline)
                                Spacer()
                                Text(AppFormatters.shortDate.string(from: entry.recordedAt))
                                    .foregroundStyle(.secondary)
                            }

                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        appStore.deleteBodyMetricEntries(kind: kind, at: offsets)
                    }
                }
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(kind.displayName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingGoalEditor = true
                } label: {
                    Image(systemName: "target")
                }
                .accessibilityLabel("目標設定")

                Button {
                    isShowingEntryEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("KPIを記録")
                .accessibilityIdentifier("addBodyMetricEntryButton")
            }
        }
        .sheet(isPresented: $isShowingEntryEditor) {
            BodyMetricEntryEditorView(kind: kind)
        }
        .sheet(isPresented: $isShowingGoalEditor) {
            BodyMetricGoalEditorView(kind: kind)
        }
    }
}

private struct BodyMetricWeeklyAverage: Identifiable {
    let weekStart: Date
    let value: Double
    let count: Int

    var id: Date { weekStart }
}

private extension Calendar {
    func startOfWeekForBodyMetric(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

private struct CurrentBodyMetricSummary: View {
    let kind: BodyMetricKind
    let latestEntry: BodyMetricEntry?
    let goal: BodyMetricGoal

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(kind.displayName, systemImage: kind.systemImage)
                        .font(.headline)

                    Spacer()

                    Text(goal.direction.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                }

                if let latestEntry {
                    Text(AppFormatters.metricValue(latestEntry.value, unit: kind.unit))
                        .font(.largeTitle.bold())

                    if let targetValue = goal.targetValue {
                        VStack(spacing: 8) {
                            LabeledContent("目標", value: AppFormatters.metricValue(targetValue, unit: kind.unit))

                            if let delta = goal.delta(from: latestEntry.value) {
                                LabeledContent("目標差", value: deltaText(delta))
                            }

                            if let rate = goal.achievementRate(from: latestEntry.value) {
                                LabeledContent("達成率", value: AppFormatters.percent(rate))
                            }
                        }
                        .font(.subheadline)
                    } else {
                        Text("目標値を設定すると、差分と達成率を表示します。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("未記録")
                        .font(.title2.bold())
                    Text("最初の値を記録すると、推移と目標差分を確認できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deltaText(_ delta: Double) -> String {
        let sign = delta > 0 ? "+" : ""
        return sign + AppFormatters.metricValue(delta, unit: kind.unit)
    }
}

#Preview {
    NavigationStack {
        BodyMetricDetailView(kind: .bodyWeight)
            .environmentObject(AppStore())
    }
}
