import Foundation

enum ReportScheduleStore {
    static let weeklyEnabledKey = "bodymode.reports.weekly.enabled"
    static let weeklyWeekdayKey = "bodymode.reports.weekly.weekday"
    static let monthlyEnabledKey = "bodymode.reports.monthly.enabled"
    static let monthlyDayKey = "bodymode.reports.monthly.day"
    static let hourKey = "bodymode.reports.schedule.hour"
    static let minuteKey = "bodymode.reports.schedule.minute"
    static let automaticAICreditUseKey = "bodymode.reports.schedule.automaticAICreditUse"
    static let lastWeeklyKey = "bodymode.reports.weekly.lastGenerated"
    static let lastMonthlyKey = "bodymode.reports.monthly.lastGenerated"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            weeklyEnabledKey: false,
            weeklyWeekdayKey: 2,
            monthlyEnabledKey: false,
            monthlyDayKey: 1,
            hourKey: 20,
            minuteKey: 0,
            automaticAICreditUseKey: false
        ])
    }
}

@MainActor
enum ScheduledReportService {
    private static var isProcessing = false

    static func processDueReports(
        appStore: AppStore,
        healthSnapshot: DailyHealthSnapshot,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        ReportScheduleStore.registerDefaults(defaults)

        if isWeeklyDue(now: now, defaults: defaults, calendar: calendar) {
            await generate(
                kind: .weekly,
                days: 7,
                appStore: appStore,
                healthSnapshot: healthSnapshot,
                now: now,
                defaults: defaults
            )
        }
        if isMonthlyDue(now: now, defaults: defaults, calendar: calendar) {
            await generate(
                kind: .monthly,
                days: 30,
                appStore: appStore,
                healthSnapshot: healthSnapshot,
                now: now,
                defaults: defaults
            )
        }
    }

    static func isWeeklyDue(
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar
    ) -> Bool {
        guard defaults.bool(forKey: ReportScheduleStore.weeklyEnabledKey) else { return false }
        let weekday = min(7, max(1, defaults.integer(forKey: ReportScheduleStore.weeklyWeekdayKey)))
        guard calendar.component(.weekday, from: now) == weekday,
              hasReachedScheduledTime(now: now, defaults: defaults, calendar: calendar) else { return false }
        guard let last = defaults.object(forKey: ReportScheduleStore.lastWeeklyKey) as? Date else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }

    static func isMonthlyDue(
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar
    ) -> Bool {
        guard defaults.bool(forKey: ReportScheduleStore.monthlyEnabledKey) else { return false }
        let day = min(28, max(1, defaults.integer(forKey: ReportScheduleStore.monthlyDayKey)))
        guard calendar.component(.day, from: now) == day,
              hasReachedScheduledTime(now: now, defaults: defaults, calendar: calendar) else { return false }
        guard let last = defaults.object(forKey: ReportScheduleStore.lastMonthlyKey) as? Date else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }

    private static func hasReachedScheduledTime(
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar
    ) -> Bool {
        let hour = min(23, max(0, defaults.integer(forKey: ReportScheduleStore.hourKey)))
        let minute = min(59, max(0, defaults.integer(forKey: ReportScheduleStore.minuteKey)))
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        var scheduledComponents = components
        scheduledComponents.hour = hour
        scheduledComponents.minute = minute
        return now >= (calendar.date(from: scheduledComponents) ?? now)
    }

    private static func generate(
        kind: AIInsightType,
        days: Int,
        appStore: AppStore,
        healthSnapshot: DailyHealthSnapshot,
        now: Date,
        defaults: UserDefaults
    ) async {
        guard defaults.bool(forKey: ReportScheduleStore.automaticAICreditUseKey) else {
            appStore.saveAIInsight(localFallback(kind: kind, days: days, appStore: appStore, now: now))
            defaults.set(now, forKey: kind == .monthly ? ReportScheduleStore.lastMonthlyKey : ReportScheduleStore.lastWeeklyKey)
            return
        }
        let payload = ScheduledReportPayloadBuilder.build(
            days: days,
            appStore: appStore,
            healthSnapshot: healthSnapshot,
            now: now
        )
        let purpose = kind == .monthly ? "予約・月次レビュー" : "予約・週次レポート"
        let record = AITransmissionRecord(
            purpose: purpose,
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames,
            itemCount: payload.bodyLogs.count + payload.meals.count + payload.workouts.count
                + payload.bodyPhotos.count + payload.sensorMetrics.count
        )
        appStore.saveAITransmission(record)

        do {
            let client = AIAPIClient(settings: appStore.aiSettings)
            let response = kind == .monthly
                ? try await client.generateMonthlyReport(payload: payload)
                : try await client.generateWeeklyReport(payload: payload)
            appStore.saveAIInsight(AIInsight(
                insightType: kind,
                inputSummary: response.inputSummary,
                outputComment: response.outputComment,
                actionSuggestion: response.actionSuggestion,
                goodPoints: response.goodPoints,
                challenges: response.challenges,
                rationales: response.rationales,
                nextActions: response.nextActions
            ))
            appStore.updateAITransmission(id: record.id, status: .completed)
        } catch {
            appStore.recordAITransmissionFailure(id: record.id, error: error)
            appStore.saveAIInsight(localFallback(kind: kind, days: days, appStore: appStore, now: now))
        }

        defaults.set(now, forKey: kind == .monthly ? ReportScheduleStore.lastMonthlyKey : ReportScheduleStore.lastWeeklyKey)
    }

