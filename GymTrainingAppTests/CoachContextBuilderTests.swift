import XCTest
@testable import GymTrainingApp

final class CoachContextBuilderTests: XCTestCase {
    func testMemoryStoreRequiresApprovalAndRemovesDuplicates() {
        let store = CoachMemoryStore()
        let existing = [CoachMemory(content: "重量は小刻みに上げたい")]
        let candidates = [
            CoachMemoryCandidate(content: "  重量は小刻みに上げたい  ", reason: "重複"),
            CoachMemoryCandidate(content: "火曜日は脚を行う", reason: "週間提案")
        ]

        let newCandidates = store.candidatesNotAlreadyStored(candidates, memories: existing)

        XCTAssertEqual(newCandidates.map(\.content), ["火曜日は脚を行う"])
        XCTAssertEqual(existing.count, 1)
        let approved = store.approving(newCandidates[0], in: existing)
        XCTAssertEqual(approved.count, 2)
        XCTAssertEqual(approved.first?.content, "火曜日は脚を行う")
    }

    func testContextBuilderIncludesAllowedRecordsAndApprovedMemories() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let exercise = Exercise(
            name: "ベンチプレス",
            primaryMuscle: .chest,
            equipment: .barbell,
            instruction: ""
        )
        let workout = WorkoutSession(
            title: "胸の日",
            sourcePlanID: nil,
            startedAt: now.addingTimeInterval(-86_400),
            endedAt: now.addingTimeInterval(-85_000),
            exercises: [
                WorkoutExercise(
                    exercise: exercise,
                    sortOrder: 0,
                    restSeconds: 90,
                    sets: [
                        WorkoutSet(
                            setOrder: 1,
                            targetWeight: 60,
                            targetReps: 10,
                            actualWeight: 60,
                            actualReps: 10,
                            isCompleted: true,
                            rpe: 7
                        )
                    ]
                )
            ]
        )

