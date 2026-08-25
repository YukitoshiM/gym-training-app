import XCTest
@testable import GymTrainingApp

@MainActor
final class AppStoreDataManagementTests: XCTestCase {
    func testAllDataExportIncludesDailyWorkoutSelection() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let plan = TrainingPlan(name: "朝のメニュー")
        store.plans = [plan]
        store.dailyWorkoutSelection = DailyWorkoutSelection(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            planID: plan.id
        )

        let data = try store.makeExportData()
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let selection = try XCTUnwrap(payload["dailyWorkoutSelection"] as? [String: Any])

        XCTAssertEqual(payload["schemaVersion"] as? Int, 8)
        XCTAssertEqual(selection["planID"] as? String, plan.id.uuidString)
    }

    func testSameDayWorkoutSessionsRemainIndependentAndOrdered() {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let morning = WorkoutSession(
            title: "朝トレ",
            sourcePlanID: nil,
            startedAt: calendar.date(byAdding: .hour, value: 1, to: day)!,
            endedAt: calendar.date(byAdding: .hour, value: 2, to: day),
            exercises: []
        )
        let evening = WorkoutSession(
            title: "夜トレ",
            sourcePlanID: nil,
            startedAt: calendar.date(byAdding: .hour, value: 8, to: day)!,
            endedAt: calendar.date(byAdding: .hour, value: 9, to: day),
            exercises: []
        )

        store.saveWorkoutHistorySession(morning)
        store.saveWorkoutHistorySession(evening)
        let sessions = store.workoutSessions(on: day)

        XCTAssertEqual(sessions.map(\.id), [evening.id, morning.id])
        XCTAssertEqual(repository.workoutHistory.count, 2)
    }

    func testOneTimeWorkoutDoesNotLinkToAnUnsavedPlan() {
        let store = AppStore(storage: TestAppDataRepository())
        let plan = TrainingPlan(name: "今回だけのメニュー")

        let oneTimeSession = store.makeWorkoutSession(from: plan, linksToSavedPlan: false)
        let savedPlanSession = store.makeWorkoutSession(from: plan)

        XCTAssertNil(oneTimeSession.sourcePlanID)
        XCTAssertEqual(savedPlanSession.sourcePlanID, plan.id)
    }

    func testSavingAIRevisionAsNewKeepsOriginalAndRegeneratesIdentifiers() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let original = TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(
                    exercise: PresetExerciseStore.exercises[0],
                    sortOrder: 0,
                    sets: [PlanSetTarget(setOrder: 0, targetWeight: 60, targetReps: 10)]
                )
            ]
        )
        store.savePlan(original)

        let copy = store.savePlanAsNew(original)

        XCTAssertEqual(store.plans.count, 2)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.exercises[0].id, original.exercises[0].id)
        XCTAssertNotEqual(copy.exercises[0].sets[0].id, original.exercises[0].sets[0].id)
        XCTAssertEqual(copy.exercises[0].sets[0].targetWeight, 60)
        XCTAssertTrue(store.plans.contains(where: { $0.id == original.id }))
    }

    func testCompletedWorkoutCreatesDurablePlanRevisionTrigger() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let plan = revisionTestPlan()
        store.savePlan(plan)
        let session = completedSession(for: plan, achievement: 1, source: .appleWatch)

        store.saveWorkoutHistorySession(session)

        let trigger = try XCTUnwrap(store.pendingPlanRevision(for: session.id))
        XCTAssertEqual(trigger.originalPlan.id, plan.id)
        XCTAssertEqual(trigger.baselineAchievementRate, 1)
        XCTAssertEqual(repository.planRevisionProposals.first?.id, trigger.id)
    }

    func testAcceptedPlanRevisionPersistsAndCanBeRevertedAfterReload() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let original = revisionTestPlan(weight: 60)
        store.savePlan(original)
        let session = completedSession(for: original, achievement: 1)
        store.finishWorkout(session)
        var revised = original
        revised.exercises[0].sets[0].targetWeight = 62.5

        let record = store.acceptPlanRevision(
            triggerSession: session,
            originalPlan: original,
            revisedPlan: revised,
            asNew: false,
            summary: "次回は62.5kg"
        )
        let reloaded = AppStore(storage: repository)
        XCTAssertEqual(reloaded.plans.first(where: { $0.id == original.id })?.exercises[0].sets[0].targetWeight, 62.5)
        XCTAssertEqual(reloaded.planRevisionProposals.first?.decision, .acceptedAsUpdate)

        reloaded.revertPlanRevision(record.id)

        XCTAssertEqual(reloaded.plans.first(where: { $0.id == original.id })?.exercises[0].sets[0].targetWeight, 60)
        XCTAssertEqual(repository.planRevisionProposals.first?.decision, .reverted)
    }

    func testLaterWorkoutEvaluatesAcceptedRevisionEffectiveness() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let plan = revisionTestPlan()
        store.savePlan(plan)
        let baseline = completedSession(for: plan, achievement: 0.6)
        store.finishWorkout(baseline)
        _ = store.acceptPlanRevision(
            triggerSession: baseline,
            originalPlan: plan,
            revisedPlan: plan,
            asNew: false,
            summary: "負荷を維持"
        )
        var followUp = completedSession(for: plan, achievement: 1)
        followUp.startedAt = Date().addingTimeInterval(1)

        store.finishWorkout(followUp)

        let evaluated = try XCTUnwrap(store.planRevisionProposals.first { $0.triggerSessionID == baseline.id })
        XCTAssertEqual(evaluated.effectiveness, .improved)
        XCTAssertEqual(evaluated.evaluatedSessionID, followUp.id)
    }

    func testActiveWorkoutAutosavesAndRestoresAsInterruptedAfterReload() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        var session = WorkoutSession(plan: revisionTestPlan())
        _ = store.beginOrResumeWorkout(session)
        session.exercises[0].sets[0].actualWeight = 61.2
        session.exercises[0].sets[0].actualReps = 8
        let restEnd = Date().addingTimeInterval(90)
        store.updateActiveWorkout(
            session,
            restTimerEndAt: restEnd,
            restExerciseID: session.exercises[0].id
        )

        let restored = AppStore(storage: repository)
        let active = try XCTUnwrap(restored.activeWorkoutSession)

        XCTAssertEqual(active.state, .interrupted)
        XCTAssertEqual(active.session.exercises[0].sets[0].actualWeight, 61.2)
        XCTAssertEqual(active.session.exercises[0].sets[0].actualReps, 8)
        XCTAssertEqual(active.restTimerEndAt, restEnd)
        XCTAssertGreaterThan(active.revision, 1)
    }

    func testStartingAnotherWorkoutKeepsExistingRecoverableSession() {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let first = WorkoutSession(title: "進行中", sourcePlanID: nil, exercises: [])
        let second = WorkoutSession(title: "別メニュー", sourcePlanID: nil, exercises: [])

        _ = store.beginOrResumeWorkout(first)
        let selected = store.beginOrResumeWorkout(second)

        XCTAssertEqual(selected.id, first.id)
        XCTAssertEqual(repository.activeWorkoutSession?.id, first.id)
    }

    func testFinishingWorkoutClearsDurableActiveSession() {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let session = WorkoutSession(title: "完了する", sourcePlanID: nil, exercises: [])
        _ = store.beginOrResumeWorkout(session)

        store.finishWorkout(session)

        XCTAssertNil(store.activeWorkoutSession)
        XCTAssertNil(repository.activeWorkoutSession)
        XCTAssertEqual(store.workoutHistory.first?.id, session.id)
    }

    func testDiscardedActiveWorkoutCanBeRestoredForResumeAfterReload() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        var session = WorkoutSession(plan: revisionTestPlan())
        session.exercises[0].sets[0].actualReps = 7
        _ = store.beginOrResumeWorkout(session)

        _ = store.discardActiveWorkout()
        XCTAssertNil(store.activeWorkoutSession)
        XCTAssertEqual(store.deletedRecords.count, 1)

        let reloaded = AppStore(storage: repository)
        let deletedID = try XCTUnwrap(reloaded.deletedRecords.first?.id)
        XCTAssertTrue(reloaded.restoreDeletedRecord(deletedID))
        XCTAssertEqual(reloaded.activeWorkoutSession?.state, .paused)
        XCTAssertEqual(reloaded.activeWorkoutSession?.session.exercises[0].sets[0].actualReps, 7)
        XCTAssertTrue(reloaded.deletedRecords.isEmpty)
    }

    func testDeletedMealMovesToDurableTrashAndRestoresWithoutDuplication() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let meal = MealEntry(name: "昼食", calories: 600)
        store.saveMealEntry(meal)

        store.deleteMealEntries(at: IndexSet(integer: 0))
        XCTAssertTrue(store.mealEntries.isEmpty)

        let reloaded = AppStore(storage: repository)
        let deletedID = try XCTUnwrap(reloaded.deletedRecords.first?.id)
        XCTAssertTrue(reloaded.restoreDeletedRecord(deletedID))
        XCTAssertEqual(reloaded.mealEntries.map(\.id), [meal.id])

        reloaded.moveToTrash(title: meal.name, payload: .meal(meal))
        let duplicateID = try XCTUnwrap(reloaded.deletedRecords.first?.id)
        XCTAssertTrue(reloaded.restoreDeletedRecord(duplicateID))
        XCTAssertEqual(reloaded.mealEntries.filter { $0.id == meal.id }.count, 1)
    }

    func testTrashPurgesRecordsOlderThanThirtyDaysOnReload() {
        let repository = TestAppDataRepository()
        repository.deletedRecords = [
            DeletedRecord(
                deletedAt: Date().addingTimeInterval(-31 * 86_400),
                title: "古い記録",
                payload: .workout(WorkoutSession(title: "古い記録", sourcePlanID: nil, exercises: []))
            )
        ]

        let store = AppStore(storage: repository)

        XCTAssertTrue(store.deletedRecords.isEmpty)
        XCTAssertTrue(repository.deletedRecords.isEmpty)
    }

    func testEditingRecordsImmediatelyRecomputesDerivedValues() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let metricID = UUID()
        store.saveBodyMetricEntry(BodyMetricEntry(id: metricID, kind: .bodyWeight, value: 70))
        store.saveBodyMetricEntry(BodyMetricEntry(id: metricID, kind: .bodyWeight, value: 69.4))

        let mealID = UUID()
        store.saveMealEntry(MealEntry(id: mealID, name: "昼食", calories: 500, protein: 20))
        store.saveMealEntry(MealEntry(id: mealID, name: "昼食", calories: 650, protein: 35))
        let nutrition = DailyNutritionProgress(
            meals: store.mealEntries(on: Date()),
            goals: store.userProfile.nutritionGoals
        )

        var workout = completedSession(for: revisionTestPlan(), achievement: 1)
        workout.exercises[0].sets[0].actualWeight = 60
        store.saveWorkoutHistorySession(workout)
        let originalVolume = try XCTUnwrap(store.workoutHistory.first).totalVolume
        workout.exercises[0].sets[0].actualWeight = 65
        store.saveWorkoutHistorySession(workout)

        XCTAssertEqual(store.bodyMetricEntries.count, 1)
        XCTAssertEqual(store.latestBodyMetricEntry(for: .bodyWeight)?.value, 69.4)
        XCTAssertEqual(store.mealEntries.count, 1)
        XCTAssertEqual(nutrition.calories, 650)
        XCTAssertEqual(nutrition.protein, 35)
        XCTAssertGreaterThan(try XCTUnwrap(store.workoutHistory.first).totalVolume, originalVolume)
    }

    func testExportIncludesActiveWorkoutAndTrash() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let session = WorkoutSession(title: "途中", sourcePlanID: nil, exercises: [])
        _ = store.beginOrResumeWorkout(session)
        store.moveToTrash(title: "削除済み", payload: .workout(session))

        let data = try store.makeExportData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GymDataExport.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 8)
        XCTAssertEqual(decoded.activeWorkoutSession?.id, session.id)
        XCTAssertEqual(decoded.deletedRecords.count, 1)
    }

    private func revisionTestPlan(weight: Double = 60) -> TrainingPlan {
        TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(
                    exercise: PresetExerciseStore.exercises[0],
                    sortOrder: 0,
                    sets: [PlanSetTarget(setOrder: 0, targetWeight: weight, targetReps: 10)]
                )
            ]
        )
    }

    private func completedSession(
        for plan: TrainingPlan,
        achievement: Double,
        source: WorkoutSourceDevice = .iPhone
    ) -> WorkoutSession {
        var session = WorkoutSession(plan: plan)
        session.sourceDevice = source
        session.endedAt = Date()
        for exerciseIndex in session.exercises.indices {
            for setIndex in session.exercises[exerciseIndex].sets.indices {
                let target = session.exercises[exerciseIndex].sets[setIndex].targetReps
                session.exercises[exerciseIndex].sets[setIndex].actualReps = Int((Double(target) * achievement).rounded())
                session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
            }
        }
        return session
    }
}

