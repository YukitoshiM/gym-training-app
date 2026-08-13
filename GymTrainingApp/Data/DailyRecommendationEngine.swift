import Foundation

struct DailyRecommendationInput {
    var now: Date
    var profile: UserProfile
    var plans: [TrainingPlan]
    var selectedPlan: TrainingPlan?
    var workouts: [WorkoutSession]
    var meals: [MealEntry]
    var bodyMetrics: [BodyMetricEntry]
    var bodyPhotos: [BodyPhotoEntry]
    var subjectiveRecovery: SubjectiveRecoveryEntry?
    var health: DailyHealthSnapshot
    var assessment: ReadinessAssessment
    var previousRecommendations: [DailyRecommendation]
}

struct DailyRecommendationEngine {
    static let contextVersion = 1
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeRecommendation(from input: DailyRecommendationInput) -> DailyRecommendation {
        let day = calendar.startOfDay(for: input.now)
        let readiness = makeReadiness(from: input)
        let primary = makePrimaryAction(input: input, readiness: readiness)
        var candidates = supportingActions(input: input)
        candidates.sort { score($0, input: input) > score($1, input: input) }

        var actions = [primary]
        for candidate in candidates where actions.count < 3 {
            guard !actions.contains(where: { $0.category == candidate.category }) else { continue }
            actions.append(candidate)
        }
        actions = actions.enumerated().map { index, action in
            var action = action
            action.priority = index
            return action
        }

        return DailyRecommendation(
            date: day,
            generatedAt: input.now,
            readiness: readiness,
            actions: actions,
            summary: summary(for: readiness),
            contextVersion: Self.contextVersion,
            source: .localRule
        )
    }

    func replacementAction(
        for action: DailyAction,
        recommendation: DailyRecommendation,
        input: DailyRecommendationInput
    ) -> DailyAction? {
        let used = Set(recommendation.activeActions.map(\.category))
        let candidates = [makePrimaryAction(input: input, readiness: recommendation.readiness)]
            + supportingActions(input: input)
        return candidates
            .filter { $0.category != action.category && !used.contains($0.category) }
            .max { score($0, input: input) < score($1, input: input) }
    }

    func progress(for action: DailyAction, input: DailyRecommendationInput) -> DailyActionProgress {
        let day = calendar.startOfDay(for: input.now)
        let workouts = input.workouts.filter { calendar.isDate($0.startedAt, inSameDayAs: day) && $0.isCompleted }
        let meals = input.meals.filter { calendar.isDate($0.recordedAt, inSameDayAs: day) }

        switch action.completionRule {
        case .workoutCompleted(let planID):
            let matching = workouts.contains { workout in
                planID == nil || workout.sourcePlanID == planID
            }
            return DailyActionProgress(
                current: matching ? 1 : 0,
                target: 1,
                detail: matching ? "完了" : "未実施",
                isCompleted: matching
            )
        case .stepsAtLeast(let target):
            let current = input.health.steps ?? 0
            return DailyActionProgress(
                current: current,
                target: Double(target),
                detail: "\(Int(current).formatted()) / \(target.formatted())歩",
                isCompleted: current >= Double(target)
            )
        case .proteinAtLeast(let target):
            let current = meals.reduce(0) { $0 + $1.protein }
            return DailyActionProgress(
                current: current,
                target: target,
                detail: "P \(Int(current.rounded())) / \(Int(target.rounded()))g",
                isCompleted: current >= target * 0.9
            )
        case .mealsRecorded(let target):
            return DailyActionProgress(
                current: Double(meals.count),
                target: Double(target),
                detail: "\(meals.count) / \(target)食",
                isCompleted: meals.count >= target
            )
        case .bodyMetricRecorded(let kind):
            let completed = input.bodyMetrics.contains {
                $0.kind == kind && calendar.isDate($0.recordedAt, inSameDayAs: day)
            }
            return DailyActionProgress(
                current: completed ? 1 : 0,
                target: 1,
                detail: completed ? "記録済み" : "未記録",
                isCompleted: completed
            )
        case .photoSetRecorded:
            let completed = input.bodyPhotos.contains {
                $0.imageData != nil && calendar.isDate($0.recordedAt, inSameDayAs: day)
            }
            return DailyActionProgress(
                current: completed ? 1 : 0,
                target: 1,
                detail: completed ? "撮影済み" : "未撮影",
                isCompleted: completed
            )
        case .sleepAtLeast(let target):
            let current = input.health.sleepHours ?? 0
            return DailyActionProgress(
                current: current,
                target: target,
                detail: "\(current.formatted(.number.precision(.fractionLength(1)))) / \(target.formatted(.number.precision(.fractionLength(1))))時間",
                isCompleted: current >= target
            )
        case .recoveryDayObserved:
            let hour = calendar.component(.hour, from: input.now)
            let hasWorkout = workouts.contains { $0.isCompleted }
            let completed = hour >= 20 && !hasWorkout
            return DailyActionProgress(
                current: completed ? 1 : 0,
                target: 1,
                detail: hasWorkout ? "運動記録あり" : (completed ? "回復日として完了" : "夜に自動で完了"),
                isCompleted: completed
            )
        case .manuallyConfirmed:
            let completed = action.status == .completed
            return DailyActionProgress(
                current: completed ? 1 : 0,
                target: 1,
                detail: completed ? "完了" : "確認待ち",
                isCompleted: completed
            )
        }
    }

