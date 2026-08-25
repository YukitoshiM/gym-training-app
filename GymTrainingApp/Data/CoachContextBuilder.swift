import Foundation

enum CoachContextCoverageState: String, Equatable {
    case ready
    case needsRecord
    case notShared
}

struct CoachContextCoverageItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let state: CoachContextCoverageState
}

struct CoachContextCoverage: Equatable {
    let items: [CoachContextCoverageItem]

    var readyItems: [CoachContextCoverageItem] { items.filter { $0.state == .ready } }
    var missingItems: [CoachContextCoverageItem] { items.filter { $0.state != .ready } }

    var contextLines: [String] {
        var lines: [String] = []
        let ready = readyItems.map(\.title)
        if !ready.isEmpty {
            lines.append("AIへ共有できる記録: \(ready.joined(separator: "、"))")
        }

        let needsRecord = items.filter { $0.state == .needsRecord }
        if !needsRecord.isEmpty {
            lines.append("助言に不足している記録: \(needsRecord.map { "\($0.title)（\($0.detail)）" }.joined(separator: "、"))")
        }

        let notShared = items.filter { $0.state == .notShared }.map(\.title)
        if !notShared.isEmpty {
            lines.append("共有設定がオフの記録: \(notShared.joined(separator: "、"))")
        }

        if !missingItems.isEmpty {
            lines.append("不足情報は推測で断定せず、助言の結論に重要な場合だけユーザーへ短く確認する")
        }
        return lines
    }
}

struct CoachContextBuilder {
    typealias RecommendationHistory = (
        recommendations: [DailyRecommendation],
        revisions: [RecommendationRevision],
        reviews: [DailyReview]
    )

    private let calendar: Calendar
    private let now: Date
    private let recommendationHistoryProvider: () -> RecommendationHistory

    init(
        calendar: Calendar = .current,
        now: Date = Date(),
        recommendationHistoryProvider: @escaping () -> RecommendationHistory = {
            let storage = LocalJSONStorage()
            return (
                storage.loadDailyRecommendations(),
                storage.loadRecommendationRevisions(),
                storage.loadDailyReviews()
            )
        }
    ) {
        self.calendar = calendar
        self.now = now
        self.recommendationHistoryProvider = recommendationHistoryProvider
    }

    func build(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetrics: [BodyMetricEntry],
        bodyMetricGoals: [BodyMetricGoal],
        meals: [MealEntry],
        bodyPhotos: [BodyPhotoEntry],
        workouts: [WorkoutSession],
        gymVisits: [GymVisit],
        subjectiveRecovery: [SubjectiveRecoveryEntry],
        healthSnapshot: DailyHealthSnapshot,
        recoveryHistory: [DailyRecoveryTrendRecord],
        memories: [CoachMemory],
        insights: [AIInsight],
        planRevisions: [PlanRevisionProposal] = []
    ) -> CoachContext {
        let coverage = coverage(
            profile: profile,
            sharing: sharing,
            bodyMetrics: bodyMetrics,
            meals: meals,
            bodyPhotos: bodyPhotos,
            workouts: workouts,
            subjectiveRecovery: subjectiveRecovery,
            healthSnapshot: healthSnapshot,
            recoveryHistory: recoveryHistory
        )
        var recentContext = recent7Days(
            profile: profile,
            sharing: sharing,
            bodyMetrics: bodyMetrics,
            meals: meals,
            bodyPhotos: bodyPhotos,
            workouts: workouts,
            gymVisits: gymVisits,
            subjectiveRecovery: subjectiveRecovery,
            healthSnapshot: healthSnapshot,
            recoveryHistory: recoveryHistory
        )
        recentContext["記録状況"] = coverage.contextLines

        let recommendationHistory = recommendationHistoryProvider()
        let recommendationContext = recommendationContext(
            recommendations: recommendationHistory.recommendations,
            revisions: recommendationHistory.revisions,
            reviews: recommendationHistory.reviews,
            sharing: sharing,
            insights: insights
        )

        let planContext = planRevisionContext(planRevisions, sharing: sharing)
        return CoachContext(
            recent7Days: recentContext,
            recent4Weeks: recent4Weeks(
                profile: profile,
                sharing: sharing,
                bodyMetrics: bodyMetrics,
                meals: meals,
                workouts: workouts,
                recoveryHistory: recoveryHistory
            ),
            longTermTrends: longTermTrends(
                profile: profile,
                sharing: sharing,
                bodyMetrics: bodyMetrics,
                workouts: workouts
            ),
            personalRecords: sharing.workouts ? personalRecords(workouts: workouts, profile: profile) : [],
            goals: goals(profile: profile, sharing: sharing, bodyMetricGoals: bodyMetricGoals),
            preferences: preferences(profile: profile, sharing: sharing),
            memories: memories.map(\.content),
            previousSuggestion: recommendationContext.previousSuggestion.merging(planContext.previous) { _, plan in plan },
            suggestionResult: recommendationContext.suggestionResult.merging(planContext.result) { _, plan in plan }
        )
    }

