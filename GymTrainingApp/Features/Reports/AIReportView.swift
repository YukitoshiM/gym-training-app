import SwiftUI

struct AIReportView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    var body: some View {
        List {
            Section {
                Button {
                    generateWeeklyReport()
                } label: {
                    Label(isGenerating ? "週次レポート生成中" : "週次AIコメントを生成", systemImage: "sparkles")
                }
                .disabled(isGenerating || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("generateWeeklyAIReportButton")

                if !appStore.aiSettings.isEnabled {
                    Text("設定でAI機能がオフです。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestWeeklyInsight {
                Section("最新レポート") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppFormatters.shortDateTime.string(from: latestWeeklyInsight.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(latestWeeklyInsight.outputComment)
                            .font(.headline)

                        Text(latestWeeklyInsight.actionSuggestion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("入力データ要約") {
                    Text(latestWeeklyInsight.inputSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("AIレポートはまだありません", systemImage: "sparkles")
                    } description: {
                        Text("身体KPI、食事、体型写真、筋トレ履歴から週次コメントを作成します。")
                    }
                    .frame(minHeight: 180)
                }
            }

            if let errorMessage {
                Section("AIエラー") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("履歴") {
                ForEach(appStore.aiInsights.filter { $0.insightType == .weekly }) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppFormatters.shortDateTime.string(from: insight.date))
                            .font(.headline)
                        Text(insight.actionSuggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("AIレポート")
    }

    private func generateWeeklyReport() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let response = try await LocalAIClient(settings: appStore.aiSettings)
                    .generateWeeklyReport(payload: weeklyPayload())
                await MainActor.run {
                    appStore.saveAIInsight(
                        AIInsight(
                            insightType: .weekly,
                            inputSummary: response.inputSummary,
                            outputComment: response.outputComment,
                            actionSuggestion: response.actionSuggestion
                        )
                    )
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func weeklyPayload() -> WeeklyReportRequest {
        WeeklyReportRequest(
            profileGoal: appStore.userProfile.goalType.displayName,
            bodyLogs: appStore.bodyMetricEntries.prefix(20).map {
                "\($0.kind.displayName): \(AppFormatters.metricValue($0.value, unit: $0.kind.unit)) \(AppFormatters.shortDate.string(from: $0.recordedAt))"
            },
            meals: appStore.mealEntries.prefix(20).map {
                "\($0.mealType.displayName) \($0.name): \(AppFormatters.calories($0.calories)) P\(AppFormatters.grams($0.protein)) F\(AppFormatters.grams($0.fat)) C\(AppFormatters.grams($0.carbs))"
            },
            workouts: appStore.workoutHistory.prefix(12).map {
                "\($0.title): \(AppFormatters.volume($0.totalVolume, unit: appStore.userProfile.weightUnit)) 達成率 \(AppFormatters.percent($0.achievementRate))"
            },
            bodyPhotos: appStore.bodyPhotoEntries.prefix(12).map {
                "\($0.angle.displayName): \($0.aiComment?.summary ?? $0.memo)"
            }
        )
    }
}

#Preview {
    NavigationStack {
        AIReportView()
            .environmentObject(AppStore())
    }
}