    private static func localFallback(
        kind: AIInsightType,
        days: Int,
        appStore: AppStore,
        now: Date
    ) -> AIInsight {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let workouts = appStore.workoutHistory.filter { $0.startedAt >= cutoff && $0.isCompleted }.count
        let mealDays = Set(appStore.mealEntries.filter { $0.recordedAt >= cutoff }.map { Calendar.current.startOfDay(for: $0.recordedAt) }).count
        return AIInsight(
            date: now,
            insightType: kind,
            inputSummary: "直近\(days)日: トレーニング\(workouts)回、食事記録\(mealDays)日",
            outputComment: "AIへ接続できなかったため、端末内の記録だけで振り返りました。記録は保持され、後からAIレポートを再生成できます。",
            actionSuggestion: workouts == 0
                ? "無理のない運動を1回予定し、実行後の疲労感を記録しましょう。"
                : "現在の記録を続け、次回起動時にAI分析を再試行してください。"
        )
    }
}

@MainActor
enum ScheduledReportPayloadBuilder {
    static func build(
        days: Int,
        appStore: AppStore,
        healthSnapshot: DailyHealthSnapshot,
        now: Date
    ) -> WeeklyReportRequest {
        let sharing = appStore.aiSettings.dataSharing
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let bodyLimit = days > 7 ? 80 : 20
        let mealLimit = days > 7 ? 150 : 30
        let workoutLimit = days > 7 ? 40 : 12
        var sensors: [String] = []
        if sharing.sleepAndRecovery, let sleep = healthSnapshot.sleepHours { sensors.append("睡眠: \(sleep.formatted(.number.precision(.fractionLength(1))))時間") }
        if sharing.sleepAndRecovery, let heartRate = healthSnapshot.restingHeartRate?.value { sensors.append("安静時心拍: \(Int(heartRate)) bpm") }
        if sharing.dailyActivity, let steps = healthSnapshot.steps { sensors.append("歩数: \(Int(steps))") }

        return WeeklyReportRequest(
            profileGoal: appStore.userProfile.goalType.displayName,
            coachID: appStore.userProfile.coachType.rawValue,
            coach: AIRequestCoachContext(profile: appStore.userProfile),
            experienceLevel: appStore.userProfile.experienceLevel.rawValue,
            bodyLogs: sharing.bodyMetrics ? appStore.bodyMetricEntries.filter { $0.recordedAt >= cutoff }.prefix(bodyLimit).map {
                "\($0.kind.displayName): \(AppFormatters.metricValue($0.value, unit: $0.kind.unit))"
            } : [],
            meals: sharing.meals ? appStore.mealEntries.filter { $0.recordedAt >= cutoff }.prefix(mealLimit).map {
                "\($0.mealType.displayName) \($0.name): \(AppFormatters.calories($0.calories)) P\(AppFormatters.grams($0.protein)) F\(AppFormatters.grams($0.fat)) C\(AppFormatters.grams($0.carbs))"
            } : [],
            workouts: sharing.workouts ? appStore.workoutHistory.filter { $0.startedAt >= cutoff }.prefix(workoutLimit).map {
                "\($0.title): \(AppFormatters.percent($0.achievementRate))"
            } : [],
            bodyPhotos: sharing.bodyPhotos ? appStore.bodyPhotoSets.filter { $0.date >= cutoff }.prefix(12).map {
                "\($0.date.formatted(date: .numeric, time: .omitted)): \($0.photoEntries.count)枚 \($0.analysis?.summary ?? $0.memo)"
            } : [],
            sensorMetrics: sensors
        )
    }
}