    private func planRevisionContext(
        _ revisions: [PlanRevisionProposal],
        sharing: AIDataSharingSettings
    ) -> (previous: [String: String], result: [String: String]) {
        guard sharing.workouts,
              let revision = revisions
                .filter({ $0.decision != .pending })
                .sorted(by: { $0.createdAt > $1.createdAt })
                .first else { return ([:], [:]) }
        var previous = [
            "plan_revision": bounded(revision.summary, maximum: 300),
            "plan_revision_decision": revision.decision.rawValue
        ]
        if let revisedPlan = revision.revisedPlan {
            previous["revised_plan"] = bounded(revisedPlan.name, maximum: 120)
        }
        var result: [String: String] = [:]
        if revision.effectiveness != .unknown {
            result["plan_revision_effectiveness"] = revision.effectiveness.rawValue
        }
        result["baseline_achievement"] = revision.baselineAchievementRate.formatted(.percent.precision(.fractionLength(0)))
        return (previous, result)
    }

    func coverage(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetrics: [BodyMetricEntry],
        meals: [MealEntry],
        bodyPhotos: [BodyPhotoEntry],
        workouts: [WorkoutSession],
        subjectiveRecovery: [SubjectiveRecoveryEntry],
        healthSnapshot: DailyHealthSnapshot,
        recoveryHistory: [DailyRecoveryTrendRecord]
    ) -> CoachContextCoverage {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        var items: [CoachContextCoverageItem] = []

        let missingProfileFields = [
            profile.heightCm == nil ? "身長" : nil,
            profile.birthYear == nil ? "生年" : nil
        ].compactMap { $0 }
        items.append(CoachContextCoverageItem(
            id: "profile",
            title: "プロフィール",
            detail: missingProfileFields.isEmpty
                ? "身長・年代・目的を参照"
                : "\(missingProfileFields.joined(separator: "・"))を設定すると負荷や栄養の助言が安定",
            systemImage: "person.crop.circle",
            state: missingProfileFields.isEmpty ? .ready : .needsRecord
        ))

        items.append(coverageItem(
            id: "training_considerations",
            title: AppLanguagePreference.bilingual(
                japanese: "運動上の配慮",
                english: "Training considerations"
            ),
            systemImage: "heart.text.square",
            isShared: sharing.trainingConsiderations,
            isReady: profile.healthIntake.isComplete,
            readyDetail: AppLanguagePreference.bilingual(
                japanese: "運動習慣・強度・配慮事項を参照",
                english: "Activity, intensity, and considerations available"
            ),
            missingDetail: AppLanguagePreference.bilingual(
                japanese: "健康・運動ヒアリングを完了",
                english: "Complete the health and activity intake"
            )
        ))

        let requiredMetrics: [BodyMetricKind] = switch profile.coachType {
        case .fatLoss, .bodyRecomposition, .wellness:
            [.bodyWeight, .waist]
        case .hypertrophy, .strength, .returnToTraining:
            [.bodyWeight]
        }
        let recentMetricKinds = Set(bodyMetrics.filter { $0.recordedAt >= fourteenDaysAgo }.map(\.kind))
        let missingMetricNames = requiredMetrics.filter { !recentMetricKinds.contains($0) }.map(\.displayName)
        items.append(coverageItem(
            id: "body_metrics",
            title: "身体",
            systemImage: "scalemass",
            isShared: sharing.bodyMetrics,
            isReady: missingMetricNames.isEmpty,
            readyDetail: "直近14日の\(requiredMetrics.map(\.displayName).joined(separator: "・"))を参照",
            missingDetail: "\(missingMetricNames.joined(separator: "・"))を記録"
        ))

        if [.fatLoss, .hypertrophy, .bodyRecomposition, .wellness].contains(profile.coachType) {
            let mealDays = Set(meals.filter { $0.recordedAt >= sevenDaysAgo }.map { calendar.startOfDay(for: $0.recordedAt) })
            items.append(coverageItem(
                id: "meals",
                title: "食事",
                systemImage: "fork.knife",
                isShared: sharing.meals,
                isReady: mealDays.count >= 3,
                readyDetail: "直近7日で\(mealDays.count)日分を参照",
                missingDetail: "直近7日のうち3日分あると傾向を判定可能"
            ))
        }

        let recentWorkouts = workouts.filter { $0.isCompleted && $0.startedAt >= fourteenDaysAgo }
        items.append(coverageItem(
            id: "workouts",
            title: "トレーニング",
            systemImage: "dumbbell",
            isShared: sharing.workouts,
            isReady: !recentWorkouts.isEmpty,
            readyDetail: "直近14日の\(recentWorkouts.count)回を参照",
            missingDetail: "直近の実績を1回以上記録"
        ))

        let hasRecentSleep = healthSnapshot.sleepHours != nil
            || recoveryHistory.contains { $0.date >= sevenDaysAgo && $0.sleepHours != nil }
        let hasRecentFatigue = subjectiveRecovery.contains { $0.recordedAt >= sevenDaysAgo }
        let recoveryMissing = [
            hasRecentSleep ? nil : "睡眠",
            hasRecentFatigue ? nil : "疲労度"
        ].compactMap { $0 }
        items.append(coverageItem(
            id: "recovery",
            title: "回復",
            systemImage: "bed.double",
            isShared: sharing.sleepAndRecovery,
            isReady: recoveryMissing.isEmpty,
            readyDetail: "睡眠と主観疲労を参照",
            missingDetail: "\(recoveryMissing.joined(separator: "・"))を記録"
        ))

        if [.fatLoss, .wellness, .returnToTraining].contains(profile.coachType) {
            let hasRecentActivity = healthSnapshot.steps != nil
                || healthSnapshot.activeEnergyKilocalories != nil
                || recoveryHistory.contains { $0.date >= sevenDaysAgo && $0.activeEnergyKilocalories != nil }
            items.append(coverageItem(
                id: "activity",
                title: "日常活動",
                systemImage: "figure.walk",
                isShared: sharing.dailyActivity,
                isReady: hasRecentActivity,
                readyDetail: "歩数・活動量を参照",
                missingDetail: "Healthから歩数または活動量を取得"
            ))
        }

        if profile.coachType == .bodyRecomposition {
            let hasRecentPhoto = bodyPhotos.contains { $0.recordedAt >= thirtyDaysAgo }
            items.append(coverageItem(
                id: "body_photos",
                title: "体型写真",
                systemImage: "person.crop.rectangle",
                isShared: sharing.bodyPhotos,
                isReady: hasRecentPhoto,
                readyDetail: "直近30日の比較コメントを参照",
                missingDetail: "同じ条件の写真を1枚記録"
            ))
        }

        if [.hypertrophy, .strength, .returnToTraining].contains(profile.coachType) {
            let hasSensorSummary = recentWorkouts.contains { $0.sensorSummary != nil }
            items.append(coverageItem(
                id: "workout_sensors",
                title: "運動センサー",
                systemImage: "waveform.path.ecg",
                isShared: sharing.workoutSensors,
                isReady: hasSensorSummary,
                readyDetail: "心拍・動作・回復を参照",
                missingDetail: "Watchで1回記録すると疲労判断を補強"
            ))
        }

        return CoachContextCoverage(items: items)
    }

