import SwiftUI

struct AIReportView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @State private var isGenerating = false
    @State private var isCheckingConnection = false
    @State private var errorPresentation: AIErrorPresentation?
    @State private var connectionNotice: AIReportConnectionNotice?
    @State private var pendingMonthlyReview: MonthlyReviewDraft?

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    private var latestMonthlyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .monthly }
    }

    var body: some View {
        List {
            Section("担当コーチ") {
                CoachIdentityView(
                    persona: appStore.userProfile.coachPersona,
                    role: appStore.userProfile.coachType.displayName,
                    detail: appStore.userProfile.coachType.characteristic,
                    avatarSize: 64
                )
                .accessibilityIdentifier("activeCoachCard")
            }

            Section("AIトレーナー") {
                NavigationLink {
                    AITrainerChatView()
                } label: {
                    HStack(spacing: 10) {
                        CoachAvatarView(persona: appStore.userProfile.coachPersona, size: 38)
                        Text("\(appStore.userProfile.coachPersona.displayName)に相談")
                    }
                }
                .accessibilityIdentifier("aiTrainerChatLink")

                NavigationLink {
                    CoachMemoryListView()
                } label: {
                    HStack {
                        Label("保存した記憶", systemImage: "brain.head.profile")
                        Spacer()
                        Text(appStore.coachMemories.count.formatted())
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }
                .accessibilityIdentifier("coachMemoryListLink")
            }

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
                    generateMonthlyReview()
                } label: {
                    Label(isGenerating ? "月次レビュー生成中" : "月次レビュー案を作成", systemImage: "calendar.badge.clock")
                }
                .disabled(isGenerating || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("generateMonthlyAIReviewButton")

                Button {
                    checkConnection()
                } label: {
                    Label(isCheckingConnection ? "接続確認中" : "AIサーバー接続を確認", systemImage: "network")
                }
                .disabled(isCheckingConnection || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("checkAIConnectionFromReportButton")

                if !appStore.aiSettings.isEnabled {
                    Text("設定でAI機能がオフです。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text("接続できない場合でも、記録済みデータは消えません。手動記録を続けたまま、あとでAIコメントだけ生成できます。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            if let latestWeeklyInsight {
                Section("最新レポート") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppFormatters.shortDateTime.string(from: latestWeeklyInsight.date))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)

                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: "\(appStore.userProfile.coachPersona.displayName)の振り返り"
                        )

                        Text("今週の結論")
                            .font(.subheadline.bold())
                        CoachFormattedText(content: latestWeeklyInsight.outputComment)

                        if latestWeeklyInsight.hasStructuredWeeklySections {
                            AIReportBulletSection(
                                title: "良かった点",
                                systemImage: "checkmark.circle.fill",
                                tint: AppTheme.positive,
                                items: latestWeeklyInsight.goodPoints ?? []
                            )
                            AIReportBulletSection(
                                title: "課題",
                                systemImage: "exclamationmark.triangle.fill",
                                tint: AppTheme.warning,
                                items: latestWeeklyInsight.challenges ?? []
                            )
                            AIReportBulletSection(
                                title: "判断の根拠",
                                systemImage: "list.clipboard.fill",
                                tint: AppTheme.blue,
                                items: latestWeeklyInsight.rationales ?? []
                            )
                            AIReportBulletSection(
                                title: "次の行動",
                                systemImage: "arrow.right.circle.fill",
                                tint: AppTheme.accent,
                                items: latestWeeklyInsight.nextActions ?? []
                            )
                            if latestWeeklyInsight.nextActions?.isEmpty != false {
                                Text("次の行動")
                                    .font(.subheadline.bold())
                                CoachFormattedText(content: latestWeeklyInsight.actionSuggestion)
                            }
                        } else {
                            Text("次の行動")
                                .font(.subheadline.bold())
                            CoachFormattedText(content: latestWeeklyInsight.actionSuggestion)
                        }

                        Text("入力データの傾向をもとにした提案で、医療上の診断ではありません。体調や痛みに不安がある場合は専門家へ相談してください。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .padding(.vertical, 4)
                }

                Section("入力データ要約") {
                    Text(latestWeeklyInsight.inputSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("\(appStore.userProfile.coachPersona.displayName)のレポートはまだありません", systemImage: "chart.line.text.clipboard")
                    } description: {
                        Text("身体KPI、食事、体型写真、筋トレ履歴から週次コメントを作成します。")
                    }
                    .frame(minHeight: 180)
                }
            }

            if let latestMonthlyInsight {
                Section("保存した月次レビュー") {
                    VStack(alignment: .leading, spacing: 10) {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: "\(appStore.userProfile.coachPersona.displayName)の月次レビュー"
                        )
                        CoachFormattedText(content: latestMonthlyInsight.outputComment)
                        CoachFormattedText(content: latestMonthlyInsight.actionSuggestion)
                    }
                }
            }

            if let errorPresentation {
                Section("AIエラー") {
                    AIErrorRecoveryCard(presentation: errorPresentation)
                }
            }

            Section("履歴") {
                ForEach(appStore.aiInsights.filter { [.weekly, .monthly].contains($0.insightType) }) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(insight.insightType == .monthly ? "月次" : "週次")・\(AppFormatters.shortDateTime.string(from: insight.date))")
                            .font(.headline)
                        Text(insight.actionSuggestion)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                            .lineLimit(2)
                    }
                }
            }

            Section("AI送信履歴") {
                if appStore.aiTransmissionHistory.isEmpty {
                    Text("送信履歴はありません")
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    ForEach(appStore.aiTransmissionHistory) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(AppFormatters.shortDateTime.string(from: record.sentAt))
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(statusTitle(record.status))
                                    .font(.footnote.bold())
                                    .foregroundStyle(statusTint(record.status))
                            }
                            Text(record.sharedCategories.joined(separator: "、").ifEmpty("共有項目なし"))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                            Text("\(record.itemCount)件・\(record.purpose)")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                    }
                    .onDelete(perform: appStore.deleteAITransmissionHistory)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("\(appStore.userProfile.coachPersona.displayName)のレポート")
        .sheet(item: $pendingMonthlyReview) { draft in
            MonthlyReviewConfirmationView(draft: draft) { approved in
                appStore.saveAIInsight(
                    AIInsight(
                        insightType: .monthly,
                            inputSummary: approved.inputSummary,
                            outputComment: approved.outputComment,
                            actionSuggestion: approved.actionSuggestion,
                            goodPoints: approved.goodPoints,
                            challenges: approved.challenges,
                            rationales: approved.rationales,
                            nextActions: approved.nextActions
                    )
                )
                pendingMonthlyReview = nil
            }
        }
    }

    private func generateWeeklyReport() {
        isGenerating = true
        errorPresentation = nil
        connectionNotice = nil

        let payload = weeklyPayload()
        let record = AITransmissionRecord(
            purpose: "\(appStore.userProfile.coachType.displayName)・週次レポート",
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames,
            itemCount: payload.bodyLogs.count
                + payload.meals.count
                + payload.workouts.count
                + payload.bodyPhotos.count
                + payload.sensorMetrics.count
        )
        appStore.saveAITransmission(record)

        Task {
            do {
                let response = try await AIAPIClient(settings: appStore.aiSettings)
                    .generateWeeklyReport(payload: payload)
                await MainActor.run {
                    appStore.saveAIInsight(
                        AIInsight(
                            insightType: .weekly,
                            inputSummary: response.inputSummary,
                            outputComment: response.outputComment,
                            actionSuggestion: response.actionSuggestion,
                            goodPoints: response.goodPoints,
                            challenges: response.challenges,
                            rationales: response.rationales,
                            nextActions: response.nextActions
                        )
                    )
                    appStore.updateAITransmission(id: record.id, status: .completed)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    appStore.updateAITransmission(id: record.id, status: .failed)
                    errorPresentation = AIClientError.presentation(for: error)
                    isGenerating = false
                }
            }
        }
    }

    private func generateMonthlyReview() {
        isGenerating = true
        errorPresentation = nil
        connectionNotice = nil
        let payload = reportPayload(days: 30, maximumBodyLogs: 80, maximumMeals: 150, maximumWorkouts: 40)
        let record = AITransmissionRecord(
            purpose: "\(appStore.userProfile.coachType.displayName)・月次レビュー案",
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames,
            itemCount: payload.bodyLogs.count
                + payload.meals.count
                + payload.workouts.count
                + payload.bodyPhotos.count
                + payload.sensorMetrics.count
        )
        appStore.saveAITransmission(record)

        Task {
            do {
                let response = try await AIAPIClient(settings: appStore.aiSettings)
                    .generateMonthlyReport(payload: payload)
                await MainActor.run {
                    pendingMonthlyReview = MonthlyReviewDraft(response: response)
                    appStore.updateAITransmission(id: record.id, status: .completed)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    appStore.updateAITransmission(id: record.id, status: .failed)
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
                let health = try await AIAPIClient(settings: appStore.aiSettings).health()
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
        reportPayload(days: 7, maximumBodyLogs: 20, maximumMeals: 30, maximumWorkouts: 12)
    }

    private func reportPayload(
        days: Int,
        maximumBodyLogs: Int,
        maximumMeals: Int,
        maximumWorkouts: Int
    ) -> WeeklyReportRequest {
        let sharing = appStore.aiSettings.dataSharing
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return WeeklyReportRequest(
            profileGoal: appStore.userProfile.goalType.displayName,
            coachID: appStore.userProfile.coachType.rawValue,
            coach: AIRequestCoachContext(profile: appStore.userProfile),
            experienceLevel: appStore.userProfile.experienceLevel.rawValue,
            bodyLogs: sharing.bodyMetrics ? appStore.bodyMetricEntries.filter { $0.recordedAt >= cutoff }.prefix(maximumBodyLogs).map {
                "\($0.kind.displayName): \(AppFormatters.metricValue($0.value, unit: $0.kind.unit)) \(AppFormatters.shortDate.string(from: $0.recordedAt))"
            } : [],
            meals: sharing.meals ? appStore.mealEntries.filter { $0.recordedAt >= cutoff }.prefix(maximumMeals).map {
                "\($0.mealType.displayName) \($0.name): \(AppFormatters.calories($0.calories)) P\(AppFormatters.grams($0.protein)) F\(AppFormatters.grams($0.fat)) C\(AppFormatters.grams($0.carbs))"
            } : [],
            workouts: sharing.workouts ? appStore.workoutHistory.filter { $0.startedAt >= cutoff }.prefix(maximumWorkouts).map {
                "\($0.title): \(AppFormatters.volume($0.totalVolume, unit: appStore.userProfile.weightUnit)) 達成率 \(AppFormatters.percent($0.achievementRate))"
            } : [],
            bodyPhotos: sharing.bodyPhotos ? appStore.bodyPhotoSets.filter { $0.date >= cutoff }.prefix(12).map { set in
                let angles = set.angleEntries.map(\.angle.displayName).joined(separator: "・")
                let angleSummary = angles.isEmpty ? "写真なし" : angles
                let observation = set.analysis?.summary ?? set.memo
                return "\(set.date.formatted(date: .numeric, time: .omitted)) \(set.photoEntries.count)枚（\(angleSummary)）: \(observation)"
            } : [],
            sensorMetrics: sensorMetricsForAI
        )
    }

    private var sensorMetricsForAI: [String] {
        let sharing = appStore.aiSettings.dataSharing
        let snapshot = healthDataManager.snapshot
        var values: [String] = []

        if sharing.sleepAndRecovery, let sleep = snapshot.sleepHours {
            values.append("睡眠: \(sleep.formatted(.number.precision(.fractionLength(1))))時間")
        }
        if sharing.sleepAndRecovery, let resting = snapshot.restingHeartRate?.value {
            values.append("安静時心拍: \(Int(resting)) bpm")
        }
        if sharing.sleepAndRecovery, let hrv = snapshot.heartRateVariabilityMilliseconds?.value {
            values.append("HRV: \(Int(hrv)) ms")
        }
        if sharing.dailyActivity, let steps = snapshot.steps {
            values.append("歩数: \(Int(steps))")
        }
        if sharing.gymVisits, !appStore.gymVisits.isEmpty {
            values.append("直近7日のジム訪問: \(appStore.gymVisits.filter { $0.arrivedAt >= Date().addingTimeInterval(-7 * 86_400) }.count)回")
        }

        if sharing.workoutSensors {
            values.append(contentsOf: appStore.workoutHistory.prefix(6).compactMap { session in
                guard let sensors = session.sensorSummary else { return nil }
                let heartRate = sensors.averageHeartRate.map { "平均心拍 \(Int($0)) bpm" } ?? "心拍未取得"
                let energy = sensors.activeEnergyKilocalories.map { "消費 \(Int($0)) kcal" } ?? "消費未取得"
                return "\(session.title): \(heartRate), \(energy)"
            })
        }
        return values
    }

    private func statusTitle(_ status: AITransmissionStatus) -> String {
        switch status {
        case .sending: "送信中"
        case .completed: "完了"
        case .failed: "失敗"
        }
    }

    private func statusTint(_ status: AITransmissionStatus) -> Color {
        switch status {
        case .sending: AppTheme.blue
        case .completed: AppTheme.positive
        case .failed: AppTheme.critical
        }
    }
}

private struct MonthlyReviewDraft: Identifiable {
    let id = UUID()
    var inputSummary: String
    var outputComment: String
    var actionSuggestion: String
    var goodPoints: [String]?
    var challenges: [String]?
    var rationales: [String]?
    var nextActions: [String]?

    init(response: WeeklyReportResponse) {
        inputSummary = response.inputSummary
        outputComment = response.outputComment
        actionSuggestion = response.actionSuggestion
        goodPoints = response.goodPoints
        challenges = response.challenges
        rationales = response.rationales
        nextActions = response.nextActions
    }
}

private struct AIReportBulletSection: View {
    let title: String
    let systemImage: String
    let tint: Color
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)

                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(tint)
                        Text(item)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private extension AIInsight {
    var hasStructuredWeeklySections: Bool {
        [goodPoints, challenges, rationales, nextActions]
            .compactMap { $0 }
            .contains { !$0.isEmpty }
    }
}

private struct MonthlyReviewConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: MonthlyReviewDraft
    let onSave: (MonthlyReviewDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("入力データ") {
                    TextEditor(text: $draft.inputSummary)
                        .frame(minHeight: 90)
                }
                Section("月次レビュー") {
                    TextEditor(text: $draft.outputComment)
                        .frame(minHeight: 150)
                }
                Section("翌月目標案") {
                    TextEditor(text: $draft.actionSuggestion)
                        .frame(minHeight: 120)
                    Text("内容を確認し、必要なら修正してから保存してください。目標は自動では確定しません。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .navigationTitle("月次レビューを確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("破棄", role: .destructive) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveMonthlyAIReviewButton")
                }
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
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
            detail = "\(health.model) と補助モデルで週次コメントを生成できます。"
            recovery = health.message
            tint = AppTheme.positive
            systemImage = "checkmark.circle.fill"
        } else if !health.ollamaReachable {
            title = "補助モデル未接続"
            detail = "APIサーバーは応答していますが、料理・レポートの補助モデルを利用できません。"
            recovery = health.message
            tint = AppTheme.orange
            systemImage = "exclamationmark.triangle.fill"
        } else {
            title = "AIモデル準備中"
            detail = "APIサーバーは応答していますが、必要なモデルを利用できません。"
            recovery = health.message
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
                .font(.footnote)
                .foregroundStyle(AppTheme.ink)

            if let recovery = notice.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
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
                .foregroundStyle(AppTheme.critical)

            if let recovery = presentation.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Text("記録は保存されたままです。あとで接続できる状態になってから、もう一度生成できます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiErrorRecoveryCard")
    }
}

#Preview {
    NavigationStack {
        AIReportView()
            .environmentObject(AppStore())
            .environmentObject(HealthDataManager())
    }
}
