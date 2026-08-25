import Foundation

enum DailyRecommendationAICreditPolicy {
    static let automaticUseKey = "bodymode.omakase.automaticAICreditUse"

    static func allowsAutomaticUse(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: automaticUseKey)
    }
}

enum DailyRecommendationPersonalizationStore {
    static let enabledKey = "bodymode.omakase.behaviorLearningEnabled"
    static let resetDateKey = "bodymode.omakase.behaviorLearningResetDate"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func reset(defaults: UserDefaults = .standard, at date: Date = Date()) {
        defaults.set(date, forKey: resetDateKey)
    }

    static func history(
        from recommendations: [DailyRecommendation],
        defaults: UserDefaults = .standard
    ) -> [DailyRecommendation] {
        guard isEnabled(defaults: defaults) else { return [] }
        guard let resetDate = defaults.object(forKey: resetDateKey) as? Date else {
            return recommendations
        }
        return recommendations.filter { $0.date >= resetDate }
    }

    static func summary(
        from recommendations: [DailyRecommendation],
        defaults: UserDefaults = .standard
    ) -> String {
        let actions = history(from: recommendations, defaults: defaults).flatMap(\.actions)
        guard !actions.isEmpty else { return L10n.string("health_meals_body_ai.a553bc46de29", fallback: "まだ学習データはありません。") }

        let grouped = Dictionary(grouping: actions, by: \.category)
        let favorite = grouped.max { left, right in
            completedRate(left.value) < completedRate(right.value)
        }
        let avoided = grouped.max { left, right in
            skippedRate(left.value) < skippedRate(right.value)
        }
        var parts: [String] = []
        if let favorite, favorite.value.contains(where: { $0.status == .completed }) {
            parts.append(L10n.string("health_meals_body_ai.a08a51f7e427", fallback: "完了しやすい項目: {{value1}}", values: [String(describing: displayName(favorite.key))]))
        }
        if let avoided, avoided.value.contains(where: { $0.status == .skipped }) {
            parts.append(L10n.string("health_meals_body_ai.1f60ca761ad5", fallback: "後回しにしやすい項目: {{value1}}", values: [String(describing: displayName(avoided.key))]))
        }
        return parts.isEmpty ? L10n.string("health_meals_body_ai.0bf9b10cad35", fallback: "完了・スキップの傾向を端末内で確認中です。") : parts.joined(separator: " / ")
    }

    static func evaluation(
        recommendations: [DailyRecommendation],
        revisions: [RecommendationRevision],
        defaults: UserDefaults = .standard
    ) -> DailyRecommendationEvaluation {
        let source = history(from: recommendations, defaults: defaults)
        let actions = source.flatMap(\.activeActions)
        let resetDate = defaults.object(forKey: resetDateKey) as? Date ?? .distantPast
        let relevantRevisions = revisions.filter { $0.timestamp >= resetDate }
        let calendar = Calendar.current
        let activeDays = Set(source.map { calendar.startOfDay(for: $0.date) })
        let aiRevisionDays = Set(
            relevantRevisions
                .filter { $0.source == .ai }
                .map { calendar.startOfDay(for: $0.date) }
        )
        return DailyRecommendationEvaluation(
            activeDayCount: activeDays.count,
            actionCount: actions.count,
            completedActionCount: actions.filter { $0.status == .completed }.count,
            adoptedActionCount: actions.filter { $0.adoptedAt != nil || $0.status == .completed }.count,
            aiRevisionCount: aiRevisionDays.intersection(activeDays).count
        )
    }

    private static func completedRate(_ actions: [DailyAction]) -> Double {
        Double(actions.filter { $0.status == .completed }.count) / Double(max(1, actions.count))
    }

    private static func skippedRate(_ actions: [DailyAction]) -> Double {
        Double(actions.filter { $0.status == .skipped }.count) / Double(max(1, actions.count))
    }

    private static func displayName(_ category: DailyActionCategory) -> String {
        switch category {
        case .workout: L10n.string("health_meals_body_ai.97bcb3ef255f", fallback: "トレーニング")
        case .steps: L10n.string("health_meals_body_ai.a64954d4ecda", fallback: "歩数")
        case .protein: L10n.string("health_meals_body_ai.140a2c34da87", fallback: "たんぱく質")
        case .mealGuidance: L10n.string("health_meals_body_ai.738844ab541c", fallback: "食事")
        case .bodyWeight: L10n.string("health_meals_body_ai.5f7020cba17f", fallback: "体重")
        case .waist: L10n.string("health_meals_body_ai.0021a0220d44", fallback: "腹囲")
        case .bodyPhoto: L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型写真")
        case .sleep: L10n.string("health_meals_body_ai.8878e4c5b97f", fallback: "睡眠")
        case .recovery: L10n.string("health_meals_body_ai.5602244ffb3a", fallback: "回復")
        case .lightActivity: L10n.string("health_meals_body_ai.6cc0928ab83d", fallback: "軽い運動")
        }
    }
}

struct DailyRecommendationEvaluation: Equatable {
    var activeDayCount: Int
    var actionCount: Int
    var completedActionCount: Int
    var adoptedActionCount: Int
    var aiRevisionCount: Int

    var completionRate: Double {
        Double(completedActionCount) / Double(max(1, actionCount))
    }

    var adoptionRate: Double {
        Double(adoptedActionCount) / Double(max(1, actionCount))
    }

    var aiChangeRate: Double {
        Double(aiRevisionCount) / Double(max(1, activeDayCount))
    }
}