    private func recent7Days(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetrics: [BodyMetricEntry],
        meals: [MealEntry],
        bodyPhotos: [BodyPhotoEntry],
        workouts: [WorkoutSession],
        gymVisits: [GymVisit],
        subjectiveRecovery: [SubjectiveRecoveryEntry],
        healthSnapshot: DailyHealthSnapshot,
        recoveryHistory: [DailyRecoveryTrendRecord]
    ) -> [String: [String]] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let bodyPhotoCutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        var result: [String: [String]] = [:]

        if sharing.workouts {
            let recentWorkouts = workouts
                .filter { $0.startedAt >= cutoff && $0.isCompleted }
                .sorted { $0.startedAt > $1.startedAt }
            result["トレーニング概要"] = recentWorkouts.map { session in
                var values = [
                    "\(day(session.startedAt)): \(session.title)",
                    "\(session.completedSetCount)セット",
                    "\(session.completedRepCount)回",
                    "総量\(number(session.totalVolume))\(profile.weightUnit.displayName)",
                    "達成率\(Int((session.achievementRate * 100).rounded()))%"
                ]
                if let endedAt = session.endedAt {
                    values.append("\(Int(endedAt.timeIntervalSince(session.startedAt) / 60))分")
                }
                if let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    values.append("メモ: \(note)")
                }
                return values.joined(separator: ", ")
            }

