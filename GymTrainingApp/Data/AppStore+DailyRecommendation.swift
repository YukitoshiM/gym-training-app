import Foundation

@MainActor
extension AppStore {
    func dailyRecommendation(on date: Date = Date()) -> DailyRecommendation? {
        dailyRecommendations.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func dailyReview(on date: Date = Date()) -> DailyReview? {
        dailyReviews.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    @discardableResult
    func refreshDailyRecommendation(
        healthSnapshot: DailyHealthSnapshot,
        readinessAssessment: ReadinessAssessment,
        now: Date = Date(),
        force: Bool = false
    ) -> DailyRecommendation {
        let engine = DailyRecommendationEngine()
        let input = dailyRecommendationInput(
            healthSnapshot: healthSnapshot,
            readinessAssessment: readinessAssessment,
            now: now
        )
        let generated = engine.makeRecommendation(from: input)

        if let index = dailyRecommendations.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: now)
        }), !force {
            var current = dailyRecommendations[index]
            current = synchronized(current, engine: engine, input: input)

            if shouldApplySafetyRevision(from: current.readiness.level, to: generated.readiness.level) {
                let previous = current.actions
                let completed = current.activeActions.filter { $0.status == .completed }
                var revised = generated.actions.filter { candidate in
                    !completed.contains(where: { $0.id == candidate.id || $0.category == candidate.category })
                }
                revised = Array((completed + revised).prefix(3)).enumerated().map { index, action in
                    var action = action
                    action.priority = index
                    return action
                }
                current.actions = revised
                current.readiness = generated.readiness
                current.summary = generated.summary
                current.generatedAt = now
                appendRevision(
                    date: current.date,
                    previous: previous,
                    next: revised,
                    reason: L10n.string("runtime_messages.da73bd0d95fc", fallback: "新しい回復データを反映し、安全側へ今日の提案を調整しました。"),
                    source: .localRule
                )
            } else {
                current.readiness = generated.readiness
            }

            dailyRecommendations[index] = current
            persistRecommendationState()
            updateDailyReview(for: current, at: now)
            refreshTargetAdjustmentProposal(engine: engine, input: input)
            return current
        }

