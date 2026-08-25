import SwiftUI

struct AIReportView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @State private var isGenerating = false
    @State private var isCheckingConnection = false
    @State private var errorPresentation: AIErrorPresentation?
    @State private var creditAccessIssue: AICreditAccessIssue?
    @State private var creditRetryInsightType: AIInsightType?
    @State private var connectionNotice: AIReportConnectionNotice?
    @State private var pendingMonthlyReview: MonthlyReviewDraft?
    @AppStorage(ReportScheduleStore.weeklyEnabledKey) private var weeklyScheduleEnabled = false
    @AppStorage(ReportScheduleStore.weeklyWeekdayKey) private var weeklyWeekday = 2
    @AppStorage(ReportScheduleStore.monthlyEnabledKey) private var monthlyScheduleEnabled = false
    @AppStorage(ReportScheduleStore.monthlyDayKey) private var monthlyDay = 1
    @AppStorage(ReportScheduleStore.hourKey) private var scheduleHour = 20
    @AppStorage(ReportScheduleStore.minuteKey) private var scheduleMinute = 0
    @AppStorage(ReportScheduleStore.automaticAICreditUseKey) private var automaticAICreditUse = false

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    private var latestMonthlyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .monthly }
    }

    var body: some View {
        List {
            Section(L10n.string("health_meals_body_ai.d6fbb962587f", fallback: "担当コーチ")) {
                CoachIdentityView(
                    persona: appStore.userProfile.coachPersona,
                    role: appStore.userProfile.coachType.displayName,
                    detail: appStore.userProfile.coachType.characteristic,
                    avatarSize: 64
                )
                .accessibilityIdentifier("activeCoachCard")
            }

            Section(L10n.string("health_meals_body_ai.4b6c42529d18", fallback: "AIトレーナー")) {
                NavigationLink {
                    AITrainerChatView()
                } label: {
                    HStack(spacing: 10) {
                        CoachAvatarView(persona: appStore.userProfile.coachPersona, size: 38)
                        Text(L10n.string("health_meals_body_ai.ea35bda4ca72", fallback: "{{value1}}に相談", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
                    }
                }
                .accessibilityIdentifier("aiTrainerChatLink")

                NavigationLink {
                    CoachMemoryListView()
                } label: {
                    HStack {
                        Label(L10n.string("health_meals_body_ai.6ac95b24ca1e", fallback: "保存した記憶"), systemImage: "brain.head.profile")
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

                AICreditCostStatusView(feature: "weekly_report", settings: appStore.aiSettings)

                Button {
                    generateWeeklyReport()
                } label: {
                    Label(isGenerating ? L10n.string("health_meals_body_ai.07a4aa136201", fallback: "週次レポート生成中") : L10n.string("health_meals_body_ai.406d8b52c4f0", fallback: "週次AIコメントを生成"), systemImage: "sparkles")
                }
                .disabled(isGenerating || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("generateWeeklyAIReportButton")

                AICreditCostStatusView(feature: "monthly_report", settings: appStore.aiSettings)

                Button {
                    generateMonthlyReview()
                } label: {
                    Label(isGenerating ? L10n.string("health_meals_body_ai.2e56b4936c7f", fallback: "月次レビュー生成中") : L10n.string("health_meals_body_ai.400cfd92d15f", fallback: "月次レビュー案を作成"), systemImage: "calendar.badge.clock")
                }
                .disabled(isGenerating || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("generateMonthlyAIReviewButton")

                Button {
                    checkConnection()
                } label: {
                    Label(isCheckingConnection ? L10n.string("health_meals_body_ai.b981046693bf", fallback: "接続確認中") : L10n.string("health_meals_body_ai.075a3448ee9c", fallback: "AIサーバー接続を確認"), systemImage: "network")
                }
                .disabled(isCheckingConnection || !appStore.aiSettings.isEnabled)
                .accessibilityIdentifier("checkAIConnectionFromReportButton")

                if !appStore.aiSettings.isEnabled {
                    Text(L10n.string("health_meals_body_ai.7aefc85ff14d", fallback: "設定でAI機能がオフです。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    Text(L10n.string("health_meals_body_ai.eb9e09955b1e", fallback: "接続できない場合でも、記録済みデータは消えません。手動記録を続けたまま、あとでAIコメントだけ生成できます。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            Section(L10n.string("release_delta.scheduled_reports", fallback: "予約レポート")) {
                Toggle(L10n.string("release_delta.weekly_report", fallback: "週次レポート"), isOn: $weeklyScheduleEnabled)
                if weeklyScheduleEnabled {
                    Picker(L10n.string("release_delta.weekday", fallback: "曜日"), selection: $weeklyWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                        }
                    }
                }
                Toggle(L10n.string("release_delta.monthly_report", fallback: "月次レポート"), isOn: $monthlyScheduleEnabled)
                if monthlyScheduleEnabled {
                    Picker(L10n.string("release_delta.day_of_month", fallback: "日付"), selection: $monthlyDay) {
                        ForEach(1...28, id: \.self) { day in
                            Text(L10n.string("release_delta.day_value", fallback: "{{value1}}日", values: [day.formatted()])).tag(day)
                        }
                    }
                }
                if weeklyScheduleEnabled || monthlyScheduleEnabled {
                    Toggle(
                        L10n.string(
                            "ai_credit.automatic_report_credit_use",
                            fallback: "AIクレジットを使って自動分析"
                        ),
                        isOn: $automaticAICreditUse
                    )
                    Text(
                        automaticAICreditUse
                            ? L10n.string(
                                "ai_credit.automatic_report_credit_use_on",
                                fallback: "予約実行時に週次または月次レポートのクレジットを消費します。"
                            )
                            : L10n.string(
                                "ai_credit.automatic_report_credit_use_off",
                                fallback: "クレジットは消費せず、端末内の記録だけで要約します。"
                            )
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                    DatePicker(
                        L10n.string("release_delta.report_time", fallback: "通知時刻"),
                        selection: Binding(
                            get: {
                                Calendar.current.date(from: DateComponents(hour: scheduleHour, minute: scheduleMinute)) ?? Date()
                            },
                            set: {
                                scheduleHour = Calendar.current.component(.hour, from: $0)
                                scheduleMinute = Calendar.current.component(.minute, from: $0)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    Text(L10n.string("release_delta.scheduled_report_explanation", fallback: "予定時刻後に最初にアプリを開いた時、自動生成します。AIに接続できない場合も端末内の要約を残します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }

            if let latestWeeklyInsight {
                Section(L10n.string("health_meals_body_ai.922efdd3ed8a", fallback: "最新レポート")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppFormatters.shortDateTime.string(from: latestWeeklyInsight.date))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)

                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: L10n.string("health_meals_body_ai.561be95fd706", fallback: "{{value1}}の振り返り", values: [String(describing: appStore.userProfile.coachPersona.displayName)])
                        )

                        Text(L10n.string("health_meals_body_ai.df10c0112692", fallback: "今週の結論"))
                            .font(.subheadline.bold())
                        CoachFormattedText(content: latestWeeklyInsight.outputComment)

                        if latestWeeklyInsight.hasStructuredWeeklySections {
                            AIReportBulletSection(
                                title: L10n.string("health_meals_body_ai.02d8de91c3f5", fallback: "良かった点"),
                                systemImage: "checkmark.circle.fill",
                                tint: AppTheme.positive,
                                items: latestWeeklyInsight.goodPoints ?? []
                            )
                            AIReportBulletSection(
                                title: L10n.string("health_meals_body_ai.234f23b52f12", fallback: "課題"),
                                systemImage: "exclamationmark.triangle.fill",
                                tint: AppTheme.warning,
                                items: latestWeeklyInsight.challenges ?? []
                            )
                            AIReportBulletSection(
                                title: L10n.string("health_meals_body_ai.bde5657225e5", fallback: "判断の根拠"),
                                systemImage: "list.clipboard.fill",
                                tint: AppTheme.blue,
                                items: latestWeeklyInsight.rationales ?? []
                            )
                            AIReportBulletSection(
                                title: L10n.string("health_meals_body_ai.4fc4c85b1a6c", fallback: "次の行動"),
                                systemImage: "arrow.right.circle.fill",
                                tint: AppTheme.accent,
                                items: latestWeeklyInsight.nextActions ?? []
                            )
                            if latestWeeklyInsight.nextActions?.isEmpty != false {
                                Text(L10n.string("health_meals_body_ai.4fc4c85b1a6c", fallback: "次の行動"))
                                    .font(.subheadline.bold())
                                CoachFormattedText(content: latestWeeklyInsight.actionSuggestion)
                            }
                        } else {
                            Text(L10n.string("health_meals_body_ai.4fc4c85b1a6c", fallback: "次の行動"))
                                .font(.subheadline.bold())
                            CoachFormattedText(content: latestWeeklyInsight.actionSuggestion)
                        }

                        Text(L10n.string("health_meals_body_ai.2494cf2da9de", fallback: "入力データの傾向をもとにした提案で、医療上の診断ではありません。体調や痛みに不安がある場合は専門家へ相談してください。"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.string("health_meals_body_ai.8a216fc82c1c", fallback: "入力データ要約")) {
                    Text(latestWeeklyInsight.inputSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label(L10n.string("health_meals_body_ai.c61497f4f0c1", fallback: "{{value1}}のレポートはまだありません", values: [String(describing: appStore.userProfile.coachPersona.displayName)]), systemImage: "chart.line.text.clipboard")
                    } description: {
                        Text(L10n.string("health_meals_body_ai.bc649c604570", fallback: "身体KPI、食事、体型写真、筋トレ履歴から週次コメントを作成します。"))
                    }
                    .frame(minHeight: 180)
                }
            }

            if let latestMonthlyInsight {
                Section(L10n.string("health_meals_body_ai.d44c1e54131a", fallback: "保存した月次レビュー")) {
                    VStack(alignment: .leading, spacing: 10) {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: L10n.string("health_meals_body_ai.81ad045e3190", fallback: "{{value1}}の月次レビュー", values: [String(describing: appStore.userProfile.coachPersona.displayName)])
                        )
                        CoachFormattedText(content: latestMonthlyInsight.outputComment)
                        CoachFormattedText(content: latestMonthlyInsight.actionSuggestion)
                    }
                }
            }

            if let errorPresentation {
                Section(L10n.string("health_meals_body_ai.7d80eebb209d", fallback: "AIエラー")) {
                    AIErrorRecoveryCard(presentation: errorPresentation)
                }
            }

            Section(L10n.string("health_meals_body_ai.263add43eb28", fallback: "履歴")) {
                ForEach(appStore.aiInsights.filter { [.weekly, .monthly].contains($0.insightType) }) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("health_meals_body_ai.e7389b1be06a", fallback: "{{value1}}・{{value2}}", values: [String(describing: insight.insightType == .monthly ? "月次" : "週次"), String(describing: AppFormatters.shortDateTime.string(from: insight.date))]))
                            .font(.headline)
                        Text(insight.actionSuggestion)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                            .lineLimit(2)
                    }
                }
            }

            Section(L10n.string("health_meals_body_ai.4d382e329510", fallback: "AI送信履歴")) {
                if appStore.aiTransmissionHistory.isEmpty {
                    Text(L10n.string("health_meals_body_ai.fbfadfb06d6e", fallback: "送信履歴はありません"))
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
                            Text(record.sharedCategories.joined(separator: "、").ifEmpty(L10n.string("health_meals_body_ai.23efa56b6422", fallback: "共有項目なし")))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                            Text(L10n.string("health_meals_body_ai.d80a4d642fbb", fallback: "{{value1}}件・{{value2}}", values: [String(describing: record.itemCount), String(describing: record.purpose)]))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                            if record.status == .failed {
                                Text(record.failureMessage ?? L10n.string("health_meals_body_ai.a8806f356dd5", fallback: "AIサーバーに接続できません。時間をおいて再試行してください。"))
                                    .font(.footnote.bold())
                                    .foregroundStyle(AppTheme.critical)
                                if let recovery = record.recoverySuggestion {
                                    Text(recovery)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.mutedInk)
                                }
                                HStack(spacing: 12) {
                                    Label(record.canRetry == false ? L10n.string("release_delta.check_settings", fallback: "設定確認が必要") : L10n.string("release_delta.can_retry", fallback: "再試行できます"), systemImage: record.canRetry == false ? "gearshape" : "arrow.clockwise")
                                    Label(record.consumedQuota == true ? L10n.string("release_delta.quota_consumed", fallback: "利用枠を消費") : L10n.string("release_delta.quota_not_consumed", fallback: "利用枠は未消費"), systemImage: "gauge.with.dots.needle.33percent")
                                }
                                .font(.caption)
                                .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                    }
                    .onDelete(perform: appStore.deleteAITransmissionHistory)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("health_meals_body_ai.b4254a2710b4", fallback: "{{value1}}のレポート", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
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
        .aiCreditRecoverySheet(
            issue: $creditAccessIssue,
            settings: appStore.aiSettings,
            onResolved: {
                await MainActor.run {
                    errorPresentation = nil
                    if creditRetryInsightType == .monthly {
                        generateMonthlyReview()
                    } else {
                        generateWeeklyReport()
                    }
                }
            }
        )
    }

    private func generateWeeklyReport() {
        isGenerating = true
        errorPresentation = nil
        connectionNotice = nil

        let payload = weeklyPayload()
        let record = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.e8afca8b2ea3", fallback: "{{value1}}・週次レポート", values: [String(describing: appStore.userProfile.coachType.displayName)]),
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
                    appStore.recordAITransmissionFailure(id: record.id, error: error)
                    errorPresentation = AIClientError.presentation(for: error)
                    creditAccessIssue = AICreditAccessIssue(error: error)
                    creditRetryInsightType = .weekly
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
            purpose: L10n.string("health_meals_body_ai.0bc6450c1c5b", fallback: "{{value1}}・月次レビュー案", values: [String(describing: appStore.userProfile.coachType.displayName)]),
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
                    appStore.recordAITransmissionFailure(id: record.id, error: error)
                    errorPresentation = AIClientError.presentation(for: error)
                    creditAccessIssue = AICreditAccessIssue(error: error)
                    creditRetryInsightType = .monthly
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
                L10n.string("health_meals_body_ai.ca5bfb0e7766", fallback: "{{value1}}: {{value2}} 達成率 {{value3}}", values: [String(describing: $0.title), String(describing: AppFormatters.volume($0.totalVolume, unit: appStore.userProfile.weightUnit)), String(describing: AppFormatters.percent($0.achievementRate))])
            } : [],
            bodyPhotos: sharing.bodyPhotos ? appStore.bodyPhotoSets.filter { $0.date >= cutoff }.prefix(12).map { set in
                let angles = set.angleEntries.map(\.angle.displayName).joined(separator: L10n.string("health_meals_body_ai.3654226ac56b", fallback: "・"))
                let angleSummary = angles.isEmpty ? L10n.string("health_meals_body_ai.2071566e71be", fallback: "写真なし") : angles
                let observation = set.analysis?.summary ?? set.memo
                return L10n.string("health_meals_body_ai.1913fa724bc8", fallback: "{{value1}} {{value2}}枚（{{value3}}）: {{value4}}", values: [String(describing: set.date.formatted(date: .numeric, time: .omitted)), String(describing: set.photoEntries.count), String(describing: angleSummary), String(describing: observation)])
            } : [],
            sensorMetrics: sensorMetricsForAI
        )
    }

    private var sensorMetricsForAI: [String] {
        let sharing = appStore.aiSettings.dataSharing
        let snapshot = healthDataManager.snapshot
        var values: [String] = []

        if sharing.sleepAndRecovery, let sleep = snapshot.sleepHours {
            values.append(L10n.string("health_meals_body_ai.5f3317f450fa", fallback: "睡眠: {{value1}}時間", values: [String(describing: sleep.formatted(.number.precision(.fractionLength(1))))]))
        }
        if sharing.sleepAndRecovery, let resting = snapshot.restingHeartRate?.value {
            values.append(L10n.string("health_meals_body_ai.2dc87f83e5a5", fallback: "安静時心拍: {{value1}} bpm", values: [String(describing: Int(resting))]))
        }
        if sharing.sleepAndRecovery, let hrv = snapshot.heartRateVariabilityMilliseconds?.value {
            values.append("HRV: \(Int(hrv)) ms")
        }
        if sharing.dailyActivity, let steps = snapshot.steps {
            values.append(L10n.string("health_meals_body_ai.69f2ab157759", fallback: "歩数: {{value1}}", values: [String(describing: Int(steps))]))
        }
        if sharing.gymVisits, !appStore.gymVisits.isEmpty {
            values.append(L10n.string("health_meals_body_ai.e0cb665ec8d8", fallback: "直近7日のジム訪問: {{value1}}回", values: [String(describing: appStore.gymVisits.filter { $0.arrivedAt >= Date().addingTimeInterval(-7 * 86_400) }.count)]))
        }

        if sharing.workoutSensors {
            values.append(contentsOf: appStore.workoutHistory.prefix(6).compactMap { session in
                guard let sensors = session.sensorSummary else { return nil }
                let heartRate = sensors.averageHeartRate.map { L10n.string("health_meals_body_ai.6c784a6d3865", fallback: "平均心拍 {{value1}} bpm", values: [String(describing: Int($0))]) } ?? L10n.string("health_meals_body_ai.ea8e5fa4331a", fallback: "心拍未取得")
                let energy = sensors.activeEnergyKilocalories.map { L10n.string("health_meals_body_ai.1a4c8a429964", fallback: "消費 {{value1}} kcal", values: [String(describing: Int($0))]) } ?? L10n.string("health_meals_body_ai.ef05cf14844b", fallback: "消費未取得")
                return "\(session.title): \(heartRate), \(energy)"
            })
        }
        return values
    }

    private func statusTitle(_ status: AITransmissionStatus) -> String {
        switch status {
        case .sending: L10n.string("health_meals_body_ai.e228355c530a", fallback: "送信中")
        case .completed: L10n.string("health_meals_body_ai.16f7a1da8526", fallback: "完了")
        case .failed: L10n.string("health_meals_body_ai.8ecbbfce44c6", fallback: "失敗")
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
                Section(L10n.string("health_meals_body_ai.92d173b2e197", fallback: "入力データ")) {
                    TextEditor(text: $draft.inputSummary)
                        .frame(minHeight: 90)
                }
                Section(L10n.string("health_meals_body_ai.5b23cf84d4e8", fallback: "月次レビュー")) {
                    TextEditor(text: $draft.outputComment)
                        .frame(minHeight: 150)
                }
                Section(L10n.string("health_meals_body_ai.08a296b53ccb", fallback: "翌月目標案")) {
                    TextEditor(text: $draft.actionSuggestion)
                        .frame(minHeight: 120)
                    Text(L10n.string("health_meals_body_ai.c1b1833378f2", fallback: "内容を確認し、必要なら修正してから保存してください。目標は自動では確定しません。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.ff95423bda70", fallback: "月次レビューを確認"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.5e978cf690d0", fallback: "破棄"), role: .destructive) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) {
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
            title = L10n.string("health_meals_body_ai.ef2753a0d8e9", fallback: "接続OK")
            detail = L10n.string("health_meals_body_ai.336d67026106", fallback: "{{value1}} と補助モデルで週次コメントを生成できます。", values: [String(describing: health.model)])
            recovery = health.message
            tint = AppTheme.positive
            systemImage = "checkmark.circle.fill"
        } else if !health.ollamaReachable {
            title = L10n.string("health_meals_body_ai.b3ec9a0c94cd", fallback: "補助モデル未接続")
            detail = L10n.string("health_meals_body_ai.4047b572f3a1", fallback: "APIサーバーは応答していますが、料理・レポートの補助モデルを利用できません。")
            recovery = health.message
            tint = AppTheme.orange
            systemImage = "exclamationmark.triangle.fill"
        } else {
            title = L10n.string("health_meals_body_ai.75a1ae0d8cd7", fallback: "AIモデル準備中")
            detail = L10n.string("health_meals_body_ai.abbfa3552a40", fallback: "APIサーバーは応答していますが、必要なモデルを利用できません。")
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

            Text(L10n.string("health_meals_body_ai.c656bd9e9244", fallback: "記録は保存されたままです。あとで接続できる状態になってから、もう一度生成できます。"))
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