        var sharing = AIDataSharingSettings.default
        sharing.sleepAndRecovery = true
        sharing.dailyActivity = true
        let context = makeBuilder(now: now).build(
            profile: .default,
            sharing: sharing,
            bodyMetrics: [BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)],
            bodyMetricGoals: [BodyMetricGoal(kind: .bodyWeight, targetValue: 68)],
            meals: [MealEntry(recordedAt: now, mealType: .lunch, name: "定食", calories: 600)],
            bodyPhotos: [BodyPhotoEntry(recordedAt: now, angle: .front, memo: "姿勢を揃えた")],
            workouts: [workout],
            gymVisits: [],
            subjectiveRecovery: [SubjectiveRecoveryEntry(recordedAt: now, fatigueLevel: 4)],
            healthSnapshot: .empty,
            recoveryHistory: [
                DailyRecoveryTrendRecord(
                    date: now,
                    sleepHours: 6.5,
                    restingHeartRateDelta: 3,
                    hrvRatio: 0.86,
                    activeEnergyKilocalories: 420
                )
            ],
            memories: [CoachMemory(content: "重量は小刻みに上げたい")],
            insights: []
        )

        XCTAssertTrue(context.recent7Days["ベンチプレス"]?.first?.contains("60kg x 10回") == true)
        XCTAssertTrue(context.recent7Days["身体KPI"]?.first?.contains("70kg") == true)
        XCTAssertTrue(context.recent7Days["食事"]?.first?.contains("600kcal") == true)
        XCTAssertTrue(context.recent7Days["体型写真"]?.first?.contains("姿勢を揃えた") == true)
        XCTAssertTrue(context.recent7Days["回復トレンド"]?.first?.contains("睡眠6.5時間") == true)
        XCTAssertTrue(context.recent7Days["記録状況"]?.contains(where: { $0.contains("不足情報は推測で断定せず") }) == true)
        XCTAssertEqual(context.memories, ["重量は小刻みに上げたい"])
        XCTAssertTrue(context.personalRecords.first?.contains("ベンチプレス") == true)
    }

    func testContextBuilderExcludesDisabledCategories() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sharing = AIDataSharingSettings(
            bodyMetrics: false,
            meals: false,
            workouts: false,
            bodyPhotos: false,
            sleepAndRecovery: false,
            dailyActivity: false,
            gymVisits: false,
            workoutSensors: false
        )

        let context = makeBuilder(now: now).build(
            profile: .default,
            sharing: sharing,
            bodyMetrics: [BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)],
            bodyMetricGoals: [],
            meals: [MealEntry(recordedAt: now, name: "定食", calories: 600)],
            bodyPhotos: [BodyPhotoEntry(recordedAt: now, memo: "記録")],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [CoachMemory(content: "承認済みの記憶")],
            insights: []
        )

        XCTAssertEqual(context.recent7Days.keys.sorted(), ["記録状況"])
        XCTAssertTrue(context.recent7Days["記録状況"]?.contains(where: { $0.contains("共有設定がオフ") }) == true)
        XCTAssertTrue(context.personalRecords.isEmpty)
        XCTAssertEqual(context.goals, ["目的: 体型改善", "目指すスタイル: 引き締まった筋肉"])
        XCTAssertEqual(context.memories, ["承認済みの記憶"])
    }

    func testCoverageIdentifiesGoalSpecificMissingRecords() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = UserProfile(
            goalType: .muscleGain,
            coachType: .hypertrophy,
            heightCm: 170,
            birthYear: 1990,
            sex: .unspecified,
            experienceLevel: .intermediate,
            weightUnit: .kg
        )

        var sharing = AIDataSharingSettings.default
        sharing.sleepAndRecovery = true
        let coverage = makeBuilder(now: now).coverage(
            profile: profile,
            sharing: sharing,
            bodyMetrics: [BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            subjectiveRecovery: [SubjectiveRecoveryEntry(recordedAt: now, fatigueLevel: 4)],
            healthSnapshot: .empty,
            recoveryHistory: []
        )

        XCTAssertEqual(coverage.items.first(where: { $0.id == "profile" })?.state, .ready)
        XCTAssertEqual(coverage.items.first(where: { $0.id == "body_metrics" })?.state, .ready)
        XCTAssertEqual(coverage.items.first(where: { $0.id == "meals" })?.state, .needsRecord)
        XCTAssertEqual(coverage.items.first(where: { $0.id == "workouts" })?.state, .needsRecord)
        XCTAssertTrue(coverage.contextLines.contains(where: { $0.contains("睡眠") }))
    }

    func testContextBuilderIncludesOutcomeAndTrainingPace() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let profile = UserProfile(
            goalType: .muscleGain,
            coachType: .hypertrophy,
            outcomeStyle: .vShape,
            focusMuscles: [.shoulders, .back],
            weeklyTrainingDays: 4,
            preferredSessionMinutes: 75,
            heightCm: nil,
            birthYear: nil,
            sex: .unspecified,
            experienceLevel: .intermediate,
            weightUnit: .kg
        )

        let context = makeBuilder(now: now).build(
            profile: profile,
            sharing: .default,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: []
        )

        XCTAssertTrue(context.goals.contains("目指すスタイル: Vシェイプ"))
        XCTAssertTrue(context.goals.contains(where: { $0.contains("重点部位:") && $0.contains("肩") && $0.contains("背中") }))
        XCTAssertTrue(context.preferences.contains("希望ペース: 週4日・1回75分"))
    }

    func testHealthIntakeIsIncludedOnlyWithExplicitSharing() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var profile = UserProfile.default
        profile.healthIntake = HealthIntakeProfile(
            activityLevel: .regular,
            plannedIntensity: .vigorous,
            safetyStatus: .hasConsiderations,
            considerations: [.jointOrMuscleDiscomfort],
            typicalSleep: .sixToSeven,
            goalFocus: .physiqueChange,
            nutritionGuidanceMode: .avoidCalorieFocus,
            otherTrainingDays: nil,
            sportOrActivity: "",
            note: "深い屈伸は避ける"
        )
        var shared = AIDataSharingSettings.default
        shared.trainingConsiderations = true
        let builder = makeBuilder(now: now)

        let included = builder.build(
            profile: profile,
            sharing: shared,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: []
        )
        var hiddenSharing = shared
        hiddenSharing.trainingConsiderations = false
        let hidden = builder.build(
            profile: profile,
            sharing: hiddenSharing,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: []
        )

        XCTAssertTrue(included.preferences.contains(where: { $0.contains("関節・筋肉") }))
        XCTAssertTrue(included.preferences.contains(where: { $0.contains("深い屈伸") }))
        XCTAssertFalse(hidden.preferences.contains(where: { $0.contains("関節・筋肉") }))
        XCTAssertFalse(hidden.preferences.contains(where: { $0.contains("深い屈伸") }))
    }

    func testBodyPhotoContextUsesThirtyDayLookback() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let included = now.addingTimeInterval(-8 * 86_400)
        let excluded = now.addingTimeInterval(-31 * 86_400)
        let context = makeBuilder(now: now).build(
            profile: .default,
            sharing: .default,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [
                BodyPhotoEntry(recordedAt: included, angle: .front, memo: "30日内"),
                BodyPhotoEntry(recordedAt: excluded, angle: .side, memo: "30日外")
            ],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: []
        )

        let photos = context.recent7Days["体型写真"] ?? []
        XCTAssertEqual(photos.count, 1)
        XCTAssertTrue(photos[0].contains("30日内"))
        XCTAssertFalse(photos[0].contains("30日外"))
    }

    func testContextIncludesBoundedRecommendationRevisionAndReview() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var workout = dailyAction(category: .workout, title: "背中・肩", priority: 0)
        workout.status = .completed
        workout.adoptedAt = now.addingTimeInterval(-600)
        var protein = dailyAction(category: .protein, title: "タンパク質150g", priority: 1)
        protein.status = .skipped
        let recommendation = dailyRecommendation(now: now, actions: [workout, protein])
        let revision = RecommendationRevision(
            date: now,
            timestamp: now.addingTimeInterval(-300),
            previousActions: [workout],
            newActions: [workout, protein],
            reason: "自由文の理由は共有しない",
            source: .ai
        )
        let review = DailyReview(
            date: now,
            generatedAt: now.addingTimeInterval(-60),
            completedActionIDs: [workout.id],
            skippedActionIDs: [protein.id],
            summary: "1 / 2達成。明日に反映します。",
            nextDayAdjustments: []
        )
        let builder = makeBuilder(
            now: now,
            recommendations: [recommendation],
            revisions: [revision],
            reviews: [review]
        )

        let context = emptyContext(builder: builder)

        XCTAssertEqual(context.previousSuggestion["date"], day(now))
        XCTAssertEqual(context.previousSuggestion["revision_source"], "ai")
        XCTAssertTrue(context.previousSuggestion["actions"]?.contains("背中・肩") == true)
        XCTAssertTrue(context.previousSuggestion["actions"]?.contains("タンパク質150g") == true)
        XCTAssertNil(context.previousSuggestion["revision_reason"])
        XCTAssertEqual(context.suggestionResult["completion"], "1/2")
        XCTAssertEqual(context.suggestionResult["adopted"], "1/2")
        XCTAssertEqual(context.suggestionResult["completed_actions"], "背中・肩")
        XCTAssertEqual(context.suggestionResult["skipped_actions"], "タンパク質150g")
        XCTAssertEqual(context.suggestionResult["review"], "1 / 2達成。明日に反映します。")
    }

    func testRecommendationContextHonorsCategorySharingGates() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var workout = dailyAction(category: .workout, title: "非共有の筋トレ", priority: 0)
        workout.status = .completed
        var protein = dailyAction(category: .protein, title: "共有する食事", priority: 1)
        protein.status = .skipped
        let recommendation = dailyRecommendation(now: now, actions: [workout, protein])
        let revision = RecommendationRevision(
            date: now,
            timestamp: now.addingTimeInterval(-60),
            previousActions: [workout],
            newActions: [workout, protein],
            reason: "睡眠不足を理由に筋トレを変更",
            source: .ai
        )
        let review = DailyReview(
            date: now,
            generatedAt: now,
            completedActionIDs: [workout.id],
            skippedActionIDs: [protein.id],
            summary: "今日の結果です。",
            nextDayAdjustments: ["非共有の筋トレを翌日に再配置"]
        )
        var sharing = AIDataSharingSettings.default
        sharing.workouts = false
        let builder = makeBuilder(
            now: now,
            recommendations: [recommendation],
            revisions: [revision],
            reviews: [review]
        )

        let context = emptyContext(builder: builder, sharing: sharing)
        let transmitted = Array(context.previousSuggestion.values) + Array(context.suggestionResult.values)

        XCTAssertTrue(context.previousSuggestion["actions"]?.contains("共有する食事") == true)
        XCTAssertFalse(transmitted.contains(where: { $0.contains("非共有の筋トレ") }))
        XCTAssertFalse(transmitted.contains(where: { $0.contains("睡眠不足") }))
        XCTAssertEqual(context.suggestionResult["completion"], "0/1")
        XCTAssertEqual(context.suggestionResult["skipped_actions"], "共有する食事")
        XCTAssertNil(context.suggestionResult["review"])
    }

    func testContextBuilderIncludesLatestPlanRevisionOutcomeOnlyWhenWorkoutSharingIsEnabled() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let plan = TrainingPlan(name: "背中の日")
        let revision = PlanRevisionProposal(
            createdAt: now,
            triggerSessionID: UUID(),
            originalPlan: plan,
            revisedPlan: TrainingPlan(name: "背中の日 改訂版"),
            summary: "達成率に合わせて重量を調整",
            decision: .acceptedAsUpdate,
            baselineAchievementRate: 0.8,
            effectiveness: .improved
        )
        let builder = makeBuilder(now: now)

        let shared = builder.build(
            profile: .default,
            sharing: .default,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: [],
            planRevisions: [revision]
        )
        XCTAssertEqual(shared.previousSuggestion["plan_revision"], "達成率に合わせて重量を調整")
        XCTAssertEqual(shared.previousSuggestion["revised_plan"], "背中の日 改訂版")
        XCTAssertEqual(shared.suggestionResult["plan_revision_effectiveness"], "improved")

        var privateSharing = AIDataSharingSettings.default
        privateSharing.workouts = false
        let hidden = builder.build(
            profile: .default,
            sharing: privateSharing,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: [],
            planRevisions: [revision]
        )
        XCTAssertNil(hidden.previousSuggestion["plan_revision"])
        XCTAssertNil(hidden.suggestionResult["plan_revision_effectiveness"])
    }

    private func makeBuilder(
        now: Date,
        recommendations: [DailyRecommendation] = [],
        revisions: [RecommendationRevision] = [],
        reviews: [DailyReview] = []
    ) -> CoachContextBuilder {
        CoachContextBuilder(now: now) {
            (recommendations, revisions, reviews)
        }
    }

    private func emptyContext(
        builder: CoachContextBuilder,
        sharing: AIDataSharingSettings = .default
    ) -> CoachContext {
        builder.build(
            profile: .default,
            sharing: sharing,
            bodyMetrics: [],
            bodyMetricGoals: [],
            meals: [],
            bodyPhotos: [],
            workouts: [],
            gymVisits: [],
            subjectiveRecovery: [],
            healthSnapshot: .empty,
            recoveryHistory: [],
            memories: [],
            insights: []
        )
    }

    private func dailyRecommendation(now: Date, actions: [DailyAction]) -> DailyRecommendation {
        DailyRecommendation(
            date: now,
            generatedAt: now.addingTimeInterval(-900),
            readiness: DailyReadiness(level: .normal, confidence: 0.8, contributingFactors: [], missingData: []),
            actions: actions,
            summary: "今日の提案",
            contextVersion: 1,
            source: .mixed
        )
    }

    private func dailyAction(
        category: DailyActionCategory,
        title: String,
        priority: Int
    ) -> DailyAction {
        DailyAction(
            category: category,
            title: title,
            targetDescription: "目標",
            completionRule: .manuallyConfirmed,
            destination: .none,
            priority: priority,
            rationale: "理由"
        )
    }

    private func day(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
