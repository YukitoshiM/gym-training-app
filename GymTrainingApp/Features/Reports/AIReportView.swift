import SwiftUI

struct AIReportView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isGenerating = false
    @State private var isCheckingConnection = false
    @State private var errorPresentation: AIErrorPresentation?
    @State private var connectionNotice: AIReportConnectionNotice?

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    var body: some View {
        List {
            Section {
                if let connectionNotice {
                    AIReportConnectionNoticeCard(notice: connectionNotice)
                }

                Button {
                    generateWeeklyReport()
                } label: {
                    Label(isGenerating ? "週次レポート生成中" : "週次AIコメントを生成", systemImage: "sparkles")
                }
                .disabled(isGenerating || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("generateWeeklyAIReportButton")

                Button {
                    checkConnection()
                } label: {
                    Label(isCheckingConnection ? "接続確認中" : "ローカルLLM接続を確認", systemImage: "network")
                }
                .disabled(isCheckingConnection || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("checkAIConnectionFromReportButton")

                if !appStore.aiSettings.isEnabled {
                    Text("設定でAI機能がオフです。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("接続できない場合でも、記録済みデータは消えません。手動記録を続けたまま、あとでAIコメントだけ生成できます。")
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

            if let errorPresentation {
                Section("AIエラー") {
                    AIErrorRecoveryCard(presentation: errorPresentation)
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
        errorPresentation = nil
        connectionNotice = nil

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
                    errorPresentation = AIClientError.presentation(for: error)
                    isGenerating = false
                }
            }
        }
    }

    private func checkConnection() {
        isCheckingConnection = true
        errorPresentation = nil
        connectionNotice = nil

        Task {
            do {
                let health = try await LocalAIClient(settings: appStore.aiSettings).health()
                await MainActor.run {
                    connectionNotice = AIReportConnectionNotice(health: health)
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    errorPresentation = AIClientError.presentation(for: error)
                    isCheckingConnection = false
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

private struct AIReportConnectionNotice {
    var title: String
    var detail: String
    var recovery: String?
    var tint: Color
    var systemImage: String

    init(health: AIHealthResponse) {
        if health.isReady {
            title = "接続OK"
            detail = "Ollama \(health.model) で週次コメントを生成できます。"
            recovery = health.message
            tint = .green
            systemImage = "checkmark.circle.fill"
        } else if !health.ollamaReachable {
            title = "Ollama未接続"
            detail = "local_llm_server は起動していますが、Ollamaに接続できません。"
            recovery = health.message ?? "Mac miniで `ollama serve` を起動してください。"
            tint = AppTheme.orange
            systemImage = "exclamationmark.triangle.fill"
        } else {
            title = "モデル未取得"
            detail = "Ollamaは起動していますが、\(health.model) が見つかりません。"
            recovery = health.message ?? "`ollama pull \(health.model)` を実行してください。"
            tint = AppTheme.orange
            systemImage = "exclamationmark.triangle.fill"
        }
    }
}

private struct AIReportConnectionNoticeCard: View {
    let notice: AIReportConnectionNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice.title, systemImage: notice.systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(notice.tint)

            Text(notice.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.ink)

            if let recovery = notice.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiReportConnectionNotice")
    }
}

private struct AIErrorRecoveryCard: View {
    let presentation: AIErrorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.message, systemImage: "xmark.octagon.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.red)

            if let recovery = presentation.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("記録は保存されたままです。あとで接続できる状態になってから、もう一度生成できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiErrorRecoveryCard")
    }
}

#Preview {
    NavigationStack {
        AIReportView()
            .environmentObject(AppStore())
    }
}
