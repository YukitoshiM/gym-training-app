import Foundation
import XCTest
@testable import GymTrainingApp

final class DailyRecommendationEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testLocalRecommendationIsImmediateAndLimitedToThreeActions() throws {
        let now = try date(day: 12, hour: 8)
        let plan = TrainingPlan(name: "背中・肩 45分")
        let input = makeInput(now: now, plans: [plan], selectedPlan: plan)

        let recommendation = DailyRecommendationEngine(calendar: calendar).makeRecommendation(from: input)

        XCTAssertEqual(recommendation.source, .localRule)
        XCTAssertLessThanOrEqual(recommendation.activeActions.count, 3)
        XCTAssertEqual(recommendation.activeActions.first?.category, .workout)
        XCTAssertEqual(recommendation.activeActions.first?.destination, .workout(planID: plan.id))
    }

    func testNoPlanMakesPlanCreationThePrimaryAction() throws {
        let now = try date(day: 12, hour: 8)
        let input = makeInput(now: now, plans: [], selectedPlan: nil)

        let recommendation = DailyRecommendationEngine(calendar: calendar).makeRecommendation(from: input)

        XCTAssertEqual(recommendation.activeActions.first?.category, .workout)
        XCTAssertEqual(recommendation.activeActions.first?.destination, .workout(planID: nil))
        XCTAssertEqual(recommendation.activeActions.first?.title, "メニューを作って始める")
        XCTAssertEqual(recommendation.activeActions.first?.completionRule, .workoutCompleted(planID: nil))
    }

    func testStrongFatigueProducesMachineCheckableRecoveryDay() throws {
        let now = try date(day: 12, hour: 8)
        let input = makeInput(
            now: now,
            plans: [TrainingPlan(name: "脚")],
            subjectiveRecovery: SubjectiveRecoveryEntry(recordedAt: now, fatigueLevel: 5),
            assessment: ReadinessAssessment(
                score: 25,
                level: .recover,
                summary: "回復優先",
                factors: ["疲労感が高めです"],
                availableFactorCount: 1
            )
        )

        let recommendation = DailyRecommendationEngine(calendar: calendar).makeRecommendation(from: input)

        XCTAssertEqual(recommendation.readiness.level, .rest)
        XCTAssertEqual(recommendation.activeActions.first?.category, .recovery)
        XCTAssertEqual(recommendation.activeActions.first?.completionRule, .recoveryDayObserved)
    }

    func testCompletionRulesReadRecordedSourceData() throws {
        let now = try date(day: 12, hour: 21)
        let plan = TrainingPlan(name: "全身")
        let workout = WorkoutSession(
            title: plan.name,
            sourcePlanID: plan.id,
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now,
            exercises: []
        )
        let input = makeInput(
            now: now,
            plans: [plan],
            workouts: [workout],
            meals: [
                MealEntry(recordedAt: now, name: "朝食", protein: 70),
                MealEntry(recordedAt: now, name: "昼食", protein: 50)
            ],
            bodyMetrics: [BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)],
            bodyPhotos: [BodyPhotoEntry(recordedAt: now, angle: .front, imageData: Data([1]))],
            health: DailyHealthSnapshot(generatedAt: now, steps: 8_200, sleepHours: 7.2)
        )
        let actions: [DailyAction] = [
            action(.workout, rule: .workoutCompleted(planID: plan.id)),
            action(.steps, rule: .stepsAtLeast(8_000)),
            action(.protein, rule: .proteinAtLeast(120)),
            action(.mealGuidance, rule: .mealsRecorded(2)),
            action(.bodyWeight, rule: .bodyMetricRecorded(.bodyWeight)),
            action(.bodyPhoto, rule: .photoSetRecorded),
            action(.sleep, rule: .sleepAtLeast(7))
        ]
        let engine = DailyRecommendationEngine(calendar: calendar)

        for action in actions {
            XCTAssertTrue(engine.progress(for: action, input: input).isCompleted, "\(action.category) should be complete")
        }
        XCTAssertFalse(
            engine.progress(for: action(.recovery, rule: .recoveryDayObserved), input: input).isCompleted,
            "A completed workout must prevent a recovery day from auto-completing"
        )
    }

    func testWeeklyMeasurementsAreNotRequestedEarly() throws {
        let now = try date(day: 12, hour: 8)
        let recent = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let input = makeInput(
            now: now,
            bodyMetrics: [
                BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now),
                BodyMetricEntry(kind: .waist, value: 80, recordedAt: recent)
            ],
            bodyPhotos: [BodyPhotoEntry(recordedAt: recent, angle: .front, imageData: Data([1]))]
        )

        let recommendation = DailyRecommendationEngine(calendar: calendar).makeRecommendation(from: input)
        let categories = Set(recommendation.activeActions.map(\.category))

        XCTAssertFalse(categories.contains(.bodyWeight))
        XCTAssertFalse(categories.contains(.waist))
        XCTAssertFalse(categories.contains(.bodyPhoto))
    }

    func testFastWeightTrendCreatesConfirmableCalorieAdjustmentOnlyOnce() throws {
        let now = try date(day: 14, hour: 8)
        var profile = UserProfile.default
        profile.goalType = .diet
        profile.nutritionGoals.calories = 2_000
        let entries = [
            BodyMetricEntry(kind: .bodyWeight, value: 80.2, recordedAt: now.addingTimeInterval(-12 * 86_400)),
            BodyMetricEntry(kind: .bodyWeight, value: 80.0, recordedAt: now.addingTimeInterval(-9 * 86_400)),
            BodyMetricEntry(kind: .bodyWeight, value: 78.5, recordedAt: now.addingTimeInterval(-5 * 86_400)),
            BodyMetricEntry(kind: .bodyWeight, value: 78.1, recordedAt: now.addingTimeInterval(-2 * 86_400))
        ]
        let input = makeInput(now: now, profile: profile, bodyMetrics: entries)
        let engine = DailyRecommendationEngine(calendar: calendar)

        let proposal = try XCTUnwrap(engine.targetAdjustmentProposal(from: input, existing: []))

        XCTAssertEqual(proposal.currentValue, 2_000)
        XCTAssertEqual(proposal.proposedValue, 2_100)
        XCTAssertEqual(proposal.status, .pending)
        XCTAssertNil(engine.targetAdjustmentProposal(from: input, existing: [proposal]))
    }

    @MainActor
    func testCalorieAdjustmentChangesProfileOnlyAfterExplicitAcceptance() throws {
        let storage = TestAppDataRepository()

        var profile = UserProfile.default
        profile.nutritionGoals.calories = 2_000
        storage.saveUserProfile(profile)
        let proposal = TargetAdjustmentProposal(
            kind: .calorieTarget,
            currentValue: 2_000,
            proposedValue: 2_100,
            reason: "確認用"
        )
        storage.saveTargetAdjustmentProposals([proposal])

        let store = AppStore(storage: storage)
        XCTAssertEqual(store.userProfile.nutritionGoals.calories, 2_000)

        store.acceptTargetAdjustmentProposal(proposal.id)

        XCTAssertEqual(store.userProfile.nutritionGoals.calories, 2_100)
        XCTAssertEqual(store.targetAdjustmentProposals.first?.status, .accepted)
    }

    func testAIDraftParserAcceptsCodeFenceAndTypedActions() throws {
        let response = """
        ```json
        {"keep_existing":false,"readiness_level":"tired","summary":"少し軽めにします。","change_reason":"睡眠が短いため","actions":[{"category":"lightActivity","title":"4,000歩","target":4000,"rationale":"回復を優先"}]}
        ```
        """

        let draft = try DailyRecommendationAIDraft.parse(from: response)

        XCTAssertFalse(draft.keepExisting)
        XCTAssertEqual(draft.readinessLevel, .tired)
        XCTAssertEqual(draft.actions.first?.category, .lightActivity)
    }

    func testWatchSnapshotKeepsTodayActionsWithoutWorkoutLibrary() throws {
        let now = try date(day: 12, hour: 8)
        let planID = UUID()
        let recommendation = DailyRecommendation(
            date: now,
            generatedAt: now,
            readiness: DailyReadiness(
                level: .good,
                confidence: 0.8,
                contributingFactors: ["睡眠"],
                missingData: []
            ),
            actions: [
                DailyAction(
                    category: .workout,
                    title: "背中・肩 45分",
                    completionRule: .workoutCompleted(planID: planID),
                    destination: .workout(planID: planID),
                    priority: 0,
                    rationale: "4日空いています"
                ),
                DailyAction(
                    category: .protein,
                    title: "タンパク質 120g",
                    completionRule: .proteinAtLeast(120),
                    destination: .meal,
                    status: .completed,
                    priority: 1,
                    rationale: "目標量"
                )
            ],
            summary: "通常どおり進めます",
            contextVersion: 1,
            source: .localRule
        )

        let snapshot = WatchDailyRecommendationSnapshot(recommendation: recommendation)
        let library = WatchWorkoutPlanLibrarySnapshot(
            plans: [],
            dailyRecommendation: snapshot
        )
        let decoded = try JSONDecoder().decode(
            WatchWorkoutPlanLibrarySnapshot.self,
            from: JSONEncoder().encode(library)
        )

        XCTAssertTrue(decoded.plans.isEmpty)
        XCTAssertEqual(decoded.dailyRecommendation?.readiness, "GOOD")
        XCTAssertEqual(decoded.dailyRecommendation?.actions.count, 2)
        XCTAssertEqual(decoded.dailyRecommendation?.actions[1].isCompleted, true)
        XCTAssertEqual(decoded.dailyRecommendation?.preferredPlanID, planID)
    }

    private func makeInput(
        now: Date,
        profile: UserProfile = .default,
        plans: [TrainingPlan] = [],
        selectedPlan: TrainingPlan? = nil,
        workouts: [WorkoutSession] = [],
        meals: [MealEntry] = [],
        bodyMetrics: [BodyMetricEntry] = [],
        bodyPhotos: [BodyPhotoEntry] = [],
        subjectiveRecovery: SubjectiveRecoveryEntry? = nil,
        health: DailyHealthSnapshot? = nil,
        assessment: ReadinessAssessment? = nil
    ) -> DailyRecommendationInput {
        DailyRecommendationInput(
            now: now,
            profile: profile,
            plans: plans,
            selectedPlan: selectedPlan,
            workouts: workouts,
            meals: meals,
            bodyMetrics: bodyMetrics,
            bodyPhotos: bodyPhotos,
            subjectiveRecovery: subjectiveRecovery,
            health: health ?? DailyHealthSnapshot(generatedAt: now),
            assessment: assessment ?? ReadinessAssessment(
                score: 75,
                level: .good,
                summary: "良好",
                factors: [],
                availableFactorCount: 0
            ),
            previousRecommendations: []
        )
    }

    private func action(_ category: DailyActionCategory, rule: DailyActionCompletionRule) -> DailyAction {
        DailyAction(
            category: category,
            title: category.rawValue,
            completionRule: rule,
            destination: .none,
            priority: 0,
            rationale: "test"
        )
    }

    private func date(day: Int, hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour)))
    }
}