        var recommendation = generated
        recommendation = synchronized(recommendation, engine: engine, input: input)
        if let index = dailyRecommendations.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: now)
        }) {
            let previous = dailyRecommendations[index]
            let completed = previous.activeActions.filter { $0.status == .completed }
            if !completed.isEmpty {
                let unfinished = recommendation.actions.filter { candidate in
                    !completed.contains(where: { $0.id == candidate.id || $0.category == candidate.category })
                }
                recommendation.actions = Array((completed + unfinished).prefix(3)).enumerated().map { offset, action in
                    var action = action
                    action.priority = offset
                    return action
                }
            }
            dailyRecommendations[index] = recommendation
            appendRevision(
                date: recommendation.date,
                previous: previous.actions,
                next: recommendation.actions,
                reason: L10n.string("runtime_messages.eac72f8d78bd", fallback: "ユーザー操作で今日の提案を作り直しました。"),
                source: .user
            )
        } else {
            dailyRecommendations.insert(recommendation, at: 0)
            UsageAnalytics.shared.record(
                .dailyRecommendationGenerated,
                dimension: recommendation.source.rawValue,
                properties: .dailyRecommendation(profile: userProfile, recommendation: recommendation)
            )
        }
        trimDailyRecommendationHistory(now: now)
        persistRecommendationState()
        updateDailyReview(for: recommendation, at: now)
        refreshTargetAdjustmentProposal(engine: engine, input: input)
        return recommendation
    }

    var pendingTargetAdjustmentProposal: TargetAdjustmentProposal? {
        targetAdjustmentProposals.first { $0.status == .pending }
    }

    func acceptTargetAdjustmentProposal(_ id: UUID) {
        guard let index = targetAdjustmentProposals.firstIndex(where: { $0.id == id && $0.status == .pending }) else {
            return
        }
        let proposal = targetAdjustmentProposals[index]
        switch proposal.kind {
        case .calorieTarget:
            var profile = userProfile
            profile.nutritionGoals.calories = proposal.proposedValue
            saveUserProfile(profile)
        }
        targetAdjustmentProposals[index].status = .accepted
        storage.saveTargetAdjustmentProposals(targetAdjustmentProposals)
    }

    func declineTargetAdjustmentProposal(_ id: UUID) {
        guard let index = targetAdjustmentProposals.firstIndex(where: { $0.id == id && $0.status == .pending }) else {
            return
        }
        targetAdjustmentProposals[index].status = .declined
        storage.saveTargetAdjustmentProposals(targetAdjustmentProposals)
    }

    func progress(
        for action: DailyAction,
        healthSnapshot: DailyHealthSnapshot,
        readinessAssessment: ReadinessAssessment,
        now: Date = Date()
    ) -> DailyActionProgress {
        DailyRecommendationEngine().progress(
            for: action,
            input: dailyRecommendationInput(
                healthSnapshot: healthSnapshot,
                readinessAssessment: readinessAssessment,
                now: now
            )
        )
    }

    func toggleManualDailyAction(_ actionID: UUID, now: Date = Date()) {
        guard let recommendationIndex = recommendationIndex(on: now),
              let actionIndex = dailyRecommendations[recommendationIndex].actions.firstIndex(where: { $0.id == actionID }),
              case .manuallyConfirmed = dailyRecommendations[recommendationIndex].actions[actionIndex].completionRule else {
            return
        }

        let wasCompleted = dailyRecommendations[recommendationIndex].actions[actionIndex].status == .completed
        dailyRecommendations[recommendationIndex].actions[actionIndex].status = wasCompleted ? .pending : .completed
        if !wasCompleted {
            dailyRecommendations[recommendationIndex].actions[actionIndex].adoptedAt = now
        }
        if !wasCompleted {
            let recommendation = dailyRecommendations[recommendationIndex]
            let action = recommendation.actions[actionIndex]
            UsageAnalytics.shared.record(
                .dailyActionCompleted,
                dimension: action.category.rawValue,
                properties: .dailyAction(
                    profile: userProfile,
                    recommendation: recommendation,
                    action: action,
                    completionMethod: "manual"
                )
            )
        }
        persistRecommendationState()
        updateDailyReview(for: dailyRecommendations[recommendationIndex], at: now)
    }

    func markDailyActionAdopted(_ actionID: UUID, now: Date = Date()) {
        guard let recommendationIndex = recommendationIndex(on: now),
              let actionIndex = dailyRecommendations[recommendationIndex].actions.firstIndex(where: { $0.id == actionID }),
              dailyRecommendations[recommendationIndex].actions[actionIndex].adoptedAt == nil else {
            return
        }
        dailyRecommendations[recommendationIndex].actions[actionIndex].adoptedAt = now
        persistRecommendationState()
    }

    func replaceDailyAction(
        _ actionID: UUID,
        healthSnapshot: DailyHealthSnapshot,
        readinessAssessment: ReadinessAssessment,
        now: Date = Date()
    ) {
        guard let recommendationIndex = recommendationIndex(on: now),
              let actionIndex = dailyRecommendations[recommendationIndex].actions.firstIndex(where: { $0.id == actionID }) else {
            return
        }
        var recommendation = dailyRecommendations[recommendationIndex]
        let previous = recommendation.actions
        let oldAction = recommendation.actions[actionIndex]
        guard oldAction.status != .completed else { return }

        let engine = DailyRecommendationEngine()
        let input = dailyRecommendationInput(
            healthSnapshot: healthSnapshot,
            readinessAssessment: readinessAssessment,
            now: now
        )
        guard var replacement = engine.replacementAction(
            for: oldAction,
            recommendation: recommendation,
            input: input
        ) else {
            recommendation.actions[actionIndex].status = .skipped
            dailyRecommendations[recommendationIndex] = recommendation
            UsageAnalytics.shared.record(
                .dailyActionDismissed,
                dimension: oldAction.category.rawValue,
                properties: .dailyAction(
                    profile: userProfile,
                    recommendation: recommendation,
                    action: recommendation.actions[actionIndex],
                    reason: "other"
                )
            )
            appendRevision(
                date: recommendation.date,
                previous: previous,
                next: recommendation.actions,
                reason: L10n.string("runtime_messages.f989482e8b85", fallback: "この項目は今日は行わない設定にしました。"),
                source: .user
            )
            persistRecommendationState()
            updateDailyReview(for: recommendation, at: now)
            return
        }

        recommendation.actions[actionIndex].status = .replaced
        replacement.priority = oldAction.priority
        recommendation.actions.append(replacement)
        dailyRecommendations[recommendationIndex] = recommendation
        var replacementProperties = UsageEventProperties.dailyAction(
            profile: userProfile,
            recommendation: recommendation,
            action: replacement,
            reason: "other"
        )
        replacementProperties.fromCategory = oldAction.category.rawValue
        replacementProperties.toCategory = replacement.category.rawValue
        UsageAnalytics.shared.record(
            .dailyActionReplaced,
            dimension: oldAction.category.rawValue,
            properties: replacementProperties
        )
        appendRevision(
            date: recommendation.date,
            previous: previous,
            next: recommendation.actions,
            reason: L10n.string("runtime_messages.88d8bda8617e", fallback: "ユーザーが今日の行動を入れ替えました。"),
            source: .user
        )
        persistRecommendationState()
        updateDailyReview(for: recommendation, at: now)
    }

    func markDailyRecommendationAIRequested(at date: Date = Date()) {
        guard let index = recommendationIndex(on: date) else { return }
        dailyRecommendations[index].aiRequestedAt = Date()
        persistRecommendationState()
    }

    func shouldRequestDailyAIAnalysis(
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard aiSettings.isEnabled,
              DailyRecommendationAICreditPolicy.allowsAutomaticUse(defaults: defaults),
              let recommendation = dailyRecommendation(on: date) else { return false }
        if recommendation.aiEvaluatedAt != nil { return false }
        if let requestedAt = recommendation.aiRequestedAt,
           date.timeIntervalSince(requestedAt) < 30 * 60 {
            return false
        }
        return true
    }

    func applyDailyAIResponse(_ response: String, for date: Date) {
        guard let index = recommendationIndex(on: date) else { return }
        do {
            let draft = try DailyRecommendationAIDraft.parse(from: response)
            var recommendation = dailyRecommendations[index]
            recommendation.aiEvaluatedAt = Date()

            let proposedReadiness = draft.readinessLevel ?? recommendation.readiness.level
            let proposed = aiActions(from: draft, baseline: recommendation)
            let hasMeaningfulChange = !draft.keepExisting
                && !draft.changeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!proposed.isEmpty)
                && (
                    readinessSeverity(proposedReadiness) > readinessSeverity(recommendation.readiness.level)
                    || proposed.map(\.category) != recommendation.activeActions.map(\.category)
                )

            if hasMeaningfulChange {
                let previous = recommendation.actions
                let completed = recommendation.activeActions.filter { $0.status == .completed }
                let mutable = proposed.filter { candidate in
                    !completed.contains(where: { $0.id == candidate.id || $0.category == candidate.category })
                }
                recommendation.actions = Array((completed + mutable).prefix(3)).enumerated().map { offset, action in
                    var action = action
                    action.priority = offset
                    return action
                }
                recommendation.readiness.level = proposedReadiness
                recommendation.summary = draft.summary.isEmpty ? recommendation.summary : draft.summary
                recommendation.source = .mixed
                appendRevision(
                    date: recommendation.date,
                    previous: previous,
                    next: recommendation.actions,
                    reason: draft.changeReason,
                    source: .ai
                )
                UsageAnalytics.shared.record(.dailyRecommendationChanged, dimension: "ai")
            } else {
                recommendation.source = recommendation.source == .localRule ? .mixed : recommendation.source
                if !draft.summary.isEmpty {
                    recommendation.summary = draft.summary
                }
                let rationales = Dictionary(uniqueKeysWithValues: draft.actions.compactMap { draftAction in
                    draftAction.id.map { ($0, draftAction.rationale) }
                })
                for actionIndex in recommendation.actions.indices {
                    if let rationale = rationales[recommendation.actions[actionIndex].id], !rationale.isEmpty {
                        recommendation.actions[actionIndex].rationale = rationale
                    }
                }
            }
            dailyRecommendations[index] = recommendation
            persistRecommendationState()
            updateDailyReview(for: recommendation, at: Date())
        } catch {
            dailyRecommendations[index].aiEvaluatedAt = Date()
            persistRecommendationState()
            AppDiagnostics.shared.record(
                error: error,
                category: "daily_recommendation.ai",
                message: "Failed to apply AI daily recommendation"
            )
        }
    }

    func applyDailyAIResponse(_ response: CoachChatResponse, for date: Date) {
        applyDailyAIResponse(response.reply, for: date)
        if let recommendationIndex = recommendationIndex(on: date) {
            dailyRecommendations[recommendationIndex].evidence = response.evidence
            dailyRecommendations[recommendationIndex].evidenceStatus = response.evidenceStatus
            persistRecommendationState()
        }
        if let proposalIndex = targetAdjustmentProposals.firstIndex(where: { $0.status == .pending }) {
            targetAdjustmentProposals[proposalIndex].evidence = response.evidence
            targetAdjustmentProposals[proposalIndex].evidenceStatus = response.evidenceStatus
            storage.saveTargetAdjustmentProposals(targetAdjustmentProposals)
        }
    }

    func latestRecommendationRevision(on date: Date = Date()) -> RecommendationRevision? {
        recommendationRevisions.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    func dailyRecommendationPrompt(for recommendation: DailyRecommendation) -> String {
        let actions = recommendation.activeActions.map { action in
            "- id=\(action.id.uuidString), category=\(action.category.rawValue), title=\(action.title), target=\(action.targetDescription), rationale=\(action.rationale)"
        }.joined(separator: "\n")
        return """
        [BODYMODE_DAILY_JSON]
        あなたはBodyModeの日次提案を安全側から点検する担当コーチです。
        端末内ルールが作成した今日の提案を、共有済み記録の短期・中期・長期傾向から確認してください。
        科学的根拠が役立つ判断ではEvidence RAGの文献を参照してください。
        小さな差では提案を変更せず、強い疲労、睡眠の大幅悪化、新しい重要記録がある場合だけ変更してください。
        完了済み項目は変更しないでください。医療診断はしないでください。
        titleとrationaleは結論を先にした自然な日本語にしてください。rationaleは、ユーザー自身の記録と行動をつなぐ短い1文にし、論文名や長い説明は含めないでください。

        現在の調子: \(recommendation.readiness.level.rawValue)
        現在の提案:
        \(actions)

        JSONだけを返してください。
        {
          "keep_existing": true,
          "readiness_level": "good|normal|tired|rest",
          "summary": L10n.string("runtime_messages.27857aa2b1ae", fallback: "短い全体コメント"),
          "change_reason": L10n.string("runtime_messages.292ff42d336e", fallback: "変更しない場合は空文字"),
          "actions": [
            {"id":L10n.string("runtime_messages.c9091516c87d", fallback: "既存ID"), "category":L10n.string("runtime_messages.79540619d261", fallback: "既存または必要なカテゴリ"), "title":L10n.string("runtime_messages.f7a8a3bb3767", fallback: "短い行動"), "target":0, "rationale":L10n.string("runtime_messages.1cf9ffa9a2cb", fallback: "なぜこの行動か")}
          ]
        }
        actionsは最大3件。categoryはworkout,steps,protein,mealGuidance,bodyWeight,waist,bodyPhoto,sleep,recovery,lightActivityのみ。
        """
    }

    private func dailyRecommendationInput(
        healthSnapshot: DailyHealthSnapshot,
        readinessAssessment: ReadinessAssessment,
        now: Date
    ) -> DailyRecommendationInput {
        let selectedPlan: TrainingPlan? = dailyWorkoutSelection.flatMap { selection in
            guard Calendar.current.isDate(selection.date, inSameDayAs: now) else { return nil }
            return plans.first { $0.id == selection.planID }
        }
        return DailyRecommendationInput(
            now: now,
            profile: userProfile,
            plans: plans,
            selectedPlan: selectedPlan,
            workouts: workoutHistory,
            meals: mealEntries,
            bodyMetrics: bodyMetricEntries,
            bodyPhotos: bodyPhotoEntries,
            subjectiveRecovery: subjectiveRecoveryEntries.first {
                Calendar.current.isDate($0.recordedAt, inSameDayAs: now)
            },
            health: healthSnapshot,
            assessment: readinessAssessment,
            previousRecommendations: DailyRecommendationPersonalizationStore.history(
                from: dailyRecommendations
            )
        )
    }

    private func synchronized(
        _ recommendation: DailyRecommendation,
        engine: DailyRecommendationEngine,
        input: DailyRecommendationInput
    ) -> DailyRecommendation {
        var result = recommendation
        for index in result.actions.indices {
            let oldStatus = result.actions[index].status
            guard oldStatus != .skipped, oldStatus != .replaced else { continue }
            let progress = engine.progress(for: result.actions[index], input: input)
            if case .manuallyConfirmed = result.actions[index].completionRule {
                continue
            }
            result.actions[index].status = if progress.isCompleted {
                .completed
            } else if progress.current > 0 {
                .inProgress
            } else {
                .pending
            }
            if oldStatus != .completed, result.actions[index].status == .completed {
                UsageAnalytics.shared.record(
                    .dailyActionCompleted,
                    dimension: result.actions[index].category.rawValue,
                    properties: .dailyAction(
                        profile: userProfile,
                        recommendation: result,
                        action: result.actions[index],
                        completionMethod: "automatic"
                    )
                )
            }
        }
        return result
    }

    private func updateDailyReview(for recommendation: DailyRecommendation, at now: Date) {
        let active = recommendation.activeActions
        let completed = active.filter { $0.status == .completed }
        let skipped = recommendation.actions.filter { $0.status == .skipped }
        let summary: String
        if completed.count == active.count, !active.isEmpty {
            summary = L10n.string("runtime_messages.1e9b7e0b1de9", fallback: "今日の3つを達成しました。明日の提案に反映します。")
        } else if completed.isEmpty {
            summary = L10n.string("runtime_messages.a0f36c6cb2d2", fallback: "できるものから1つで十分です。")
        } else {
            summary = L10n.string("runtime_messages.7439490555e5", fallback: "{{value1}} / {{value2}}達成。残りは無理のない範囲で進めましょう。", values: [String(describing: completed.count), String(describing: active.count)])
        }
        let adjustments = skipped.map { L10n.string("runtime_messages.0d127efd525d", fallback: "{{value1}}は再配置せず、本人の選択として扱う", values: [String(describing: $0.title)]) }
        let review = DailyReview(
            date: recommendation.date,
            generatedAt: now,
            completedActionIDs: completed.map(\.id),
            skippedActionIDs: skipped.map(\.id),
            summary: summary,
            nextDayAdjustments: adjustments
        )
        if let index = dailyReviews.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: recommendation.date)
        }) {
            dailyReviews[index] = review
        } else {
            dailyReviews.insert(review, at: 0)
        }
        dailyReviews = Array(dailyReviews.sorted { $0.date > $1.date }.prefix(90))
        storage.saveDailyReviews(dailyReviews)
    }

    private func appendRevision(
        date: Date,
        previous: [DailyAction],
        next: [DailyAction],
        reason: String,
        source: DailyRecommendationSource
    ) {
        recommendationRevisions.insert(
            RecommendationRevision(
                date: date,
                previousActions: previous,
                newActions: next,
                reason: reason,
                source: source
            ),
            at: 0
        )
        recommendationRevisions = Array(recommendationRevisions.prefix(200))
        storage.saveRecommendationRevisions(recommendationRevisions)
    }

    private func persistRecommendationState() {
        dailyRecommendations.sort { $0.date > $1.date }
        storage.saveDailyRecommendations(dailyRecommendations)
    }

    private func refreshTargetAdjustmentProposal(
        engine: DailyRecommendationEngine,
        input: DailyRecommendationInput
    ) {
        guard let proposal = engine.targetAdjustmentProposal(
            from: input,
            existing: targetAdjustmentProposals
        ) else { return }
        targetAdjustmentProposals.insert(proposal, at: 0)
        targetAdjustmentProposals = Array(targetAdjustmentProposals.prefix(50))
        storage.saveTargetAdjustmentProposals(targetAdjustmentProposals)
    }

    private func trimDailyRecommendationHistory(now: Date) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        dailyRecommendations = dailyRecommendations
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    private func recommendationIndex(on date: Date) -> Int? {
        dailyRecommendations.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func shouldApplySafetyRevision(from old: DailyReadinessLevel, to new: DailyReadinessLevel) -> Bool {
        readinessSeverity(new) - readinessSeverity(old) >= 2
    }

    private func readinessSeverity(_ level: DailyReadinessLevel) -> Int {
        switch level {
        case .good: 0
        case .normal: 1
        case .tired: 2
        case .rest: 3
        }
    }

    private func aiActions(
        from draft: DailyRecommendationAIDraft,
        baseline: DailyRecommendation
    ) -> [DailyAction] {
        draft.actions.prefix(3).compactMap { proposal in
            let existing = proposal.id.flatMap { id in baseline.actions.first { $0.id == id } }
                ?? baseline.actions.first { $0.category == proposal.category }
            let id = existing?.id ?? UUID()
            let status = existing?.status ?? .pending
            let target = max(0, proposal.target ?? 0)

            let rule: DailyActionCompletionRule
            let destination: DailyActionDestination
            let targetDescription: String
            switch proposal.category {
            case .workout:
                let planID: UUID? = if case .workout(let id) = existing?.destination { id } else { todayPlan?.id }
                rule = .workoutCompleted(planID: planID)
                destination = .workout(planID: planID)
                targetDescription = existing?.targetDescription ?? L10n.string("runtime_messages.09d55c9613d1", fallback: "今日のメニュー")
            case .steps, .lightActivity:
                let stepTarget = Int(target > 0 ? target : 8_000)
                rule = .stepsAtLeast(stepTarget)
                destination = .steps
                targetDescription = L10n.string("runtime_messages.3e158eb5aa2a", fallback: "{{value1}}歩", values: [String(describing: stepTarget.formatted())])
            case .protein:
                let proteinTarget = target > 0 ? target : userProfile.nutritionGoals.protein
                rule = .proteinAtLeast(proteinTarget)
                destination = .meal
                targetDescription = "P \(Int(proteinTarget.rounded()))g"
            case .mealGuidance:
                let mealTarget = Int(target > 0 ? target : Double(userProfile.nutritionGoals.mealCount))
                rule = .mealsRecorded(mealTarget)
                destination = .meal
                targetDescription = L10n.string("runtime_messages.28ae9e02d508", fallback: "{{value1}}食", values: [String(describing: mealTarget)])
            case .bodyWeight:
                rule = .bodyMetricRecorded(.bodyWeight)
                destination = .bodyMetric(.bodyWeight)
                targetDescription = L10n.string("runtime_messages.8f99d9e86006", fallback: "今日1回")
            case .waist:
                rule = .bodyMetricRecorded(.waist)
                destination = .bodyMetric(.waist)
                targetDescription = L10n.string("runtime_messages.b5aace88c82a", fallback: "週1回")
            case .bodyPhoto:
                rule = .photoSetRecorded
                destination = .bodyPhoto
                targetDescription = L10n.string("runtime_messages.b5aace88c82a", fallback: "週1回")
            case .sleep:
                let sleepTarget = target > 0 ? target : 7
                rule = .sleepAtLeast(sleepTarget)
                destination = .condition
                targetDescription = L10n.string("runtime_messages.c98c9b59305c", fallback: "{{value1}}時間", values: [String(describing: sleepTarget.formatted(.number.precision(.fractionLength(0...1))))])
            case .recovery:
                rule = .recoveryDayObserved
                destination = .condition
                targetDescription = existing?.targetDescription ?? L10n.string("runtime_messages.3574f4648a2f", fallback: "回復を優先")
            }
            return DailyAction(
                id: id,
                category: proposal.category,
                title: proposal.title,
                targetDescription: targetDescription,
                completionRule: rule,
                destination: destination,
                status: status,
                priority: existing?.priority ?? 2,
                rationale: proposal.rationale
            )
        }
    }
}
