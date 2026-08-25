import SwiftUI

struct BodyMetricListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var pendingEstimate: BodyMetricEstimate?

    private var estimates: [BodyMetricEstimate] {
        BodyMetricEstimateService.estimates(entries: appStore.bodyMetricEntries, profile: appStore.userProfile)
    }

    var body: some View {
        List {
            Section(L10n.string("health_meals_body_ai.d9eb6553376d", fallback: "主要KPI")) {
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
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("bodyMetricRow-\(kind.rawValue)")
                }
            }

            Section(L10n.string("health_meals_body_ai.9b10a7bc0507", fallback: "記録の見方")) {
                Label(L10n.string("health_meals_body_ai.b4469d69cea6", fallback: "目標との差分と達成率をKPIごとに確認できます。"), systemImage: "target")
                Label(L10n.string("health_meals_body_ai.b695d78f775e", fallback: "体重や腹囲のように日々ぶれる数値は、推移で見る前提です。"), systemImage: "chart.line.uptrend.xyaxis")
            }
            .foregroundStyle(AppTheme.mutedInk)

            if !estimates.isEmpty {
                Section {
                    ForEach(estimates) { estimate in
                        Button {
                            pendingEstimate = estimate
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(estimate.kind.displayName, systemImage: "waveform.path.ecg")
                                        .font(.headline)
                                    Spacer()
                                    Text(L10n.string("release_delta.estimated", fallback: "推定"))
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.warning)
                                }
                                Text(estimate.rangeText)
                                    .font(.title3.bold())
                                Text(estimate.rationale)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.string("release_delta.reference_estimate", fallback: "参考推定"))
                } footer: {
                    Text(L10n.string("release_delta.estimate_disclaimer", fallback: "参考範囲であり測定値ではありません。タップして内容を確認した場合だけ保存します。"))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("health_meals_body_ai.639d445a88af", fallback: "身体KPI"))
        .confirmationDialog(
            L10n.string("release_delta.save_estimate_title", fallback: "参考推定を保存しますか？"),
            isPresented: Binding(
                get: { pendingEstimate != nil },
                set: { if !$0 { pendingEstimate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("release_delta.save_as_estimate", fallback: "推定として保存")) {
                if let pendingEstimate {
                    appStore.saveBodyMetricEntry(pendingEstimate.approvedEntry())
                }
                pendingEstimate = nil
            }
            Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル"), role: .cancel) {
                pendingEstimate = nil
            }
        } message: {
            Text(pendingEstimate.map {
                L10n.string("release_delta.estimate_confirmation", fallback: "{{value1}} {{value2}}。実測値は上書きしません。", values: [$0.kind.displayName, $0.rangeText])
            } ?? "")
        }
    }
}

private struct BodyMetricRow: View {
    let kind: BodyMetricKind
    let latestEntry: BodyMetricEntry?
    let goal: BodyMetricGoal

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: kind.systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.displayName)
                        .font(.headline)

                    if let latestEntry {
                        Text(AppFormatters.shortDate.string(from: latestEntry.recordedAt))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        Text(L10n.string("health_meals_body_ai.220b27fdd9bd", fallback: "未記録"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let latestEntry {
                        Text(AppFormatters.metricValue(latestEntry.value, unit: kind.unit))
                            .font(.headline)
                        if latestEntry.isEstimated == true {
                            Text(L10n.string("release_delta.estimated", fallback: "推定"))
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.warning)
                        }
                    } else {
                        Text("-")
                            .font(.headline)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    if let latestEntry,
                       let delta = goal.delta(from: latestEntry.value) {
                        Text(deltaText(delta))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    } else {
                        Text(L10n.string("health_meals_body_ai.f972a5f65765", fallback: "目標未設定"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func deltaText(_ delta: Double) -> String {
        let sign = delta > 0 ? "+" : ""
        return L10n.string("health_meals_body_ai.b8b04a1e8e72", fallback: "目標差 {{value1}}{{value2}}", values: [String(describing: sign), String(describing: AppFormatters.metricValue(delta, unit: kind.unit))])
    }

    private var tint: Color {
        switch kind {
        case .bodyWeight: AppTheme.blue
        case .waist: AppTheme.orange
        case .bodyFatPercentage: AppTheme.purple
        }
    }
}

#Preview {
    NavigationStack {
        BodyMetricListView()
            .environmentObject(AppStore())
    }
}