final class HistoryPeriodComparisonTests: XCTestCase {
    func testComparisonUsesAdjacentEqualWindowsAndBuildsMovingAverage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 14)))
        let sessions = [
            session(on: date(2026, 1, 3, calendar: calendar), volume: 100),
            session(on: date(2026, 1, 10, calendar: calendar), volume: 200),
            session(on: date(2026, 1, 14, calendar: calendar), volume: 300)
        ]

        let comparison = HistoryPeriodComparison.make(
            sessions: sessions,
            window: .week,
            endingAt: endDate,
            calendar: calendar
        )

        XCTAssertEqual(comparison.current.sessionCount, 2)
        XCTAssertEqual(comparison.current.totalVolume, 500, accuracy: 0.001)
        XCTAssertEqual(comparison.current.averageVolumePerSession, 250, accuracy: 0.001)
        XCTAssertEqual(comparison.previous.sessionCount, 1)
        XCTAssertEqual(comparison.previous.totalVolume, 100, accuracy: 0.001)
        XCTAssertEqual(comparison.points.count, 7)
        XCTAssertEqual(comparison.points.last?.movingAverage ?? -1, 500 / 7, accuracy: 0.001)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func session(on date: Date, volume: Double) -> WorkoutSession {
        let set = WorkoutSet(
            setOrder: 1,
            targetWeight: volume,
            targetReps: 1,
            actualWeight: volume,
            actualReps: 1,
            isCompleted: true
        )
        let exercise = WorkoutExercise(
            exercise: Exercise(
                name: "Test",
                primaryMuscle: .fullBody,
                equipment: .bodyweight,
                instruction: ""
            ),
            sortOrder: 0,
            restSeconds: 0,
            sets: [set]
        )
        return WorkoutSession(
            title: "Test",
            sourcePlanID: nil,
            startedAt: date,
            endedAt: date,
            exercises: [exercise]
        )
    }
}