            for session in recentWorkouts {
                for exercise in session.exercises where !exercise.isSkipped {
                    let sets = exercise.sets.filter(\.isCompleted).map { set in
                        var value = "\(number(set.actualWeight))\(profile.weightUnit.displayName) x \(set.actualReps)回"
                        if let rpe = set.rpe { value += " RPE \(number(rpe))" }
                        return value
                    }
                    guard !sets.isEmpty else { continue }
                    result[exercise.exercise.name, default: []].append("\(day(session.startedAt)): \(sets.joined(separator: ", "))")
                }
            }
        }

        if sharing.meals {
            let recentMeals = meals.filter { $0.recordedAt >= cutoff }
            let grouped = Dictionary(grouping: recentMeals) { calendar.startOfDay(for: $0.recordedAt) }
            result["食事"] = grouped.keys.sorted(by: >).map { date in
                let values = grouped[date] ?? []
                return "\(day(date)): \(values.count)食, \(Int(values.reduce(0) { $0 + $1.calories }))kcal, P\(Int(values.reduce(0) { $0 + $1.protein }))g F\(Int(values.reduce(0) { $0 + $1.fat }))g C\(Int(values.reduce(0) { $0 + $1.carbs }))g"
            }
            result["食事詳細"] = recentMeals
                .sorted { $0.recordedAt > $1.recordedAt }
                .prefix(24)
                .map { meal in
                    var value = "\(day(meal.recordedAt)) \(meal.mealType.displayName): \(meal.name), \(Int(meal.calories))kcal P\(number(meal.protein))g F\(number(meal.fat))g C\(number(meal.carbs))g"
                    let memo = meal.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !memo.isEmpty { value += ", メモ: \(memo)" }
                    return value
                }
        }

        if sharing.bodyMetrics {
            result["身体KPI"] = bodyMetrics
                .filter { $0.recordedAt >= cutoff }
                .sorted { $0.recordedAt > $1.recordedAt }
                .prefix(20)
                .map {
                    let note = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = note.isEmpty ? "" : " メモ: \(note)"
                    return "\(day($0.recordedAt)): \($0.kind.displayName) \(number($0.value))\($0.kind.storageUnit)\(suffix)"
                }
        }

        if sharing.bodyPhotos {
            result["体型写真"] = BodyPhotoSet.grouped(
                bodyPhotos.filter { $0.recordedAt >= bodyPhotoCutoff && $0.recordedAt <= now },
                calendar: calendar
            )
                .prefix(12)
                .map { set in
                    let summary = set.analysis?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let memo = set.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                    let observation = !summary.isEmpty ? summary : (!memo.isEmpty ? memo : "記録あり")
                    let angles = set.angleEntries.map(\.angle.displayName).joined(separator: "・")
                    let angleSummary = angles.isEmpty ? "写真なし" : angles
                    return "\(day(set.date)): \(set.photoEntries.count)枚（\(angleSummary)） \(observation)"
                }
        }

        if sharing.sleepAndRecovery {
            var recovery: [String] = subjectiveRecovery
                .filter { $0.recordedAt >= cutoff }
                .sorted { $0.recordedAt > $1.recordedAt }
                .map { "\(day($0.recordedAt)): 主観疲労 \($0.fatigueLevel)/5" }
            if let sleep = healthSnapshot.sleepSummary {
                var values = ["直近睡眠 \(number(sleep.totalHours))時間"]
                if let deep = sleep.deepHours { values.append("深い\(number(deep))時間") }
                if let rem = sleep.remHours { values.append("REM\(number(rem))時間") }
                if let quality = sleep.qualityScore { values.append("品質\(quality)/100") }
                if let interruptions = sleep.interruptionCount { values.append("中断\(interruptions)回") }
                recovery.insert(values.joined(separator: ", "), at: 0)
            } else if let sleep = healthSnapshot.sleepHours {
                recovery.insert("直近睡眠 \(number(sleep))時間", at: 0)
            }
            if let restingHeartRate = healthSnapshot.restingHeartRate?.value {
                recovery.append("安静時心拍 \(Int(restingHeartRate))bpm")
            }
            if let hrv = healthSnapshot.heartRateVariabilityMilliseconds?.value {
                recovery.append("HRV \(Int(hrv))ms")
            }
            if let respiratoryRate = healthSnapshot.respiratoryRate?.value {
                recovery.append("呼吸数 \(number(respiratoryRate))回/分")
            }
            if let temperature = healthSnapshot.wristTemperatureCelsius?.value {
                recovery.append("手首温 \(number(temperature))℃")
            }
            if let heartRateRecovery = healthSnapshot.heartRateRecovery?.value {
                recovery.append("心拍回復 \(number(heartRateRecovery))bpm")
            }
            result["回復"] = recovery
            result["回復トレンド"] = recoveryHistory
                .filter { $0.date >= cutoff }
                .sorted { $0.date > $1.date }
                .prefix(7)
                .map { record in
                    var values = [day(record.date)]
                    if let sleep = record.sleepHours { values.append("睡眠\(number(sleep))時間") }
                    if let heartRateDelta = record.restingHeartRateDelta { values.append("安静時心拍差\(signed(heartRateDelta))bpm") }
                    if let hrvRatio = record.hrvRatio { values.append("HRV比\(number(hrvRatio))") }
                    return values.joined(separator: ", ")
                }
        }

        if sharing.dailyActivity {
            var activity: [String] = []
            if let steps = healthSnapshot.steps { activity.append("今日の歩数 \(Int(steps))歩") }
            if let energy = healthSnapshot.activeEnergyKilocalories { activity.append("今日の活動エネルギー \(Int(energy))kcal") }
            if let restingEnergy = healthSnapshot.restingEnergyKilocalories { activity.append("今日の安静時エネルギー \(Int(restingEnergy))kcal") }
            if let distance = healthSnapshot.walkingRunningDistanceKilometers { activity.append("今日の歩行・走行距離 \(number(distance))km") }
            if let flights = healthSnapshot.flightsClimbed { activity.append("今日の上った階数 \(Int(flights))階") }
            if let progress = healthSnapshot.activityProgress {
                if let exerciseMinutes = progress.exerciseMinutes { activity.append("今日の運動 \(Int(exerciseMinutes))分") }
                if let standHours = progress.standHours { activity.append("今日のスタンド \(Int(standHours))時間") }
            }
            result["日常活動"] = activity
            result["日常活動トレンド"] = recoveryHistory
                .filter { $0.date >= cutoff && $0.activeEnergyKilocalories != nil }
                .sorted { $0.date > $1.date }
                .prefix(7)
                .compactMap { record in
                    record.activeEnergyKilocalories.map { "\(day(record.date)): 活動エネルギー\(Int($0))kcal" }
                }
        }

        if sharing.gymVisits {
            result["ジム訪問"] = gymVisits
                .filter { $0.arrivedAt >= cutoff }
                .sorted { $0.arrivedAt > $1.arrivedAt }
                .map { "\(day($0.arrivedAt)): 訪問" }
        }

        if sharing.workoutSensors {
            result["ワークアウトセンサー"] = workouts
                .filter { $0.startedAt >= cutoff }
                .compactMap { session in
                    guard let sensors = session.sensorSummary else { return nil }
                    var values = ["\(day(session.startedAt)) \(session.title)"]
                    values.append("\(Int(sensors.durationSeconds / 60))分")
                    if let heartRate = sensors.averageHeartRate { values.append("平均心拍\(Int(heartRate))bpm") }
                    if let heartRate = sensors.maximumHeartRate { values.append("最大心拍\(Int(heartRate))bpm") }
                    if let recovery = sensors.heartRateRecovery { values.append("心拍回復\(number(recovery))bpm") }
                    if let energy = sensors.activeEnergyKilocalories { values.append("消費\(Int(energy))kcal") }
                    if let reps = sensors.estimatedReps { values.append("推定\(reps)回") }
                    if let confidence = sensors.motionConfidence { values.append("動作信頼度\(Int(confidence * 100))%") }
                    return values.joined(separator: " ")
                }
        }

        return result.filter { !$0.value.isEmpty }
    }

    private func recent4Weeks(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetrics: [BodyMetricEntry],
        meals: [MealEntry],
        workouts: [WorkoutSession],
        recoveryHistory: [DailyRecoveryTrendRecord]
    ) -> [String: [String]] {
        var summaries: [String] = []
        for weeksAgo in 0..<4 {
            let end = calendar.date(byAdding: .day, value: -(weeksAgo * 7), to: now) ?? now
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            var parts = ["\(day(start))〜\(day(end))"]

            if sharing.workouts {
                let sessions = workouts.filter { $0.startedAt >= start && $0.startedAt < end && $0.isCompleted }
                parts.append("筋トレ\(sessions.count)回")
                parts.append("完了セット\(sessions.reduce(0) { $0 + $1.completedSetCount })")
                parts.append("総量\(number(sessions.reduce(0) { $0 + $1.totalVolume }))\(profile.weightUnit.displayName)")
            }

            if sharing.meals {
                let values = meals.filter { $0.recordedAt >= start && $0.recordedAt < end }
                if !values.isEmpty {
                    parts.append("食事\(values.count)件")
                    parts.append("平均\(Int(values.reduce(0) { $0 + $1.calories } / 7))kcal/日")
                }
            }

            if sharing.bodyMetrics {
                for kind in BodyMetricKind.allCases {
                    let values = bodyMetrics
                        .filter { $0.kind == kind && $0.recordedAt >= start && $0.recordedAt < end }
                        .map(\.value)
                    if !values.isEmpty {
                        parts.append("\(kind.displayName)平均\(number(values.reduce(0, +) / Double(values.count)))\(kind.storageUnit)")
                    }
                }
            }

            if sharing.sleepAndRecovery {
                let recovery = recoveryHistory.filter { $0.date >= start && $0.date < end }
                let sleep = recovery.compactMap(\.sleepHours)
                let hrv = recovery.compactMap(\.hrvRatio)
                if !sleep.isEmpty {
                    parts.append("平均睡眠\(number(sleep.reduce(0, +) / Double(sleep.count)))時間")
                }
                if !hrv.isEmpty {
                    parts.append("平均HRV比\(number(hrv.reduce(0, +) / Double(hrv.count)))")
                }
            }

            if sharing.dailyActivity {
                let activity = recoveryHistory
                    .filter { $0.date >= start && $0.date < end }
                    .compactMap(\.activeEnergyKilocalories)
                if !activity.isEmpty {
                    parts.append("平均活動\(Int(activity.reduce(0, +) / Double(activity.count)))kcal")
                }
            }
            summaries.append(parts.joined(separator: ", "))
        }
        return summaries.isEmpty ? [:] : ["週間サマリー": summaries]
    }

    private func longTermTrends(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetrics: [BodyMetricEntry],
        workouts: [WorkoutSession]
    ) -> [String: [String]] {
        let cutoff = calendar.date(byAdding: .day, value: -365, to: now) ?? .distantPast
        var result: [String: [String]] = [:]

        if sharing.bodyMetrics {
            result["身体変化"] = BodyMetricKind.allCases.compactMap { kind in
                let entries = bodyMetrics
                    .filter { $0.kind == kind && $0.recordedAt >= cutoff }
                    .sorted { $0.recordedAt < $1.recordedAt }
                guard let first = entries.first, let last = entries.last, first.id != last.id else { return nil }
                let delta = last.value - first.value
                return "\(kind.displayName): \(number(first.value))→\(number(last.value))\(kind.storageUnit) (\(signed(delta))\(kind.storageUnit))"
            }
        }

        if sharing.workouts {
            let sessions = workouts.filter { $0.startedAt >= cutoff && $0.isCompleted }
            result["年間トレーニング"] = [
                "\(sessions.count)回, \(sessions.reduce(0) { $0 + $1.completedSetCount })セット, 総量\(number(sessions.reduce(0) { $0 + $1.totalVolume }))\(profile.weightUnit.displayName)"
            ]
        }
        return result.filter { !$0.value.isEmpty }
    }

    private func personalRecords(workouts: [WorkoutSession], profile: UserProfile) -> [String] {
        var best: [String: WorkoutSet] = [:]
        for exercise in workouts.filter(\.isCompleted).flatMap(\.exercises) where !exercise.isSkipped {
            for set in exercise.sets where set.isCompleted {
                let current = best[exercise.exercise.name]
                if current == nil
                    || set.actualWeight > current!.actualWeight
                    || (set.actualWeight == current!.actualWeight && set.actualReps > current!.actualReps) {
                    best[exercise.exercise.name] = set
                }
            }
        }
        return best.keys.sorted().compactMap { name in
            guard let set = best[name] else { return nil }
            return "\(name): \(number(set.actualWeight))\(profile.weightUnit.displayName) x \(set.actualReps)回"
        }
    }

    private func goals(
        profile: UserProfile,
        sharing: AIDataSharingSettings,
        bodyMetricGoals: [BodyMetricGoal]
    ) -> [String] {
        var result = [
            "目的: \(profile.goalType.displayName)",
            "目指すスタイル: \(profile.outcomeStyle.displayName)"
        ]
        if profile.outcomeStyle == .custom, !profile.customOutcomeText.isEmpty {
            result.append("目標の詳細: \(profile.customOutcomeText)")
        }
        if !profile.focusMuscles.isEmpty {
            result.append("重点部位: \(profile.focusMuscles.map(\.displayName).joined(separator: "・"))")
        }
        if sharing.bodyMetrics {
            result.append(contentsOf: bodyMetricGoals.compactMap { goal in
                guard let target = goal.targetValue else { return nil }
                return "目標\(goal.kind.displayName): \(number(target))\(goal.kind.storageUnit)"
            })
        }
        if sharing.meals {
            let nutrition = profile.nutritionGoals
            result.append("食事目標: \(Int(nutrition.calories))kcal P\(number(nutrition.protein))g F\(number(nutrition.fat))g C\(number(nutrition.carbs))g \(nutrition.mealCount)食")
        }
        return result
    }

    private func preferences(profile: UserProfile, sharing: AIDataSharingSettings) -> [String] {
        var result = [
            "担当コーチ: \(profile.coachType.displayName)",
            "担当トレーナー: \(profile.coachPersona.displayName)",
            "トレーナーの話し方: \(profile.coachingStyle.promptDescription)",
            "コーチの重点領域: \(profile.coachType.expertiseProfile.topFocusAreas.joined(separator: "・"))",
            "経験レベル: \(profile.experienceLevel.displayName)",
            "希望ペース: 週\(profile.weeklyTrainingDays)日・1回\(profile.preferredSessionMinutes)分",
            "利用できる器具: \(profile.availableEquipment.map(\.displayName).joined(separator: "、"))",
            "重量単位: \(profile.weightUnit.displayName)",
            "返答言語: \(AppLanguagePreference.aiLocaleIdentifier)",
            "回答形式: 結論を先に示し、短い段落・見出し・箇条書きで読みやすくする"
        ]
        if sharing.trainingConsiderations {
            let intake = profile.healthIntake
            result.append("現在の運動習慣: \(intake.activityLevel.displayName)")
            result.append("予定する運動強度: \(intake.plannedIntensity.displayName)")
            result.append("運動上の配慮: \(intake.safetyStatus.displayName)")
            if !intake.considerations.isEmpty {
                result.append("配慮項目: \(intake.considerations.map(\.displayName).joined(separator: "、"))")
            }
            result.append("ふだんの睡眠: \(intake.typicalSleep.displayName)")
            if intake.goalFocus != .notAnswered {
                result.append("目的別の優先項目: \(intake.goalFocus.displayName)")
            }
            if intake.nutritionGuidanceMode != .notAnswered {
                result.append("食事助言の扱い: \(intake.nutritionGuidanceMode.displayName)")
            }
            if let days = intake.otherTrainingDays {
                result.append("その他の練習: 週\(days)回")
            }
            if !intake.sportOrActivity.isEmpty {
                result.append("競技・アクティビティ: \(intake.sportOrActivity)")
            }
            if !intake.note.isEmpty {
                result.append("専門家の指示・避けたい動作: \(bounded(intake.note, maximum: 300))")
            }
            result.append("症状や専門家の指示に反する運動・食事の提案はしない")
        }
        if sharing.bodyMetrics {
            if let height = profile.heightCm {
                result.append("身長: \(number(height))cm")
            }
            if let birthYear = profile.birthYear {
                let currentYear = calendar.component(.year, from: now)
                result.append("年齢目安: \(max(0, currentYear - birthYear))歳")
            }
            if profile.sex != .unspecified {
                result.append("性別: \(profile.sex.displayName)")
            }
        }
        return result
    }

    private func coverageItem(
        id: String,
        title: String,
        systemImage: String,
        isShared: Bool,
        isReady: Bool,
        readyDetail: String,
        missingDetail: String
    ) -> CoachContextCoverageItem {
        if !isShared {
            return CoachContextCoverageItem(
                id: id,
                title: title,
                detail: "AI共有設定がオフ",
                systemImage: systemImage,
                state: .notShared
            )
        }
        return CoachContextCoverageItem(
            id: id,
            title: title,
            detail: isReady ? readyDetail : missingDetail,
            systemImage: systemImage,
            state: isReady ? .ready : .needsRecord
        )
    }

    private func recommendationContext(
        recommendations: [DailyRecommendation],
        revisions: [RecommendationRevision],
        reviews: [DailyReview],
        sharing: AIDataSharingSettings,
        insights: [AIInsight]
    ) -> (previousSuggestion: [String: String], suggestionResult: [String: String]) {
        let eligibleRecommendations = recommendations
            .filter { $0.date <= now }
            .sorted { $0.date > $1.date }

        guard let recommendation = eligibleRecommendations.first(where: {
            $0.actions.contains { $0.status != .replaced && canShare($0.category, sharing: sharing) }
        }) else {
            return (legacyPreviousSuggestion(insights, sharing: sharing), [:])
        }

        let actions = Array(
            recommendation.actions
                .filter { $0.status != .replaced && canShare($0.category, sharing: sharing) }
                .sorted { $0.priority < $1.priority }
                .prefix(3)
        )
        guard !actions.isEmpty else {
            return (legacyPreviousSuggestion(insights, sharing: sharing), [:])
        }

        var previousSuggestion: [String: String] = [
            "date": day(recommendation.date),
            "source": recommendation.source.rawValue,
            "actions": bounded(actions.map(actionDescription).joined(separator: " / "), maximum: 600)
        ]

        if let revision = revisions
            .filter({
                $0.timestamp <= now
                    && calendar.isDate($0.date, inSameDayAs: recommendation.date)
                    && $0.newActions.contains { canShare($0.category, sharing: sharing) }
            })
            .max(by: { $0.timestamp < $1.timestamp }) {
            previousSuggestion["revision_at"] = timestamp(revision.timestamp)
            previousSuggestion["revision_source"] = revision.source.rawValue
            let revisedActions = revision.newActions
                .filter { $0.status != .replaced && canShare($0.category, sharing: sharing) }
                .sorted { $0.priority < $1.priority }
                .prefix(3)
                .map(actionDescription)
            if !revisedActions.isEmpty {
                previousSuggestion["revised_actions"] = bounded(revisedActions.joined(separator: " / "), maximum: 600)
            }
        }

        let visibleActionIDs = Set(actions.map(\.id))
        let completed = actions.filter { $0.status == .completed }
        let skipped = actions.filter { $0.status == .skipped }
        let adopted = actions.filter { $0.adoptedAt != nil }
        let review = reviews
            .filter { $0.generatedAt <= now && calendar.isDate($0.date, inSameDayAs: recommendation.date) }
            .max(by: { $0.generatedAt < $1.generatedAt })
        let reviewedCompleted = review.map { Set($0.completedActionIDs).intersection(visibleActionIDs) } ?? []
        let reviewedSkipped = review.map { Set($0.skippedActionIDs).intersection(visibleActionIDs) } ?? []
        let completedIDs = Set(completed.map(\.id)).union(reviewedCompleted)
        let skippedIDs = Set(skipped.map(\.id)).union(reviewedSkipped)

        var suggestionResult: [String: String] = [
            "date": day(recommendation.date),
            "completion": "\(completedIDs.count)/\(actions.count)",
            "adopted": "\(adopted.count)/\(actions.count)"
        ]
        let completedTitles = actions.filter { completedIDs.contains($0.id) }.map(\.title)
        let skippedTitles = actions.filter { skippedIDs.contains($0.id) }.map(\.title)
        if !completedTitles.isEmpty {
            suggestionResult["completed_actions"] = bounded(completedTitles.joined(separator: "、"), maximum: 400)
        }
        if !skippedTitles.isEmpty {
            suggestionResult["skipped_actions"] = bounded(skippedTitles.joined(separator: "、"), maximum: 400)
        }
        let allActiveActionsShareable = recommendation.actions
            .filter { $0.status != .replaced }
            .allSatisfy { canShare($0.category, sharing: sharing) }
        if let review, allActiveActionsShareable {
            suggestionResult["review"] = bounded(review.summary, maximum: 400)
        }

        return (previousSuggestion, suggestionResult)
    }

    private func actionDescription(_ action: DailyAction) -> String {
        let title = bounded(action.title, maximum: 120)
        let target = bounded(action.targetDescription, maximum: 120)
        let label = target.isEmpty ? title : "\(title)（\(target)）"
        return "\(label) [\(action.status.rawValue)]"
    }

    private func canShare(_ category: DailyActionCategory, sharing: AIDataSharingSettings) -> Bool {
        switch category {
        case .workout:
            sharing.workouts
        case .steps, .lightActivity:
            sharing.dailyActivity
        case .protein, .mealGuidance:
            sharing.meals
        case .bodyWeight, .waist:
            sharing.bodyMetrics
        case .bodyPhoto:
            sharing.bodyPhotos
        case .sleep, .recovery:
            sharing.sleepAndRecovery
        }
    }

    private func legacyPreviousSuggestion(
        _ insights: [AIInsight],
        sharing: AIDataSharingSettings
    ) -> [String: String] {
        let allCategoriesShared = sharing.bodyMetrics
            && sharing.meals
            && sharing.workouts
            && sharing.bodyPhotos
            && sharing.sleepAndRecovery
            && sharing.dailyActivity
            && sharing.gymVisits
            && sharing.workoutSensors
        guard allCategoriesShared,
              let insight = insights
                .filter({ $0.insightType == .weekly && $0.date <= now })
                .max(by: { $0.date < $1.date }) else {
            return [:]
        }
        return [
            "date": day(insight.date),
            "suggestion": bounded(insight.actionSuggestion, maximum: 600)
        ]
    }

    private func bounded(_ value: String, maximum: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(maximum))
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func day(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func signed(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + number(value)
    }
}
