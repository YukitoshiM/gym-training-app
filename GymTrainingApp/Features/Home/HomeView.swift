import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gym Training")
                            .font(.largeTitle.bold())
                        Text(homeSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricPill(title: "計画", value: "\(appStore.plans.count)件", systemImage: "list.bullet.rectangle", tint: AppTheme.blue)
                        MetricPill(title: "履歴", value: "\(appStore.workoutHistory.count)件", systemImage: "clock.arrow.circlepath", tint: AppTheme.orange)
                        MetricPill(title: "KPI記録", value: "\(appStore.bodyMetricEntries.count)件", systemImage: "chart.line.uptrend.xyaxis", tint: AppTheme.purple)
                        MetricPill(title: "直近達成率", value: latestAchievementText, systemImage: "target", tint: AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("身体KPI")
                                .font(.headline)
                            Spacer()
                            NavigationLink {
                                BodyMetricListView()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("身体KPIを記録する")
                            .accessibilityIdentifier("bodyMetricListLink")
                        }

                        ForEach(BodyMetricKind.allCases) { kind in
                            HStack(spacing: 12) {
                                IconBadge(systemImage: kind.systemImage, tint: metricTint(for: kind))

                                Text(kind.displayName)
                                    .font(.subheadline.weight(.medium))

                                Spacer()

                                if let latest = appStore.latestBodyMetricEntry(for: kind) {
                                    Text(AppFormatters.metricValue(latest.value, unit: kind.unit))
                                        .font(.subheadline.bold())
                                } else {
                                    Text("未記録")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))

                    CardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("できること")
                                .font(.headline)
                            Label("計画を作る", systemImage: "checkmark.circle.fill")
                            Label("計画から記録する", systemImage: "checkmark.circle.fill")
                            Label("履歴で振り返る", systemImage: "checkmark.circle.fill")
                            Label("身体KPIを記録する", systemImage: "checkmark.circle.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("ホーム")
        }
    }

    private var homeSubtitle: String {
        if let latest = appStore.workoutHistory.first {
            return "直近: \(latest.title) / 達成率 \(AppFormatters.percent(latest.achievementRate))"
        }

        return "計画、記録、KPIをひとつの流れで管理します"
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

#Preview {
    HomeView()
        .environmentObject(AppStore())
}