    func targetAdjustmentProposal(
        from input: DailyRecommendationInput,
        existing: [TargetAdjustmentProposal]
    ) -> TargetAdjustmentProposal? {
        guard input.profile.nutritionGoals.calories > 0,
              !existing.contains(where: { $0.status == .pending }),
              !existing.contains(where: { input.now.timeIntervalSince($0.createdAt) < 7 * 24 * 60 * 60 }) else {
            return nil
        }

        let weights = input.bodyMetrics
            .filter { $0.kind == .bodyWeight && $0.recordedAt >= input.now.addingTimeInterval(-14 * 24 * 60 * 60) }
        let recentCutoff = input.now.addingTimeInterval(-7 * 24 * 60 * 60)
        let recent = weights.filter { $0.recordedAt >= recentCutoff }.map(\.value)
        let previous = weights.filter { $0.recordedAt < recentCutoff }.map(\.value)
        guard recent.count >= 2, previous.count >= 2 else { return nil }

        let recentAverage = recent.reduce(0, +) / Double(recent.count)
        let previousAverage = previous.reduce(0, +) / Double(previous.count)
        guard previousAverage > 0 else { return nil }
        let changeRate = (recentAverage - previousAverage) / previousAverage

        let adjustment: Double?
        let reason: String?
        switch input.profile.goalType {
        case .diet, .bodyShape:
            if changeRate < -0.015 {
                adjustment = 100
                reason = "直近の週平均体重が速めに下がっています。無理のない進み方にするため、摂取目安を少し増やす候補です。"
            } else if changeRate > 0.005 {
                adjustment = -100
                reason = "直近の週平均体重が目標方向と逆に動いています。まずは摂取目安を少し調整する候補です。"
            } else {
                adjustment = nil
                reason = nil
            }
        case .muscleGain:
            if changeRate < -0.005 {
                adjustment = 100
                reason = "直近の週平均体重が下がっています。筋肥大を支えるため、摂取目安を少し増やす候補です。"
            } else if changeRate > 0.01 {
                adjustment = -100
                reason = "直近の週平均体重が速めに増えています。増加ペースを整えるため、摂取目安を少し抑える候補です。"
            } else {
                adjustment = nil
                reason = nil
            }
        case .health, .performance:
            adjustment = nil
            reason = nil
        }

        guard let adjustment, let reason else { return nil }
        let current = input.profile.nutritionGoals.calories
        let proposed = min(10_000, max(1_000, current + adjustment))
        guard proposed != current else { return nil }
        return TargetAdjustmentProposal(
            createdAt: input.now,
            kind: .calorieTarget,
            currentValue: current,
            proposedValue: proposed,
            reason: reason
        )
    }

    private func makeReadiness(from input: DailyRecommendationInput) -> DailyReadiness {
        let health = input.health
        var available = 0
        var missing: [String] = []

        if health.sleepHours == nil { missing.append("睡眠") } else { available += 1 }
        if health.heartRateVariabilityMilliseconds == nil { missing.append("HRV") } else { available += 1 }
        if health.restingHeartRate == nil { missing.append("安静時心拍") } else { available += 1 }
        if input.subjectiveRecovery == nil { missing.append("疲労感") } else { available += 1 }
        if input.workouts.isEmpty { missing.append("トレーニング履歴") } else { available += 1 }

        let level: DailyReadinessLevel
        if input.subjectiveRecovery?.fatigueLevel == 5 || (input.assessment.score ?? 100) < 35 {
            level = .rest
        } else {
            level = switch input.assessment.level {
            case .good: .good
            case .moderate: .normal
            case .recover: .tired
            }
        }

        return DailyReadiness(
            level: level,
            confidence: Double(available) / 5,
            contributingFactors: Array(input.assessment.factors.prefix(5)),
            missingData: missing
        )
    }

