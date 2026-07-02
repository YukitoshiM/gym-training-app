import SwiftUI

struct BodyMetricListView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        List {
            Section("主要KPI") {
                ForEach(BodyMetricKind.allCases) { kind in
                    NavigationLink {
                        BodyMetricDetailView(kind: kind)
                    } label: {
                        BodyMetricRow(
                            kind: kind,
                            latestEntry: appStore.latestBodyMetricEntry(for: kind),
                            goal: appStore.bodyMetricGoal(for: kind)
                        )
                    }
                    .accessibilityIdentifier("bodyMetricRow-\(kind.rawValue)")
                }
            }

            Section("記録の見方") {
                Label("目標との差分と達成率をKPIごとに確認できます。", systemImage: "target")
                Label("体重や腹囲のように日々ぶれる数値は、推移で見る前提です。", systemImage: "chart.line.uptrend.xyaxis")
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle("身体KPI")
    }
}

private struct BodyMetricRow: View {
    let kind: BodyMetricKind
    let latestEntry: BodyMetricEntry?
    let goal: BodyMetricGoal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayName)
                    .font(.headline)

                if let latestEntry {
                    Text(AppFormatters.shortDate.string(from: latestEntry.recordedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未記録")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let latestEntry {
                    Text(AppFormatters.metricValue(latestEntry.value, unit: kind.unit))
                        .font(.headline)
                } else {
                    Text("-")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if let latestEntry,
                   let delta = goal.delta(from: latestEntry.value) {
                    Text(deltaText(delta))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("目標未設定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deltaText(_ delta: Double) -> String {
        let sign = delta > 0 ? "+" : ""
        return "目標差 \(sign)\(AppFormatters.metricValue(delta, unit: kind.unit))"
    }
}

#Preview {
    NavigationStack {
        BodyMetricListView()
            .environmentObject(AppStore())
    }
}