    private func makePrimaryAction(
        input: DailyRecommendationInput,
        readiness: DailyReadiness
    ) -> DailyAction {
        if readiness.level == .rest {
            return DailyAction(
                category: .recovery,
                title: "今日は回復を優先",
                targetDescription: "無理をしない",
                completionRule: .recoveryDayObserved,
                destination: .condition,
                priority: 0,
                rationale: "疲労と回復データを踏まえ、負荷を増やさない日を提案しました。"
            )
        }

        if input.plans.isEmpty {
            return DailyAction(
                category: .workout,
                title: "メニューを作って始める",
                targetDescription: "使える器具から提案",
                completionRule: .workoutCompleted(planID: nil),
                destination: .workout(planID: nil),
                priority: 0,
                rationale: "最初のトレーニングを迷わず始められるよう、利用できる器具に合わせてメニューを作成します。"
            )
        }

        if let plan = workoutPlanIfDue(input: input) {
            let isTired = readiness.level == .tired
            return DailyAction(
                category: .workout,
                title: isTired ? "\(plan.name)を軽めに" : plan.name,
                targetDescription: isTired
                    ? "RPEを1段階下げる"
                    : "約\(input.profile.preferredSessionMinutes)分",
                completionRule: .workoutCompleted(planID: plan.id),
                destination: .workout(planID: plan.id),
                priority: 0,
                rationale: workoutRationale(input: input, plan: plan, isTired: isTired)
            )
        }

        let target = stepTarget(profile: input.profile, tired: readiness.level == .tired)
        return DailyAction(
            category: readiness.level == .tired ? .lightActivity : .steps,
            title: readiness.level == .tired ? "軽く身体を動かす" : "\(target.formatted())歩",
            targetDescription: "現在の歩数から自動更新",
            completionRule: .stepsAtLeast(target),
            destination: .steps,
            priority: 0,
            rationale: "今日は筋力トレーニングの間隔を取り、無理のない活動量を優先します。"
        )
    }

    private func supportingActions(input: DailyRecommendationInput) -> [DailyAction] {
        var result: [DailyAction] = []
        let day = calendar.startOfDay(for: input.now)
        let todayMeals = input.meals.filter { calendar.isDate($0.recordedAt, inSameDayAs: day) }
        let protein = todayMeals.reduce(0) { $0 + $1.protein }
        let proteinGoal = input.profile.nutritionGoals.protein

        if proteinGoal > 0, protein < proteinGoal * 0.9 {
            result.append(DailyAction(
                category: .protein,
                title: "タンパク質 \(Int(proteinGoal.rounded()))g",
                targetDescription: "あと\(max(0, Int((proteinGoal - protein).rounded())))g",
                completionRule: .proteinAtLeast(proteinGoal),
                destination: .meal,
                priority: 1,
                rationale: "目標と今日の食事記録から、残りのタンパク質量を表示しています。"
            ))
        }

        if !input.bodyMetrics.contains(where: {
            $0.kind == .bodyWeight && calendar.isDate($0.recordedAt, inSameDayAs: day)
        }) {
            result.append(DailyAction(
                category: .bodyWeight,
                title: "体重を記録",
                targetDescription: "前回値から入力",
                completionRule: .bodyMetricRecorded(.bodyWeight),
                destination: .bodyMetric(.bodyWeight),
                priority: 2,
                rationale: "日々の変化ではなく、週平均の傾向を判断する材料にします。"
            ))
        }

        if isWeeklyMetricDue(kind: .waist, entries: input.bodyMetrics, now: input.now) {
            result.append(DailyAction(
                category: .waist,
                title: "腹囲を記録",
                targetDescription: "週1回の確認",
                completionRule: .bodyMetricRecorded(.waist),
                destination: .bodyMetric(.waist),
                priority: 2,
                rationale: "前回の腹囲記録から7日以上空いています。"
            ))
        }

        if shouldSuggestPhoto(input: input) {
            result.append(DailyAction(
                category: .bodyPhoto,
                title: "体型写真を撮る",
                targetDescription: "週1回・同じ条件で",
                completionRule: .photoSetRecorded,
                destination: .bodyPhoto,
                priority: 2,
                rationale: "見た目の変化を比較できるよう、前回と近い条件で撮影します。"
            ))
        }

        if todayMeals.count < input.profile.nutritionGoals.mealCount {
            result.append(DailyAction(
                category: .mealGuidance,
                title: "食事を撮って記録",
                targetDescription: "\(todayMeals.count) / \(input.profile.nutritionGoals.mealCount)食",
                completionRule: .mealsRecorded(input.profile.nutritionGoals.mealCount),
                destination: .meal,
                priority: 2,
                rationale: "写真から下書きを作り、入力の手間を減らします。"
            ))
        }
        return result
    }

    private func workoutPlanIfDue(input: DailyRecommendationInput) -> TrainingPlan? {
        guard !input.plans.isEmpty else { return nil }
        if input.workouts.contains(where: { calendar.isDate($0.startedAt, inSameDayAs: input.now) && $0.isCompleted }) {
            return nil
        }

        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: input.now)?.start
            ?? calendar.startOfDay(for: input.now)
        let weeklyCount = input.workouts.filter { $0.isCompleted && $0.startedAt >= startOfWeek }.count
        guard weeklyCount < input.profile.weeklyTrainingDays else { return nil }

        if let latest = input.workouts.filter(\.isCompleted).max(by: { $0.startedAt < $1.startedAt }),
           input.now.timeIntervalSince(latest.startedAt) < 20 * 60 * 60 {
            return nil
        }
        return input.selectedPlan ?? input.plans[weeklyCount % input.plans.count]
    }

    private func isWeeklyMetricDue(kind: BodyMetricKind, entries: [BodyMetricEntry], now: Date) -> Bool {
        guard let latest = entries.filter({ $0.kind == kind }).max(by: { $0.recordedAt < $1.recordedAt }) else {
            return true
        }
        return now.timeIntervalSince(latest.recordedAt) >= 7 * 24 * 60 * 60
    }

    private func shouldSuggestPhoto(input: DailyRecommendationInput) -> Bool {
        guard [.diet, .muscleGain, .bodyShape].contains(input.profile.goalType) else { return false }
        guard let latest = input.bodyPhotos.filter({ $0.imageData != nil }).max(by: { $0.recordedAt < $1.recordedAt }) else {
            return true
        }
        return input.now.timeIntervalSince(latest.recordedAt) >= 7 * 24 * 60 * 60
    }

    private func score(_ action: DailyAction, input: DailyRecommendationInput) -> Int {
        let completedHistory = input.previousRecommendations.flatMap(\.actions)
        let completed = completedHistory.filter { $0.category == action.category && $0.status == .completed }.count
        let skipped = completedHistory.filter {
            $0.category == action.category && [.skipped, .replaced].contains($0.status)
        }.count
        let base: Int = switch action.category {
        case .protein: 70
        case .bodyWeight: 60
        case .bodyPhoto, .waist: 55
        case .mealGuidance: 50
        default: 40
        }
        return base + min(10, completed * 2) - min(12, skipped * 3)
    }

    private func stepTarget(profile: UserProfile, tired: Bool) -> Int {
        if tired { return 4_000 }
        return switch profile.goalType {
        case .diet, .health: 8_000
        case .performance: 10_000
        case .muscleGain, .bodyShape: 7_000
        }
    }

    private func workoutRationale(input: DailyRecommendationInput, plan: TrainingPlan, isTired: Bool) -> String {
        if isTired {
            return "回復データが低めのため、\(plan.name)の重量かセット数を抑えます。"
        }
        if let latest = input.workouts.filter(\.isCompleted).max(by: { $0.startedAt < $1.startedAt }) {
            let days = max(0, calendar.dateComponents([.day], from: latest.startedAt, to: input.now).day ?? 0)
            return "前回のトレーニングから\(days)日空き、今週の予定回数に余裕があります。"
        }
        return "設定した目的、利用できる器具、週の運動回数から選びました。"
    }

    private func summary(for readiness: DailyReadiness) -> String {
        switch readiness.level {
        case .good: "通常どおり進められそうです。"
        case .normal: "体調を見ながら予定どおり進めましょう。"
        case .tired: "今日は負荷を少し抑えます。"
        case .rest: "回復を優先する日にしましょう。"
        }
    }
}
