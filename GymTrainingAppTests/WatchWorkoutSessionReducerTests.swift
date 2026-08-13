import XCTest
@testable import GymTrainingApp

final class WatchWorkoutSessionReducerTests: XCTestCase {
    func testSessionStartsFromCurrentPlanTargetsInsteadOfPreviousActuals() {
        let plan = WatchWorkoutPlanSnapshot(
            id: UUID(),
            name: "胸の日",
            weightUnit: .kg,
            exercises: [
                WatchPlanExerciseSnapshot(
                    id: UUID(),
                    exerciseID: UUID(),
                    name: "ベンチプレス",
                    primaryMuscleName: "胸",
                    primaryMuscleRawValue: "chest",
                    equipmentRawValue: "barbell",
                    restSeconds: 90,
                    sets: [
                        WatchPlanSetTargetSnapshot(
                            id: UUID(),
                            setOrder: 1,
                            targetWeight: 60,
                            targetReps: 8,
                            plannedConcentricSeconds: 2,
                            plannedEccentricSeconds: 3,
                            previousActualWeight: 52.5,
                            previousActualReps: 10,
                            previousRPE: 7
                        )
                    ]
                )
            ]
        )

        let session = WatchWorkoutSessionSnapshot(plan: plan)
        let set = session.exercises[0].sets[0]

        XCTAssertEqual(set.targetWeight, 60)
        XCTAssertEqual(set.actualWeight, 60)
        XCTAssertEqual(set.targetReps, 8)
        XCTAssertEqual(set.actualReps, 8)
        XCTAssertEqual(set.rpe, 7)
        XCTAssertEqual(set.plannedConcentricSeconds, 2)
        XCTAssertEqual(set.plannedEccentricSeconds, 3)
    }

    func testAssistedSetAlsoStartsFromNegativePlanTarget() {
        let plan = WatchWorkoutPlanSnapshot(
            id: UUID(),
            name: "背中の日",
            weightUnit: .kg,
            exercises: [
                WatchPlanExerciseSnapshot(
                    id: UUID(),
                    exerciseID: UUID(),
                    name: "アシストチンニング",
                    primaryMuscleName: "背中",
                    primaryMuscleRawValue: "back",
                    equipmentRawValue: "machine",
                    restSeconds: 90,
                    sets: [
                        WatchPlanSetTargetSnapshot(
                            id: UUID(),
                            setOrder: 1,
                            targetWeight: -20,
                            targetReps: 10,
                            previousActualWeight: -30,
                            previousActualReps: 8,
                            previousRPE: nil
                        )
                    ]
                )
            ]
        )

        let set = WatchWorkoutSessionSnapshot(plan: plan).exercises[0].sets[0]

        XCTAssertEqual(set.actualWeight, -20)
        XCTAssertEqual(set.actualReps, 10)
    }

    func testStartingAnotherSetReturnsThePreviousSetToPending() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let firstSetID = session.exercises[0].sets[0].id
        let secondSetID = session.exercises[0].sets[1].id
        let firstStart = Date(timeIntervalSince1970: 100)
        let secondStart = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .startSet(exerciseID: exerciseID, setID: firstSetID, startedAt: firstStart)
        ))
        session.exercises[0].sets[0].rpe = 8
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .startSet(exerciseID: exerciseID, setID: secondSetID, startedAt: secondStart)
        ))

        XCTAssertNil(session.exercises[0].sets[0].startedAt)
        XCTAssertNil(session.exercises[0].sets[0].rpe)
        XCTAssertEqual(session.exercises[0].sets[1].startedAt, secondStart)
    }

    func testWeightUpdateAppliesToEveryIncompleteSetOnly() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let secondSetID = session.exercises[0].sets[1].id
        session.exercises[0].sets[0].isCompleted = true
        session.exercises[0].sets[0].actualWeight = 40
        session.exercises[0].sets[1].startedAt = Date()

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateExerciseWeight(exerciseID: exerciseID, activeSetID: secondSetID, weight: 52.5)
        ))

        XCTAssertEqual(session.exercises[0].sets[0].actualWeight, 40)
        XCTAssertEqual(session.exercises[0].sets[1].actualWeight, 52.5)
        XCTAssertEqual(session.exercises[0].sets[2].actualWeight, 52.5)
    }

    func testStartSetRepairsStaleWeightFromPlanOnFirstStart() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let secondSetID = session.exercises[0].sets[1].id

        session.exercises[0].sets[1].actualWeight = 40
        session.exercises[0].sets[1].actualReps = 6

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .startSet(exerciseID: exerciseID, setID: secondSetID, startedAt: Date(timeIntervalSince1970: 111))
        ))

        XCTAssertEqual(session.exercises[0].sets[1].startedAt, Date(timeIntervalSince1970: 111))
        XCTAssertEqual(session.exercises[0].sets[1].actualWeight, 50)
        XCTAssertEqual(session.exercises[0].sets[1].actualReps, 6)
    }

    func testStartSetPreservesWeightPropagatedByUserInCurrentSession() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let firstSetID = session.exercises[0].sets[0].id
        let secondSetID = session.exercises[0].sets[1].id

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateExerciseWeight(exerciseID: exerciseID, activeSetID: firstSetID, weight: 52.5)
        ))
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .startSet(exerciseID: exerciseID, setID: secondSetID, startedAt: Date())
        ))

        XCTAssertEqual(session.exercises[0].sets[1].actualWeight, 52.5)
        XCTAssertEqual(session.exercises[0].sets[1].hasUserAdjustedWeight, true)
    }

    func testEditableValuesAndCompletionAreReducedTogether() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let setID = session.exercises[0].sets[0].id
        let completedAt = Date(timeIntervalSince1970: 300)

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .startSet(exerciseID: exerciseID, setID: setID, startedAt: completedAt)
        ))
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateReps(exerciseID: exerciseID, setID: setID, reps: 1_200)
        ))
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateRPE(exerciseID: exerciseID, setID: setID, rpe: 8.24)
        ))
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .completeSet(
                exerciseID: exerciseID,
                setID: setID,
                isCompleted: true,
                completedAt: completedAt,
                sensorSummary: nil
            )
        ))

        XCTAssertEqual(session.exercises[0].sets[0].actualReps, 999)
        XCTAssertEqual(session.exercises[0].sets[0].rpe, 8)
        XCTAssertTrue(session.exercises[0].sets[0].isCompleted)
        XCTAssertEqual(session.exercises[0].sets[0].completedAt, completedAt)
    }

    func testTempoGuideCountsBothPhasesAcrossRepetitions() throws {
        let target = try XCTUnwrap(WatchTempoTarget(
            concentricSeconds: 2,
            eccentricSeconds: 3,
            repetitions: 2
        ))
        var state = WatchTempoGuideState(target: target)
        let cues = (0..<10).compactMap { _ in state.advance() }

        XCTAssertEqual(cues.count, 10)
        XCTAssertEqual(cues.first?.displayText, "上げ 1/2・1/2回")
        XCTAssertEqual(cues.first?.hapticCue, .concentricStart)
        XCTAssertEqual(cues[1].hapticCue, .beat)
        XCTAssertEqual(cues[2].hapticCue, .eccentricStart)
        XCTAssertEqual(cues[4].displayText, "下げ 3/3・1/2回")
        XCTAssertEqual(cues.last?.displayText, "下げ 3/3・2/2回")
        XCTAssertTrue(state.isFinished)
        XCTAssertNil(state.advance())
    }

    func testTempoGuideCanSkipCurrentPhase() throws {
        let target = try XCTUnwrap(WatchTempoTarget(
            concentricSeconds: 3,
            eccentricSeconds: 2,
            repetitions: 1
        ))
        var state = WatchTempoGuideState(target: target)
        _ = state.advance()
        state.skipCurrentPhase()

        XCTAssertEqual(state.advance()?.displayText, "下げ 1/2・1/1回")
    }

    func testTempoGuidePauseResumeAndDisablePreservePosition() throws {
        let target = try XCTUnwrap(WatchTempoTarget(
            concentricSeconds: 3,
            eccentricSeconds: 2,
            repetitions: 1
        ))
        var state = WatchTempoGuideState(target: target)

        XCTAssertEqual(state.advance()?.second, 1)
        state.pause()
        XCTAssertTrue(state.isPaused)
        XCTAssertNil(state.advance())
        XCTAssertEqual(state.elapsedSeconds, 1)

        state.resume()
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.advance()?.second, 2)

        state.setEnabled(false)
        XCTAssertFalse(state.isEnabled)
        XCTAssertNil(state.advance())
        XCTAssertEqual(state.elapsedSeconds, 2)

        state.resume()
        XCTAssertNil(state.advance())
        state.setEnabled(true)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.advance()?.second, 3)
        XCTAssertEqual(state.advance()?.hapticCue, .eccentricStart)
    }

    func testTempoSpeedProducesOneToThreeHapticsPerSecond() throws {
        for speed in 1...3 {
            let target = try XCTUnwrap(WatchTempoTarget(
                concentricSeconds: 2,
                eccentricSeconds: 2,
                repetitions: 1,
                beatSpeed: speed
            ))
            var state = WatchTempoGuideState(target: target)
            let startCue = try XCTUnwrap(state.advance())
            let beatCue = try XCTUnwrap(state.advance())

            XCTAssertEqual(startCue.hapticCount, speed)
            XCTAssertEqual(beatCue.hapticCount, speed)
            XCTAssertTrue(beatCue.shouldEmitBeat)
            XCTAssertEqual(startCue.hapticPattern.first, .directionUp)
            XCTAssertEqual(startCue.hapticPattern.count, speed)
            XCTAssertEqual(beatCue.hapticPattern, Array(repeating: .click, count: speed))
            XCTAssertEqual(startCue.hapticIntervalNanoseconds, UInt64(1_000_000_000 / speed))
        }
    }

    func testTempoHapticPatternSignalsLiftAndLowerDirections() throws {
        let target = try XCTUnwrap(WatchTempoTarget(
            concentricSeconds: 1,
            eccentricSeconds: 1,
            repetitions: 1,
            beatSpeed: 3
        ))
        var state = WatchTempoGuideState(target: target)

        let liftCue = try XCTUnwrap(state.advance())
        let lowerCue = try XCTUnwrap(state.advance())

        XCTAssertEqual(liftCue.hapticPattern, [.directionUp, .click, .click])
        XCTAssertEqual(lowerCue.hapticPattern, [.directionDown, .click, .click])
    }

    func testPlannedTempoIsStoredPerSetAndRejectsOutOfRangeValues() {
        var session = makeSession()
        let exerciseID = session.exercises[0].id
        let firstSetID = session.exercises[0].sets[0].id

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updatePlannedTempo(
                exerciseID: exerciseID,
                setID: firstSetID,
                concentricSeconds: 2,
                eccentricSeconds: 4,
                beatSpeed: 3
            )
        ))
        XCTAssertEqual(session.exercises[0].sets[0].plannedConcentricSeconds, 2)
        XCTAssertEqual(session.exercises[0].sets[0].plannedEccentricSeconds, 4)
        XCTAssertEqual(session.exercises[0].sets[0].plannedTempoBeatSpeed, 3)
        XCTAssertNil(session.exercises[0].sets[1].plannedConcentricSeconds)

        XCTAssertFalse(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updatePlannedTempo(
                exerciseID: exerciseID,
                setID: firstSetID,
                concentricSeconds: 0,
                eccentricSeconds: 4,
                beatSpeed: 3
            )
        ))
        XCTAssertEqual(session.exercises[0].sets[0].plannedConcentricSeconds, 2)
    }

    func testTempoPerformancePersistsPlanDifferenceAndManualCorrection() throws {
        var session = makeSessionWithTempo()
        let exerciseID = session.exercises[0].id
        let setID = session.exercises[0].sets[0].id

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateObservedTempo(
                exerciseID: exerciseID,
                setID: setID,
                concentricSeconds: 1.4,
                eccentricSeconds: 3.8,
                wasManuallyCorrected: true
            )
        ))

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WatchWorkoutSessionSnapshot.self, from: data)
        let performance = try XCTUnwrap(decoded.exercises[0].sets[0].tempoPerformance)
        XCTAssertEqual(performance.achievement, .mixed)
        XCTAssertEqual(performance.concentricDifferenceSeconds, -0.6, accuracy: 0.0001)
        XCTAssertEqual(performance.eccentricDifferenceSeconds, 0.8, accuracy: 0.0001)
        XCTAssertTrue(performance.wasManuallyCorrected)
    }

    func testCompletingSetCapturesMeasuredTempoWithoutOverwritingManualCorrection() throws {
        var session = makeSessionWithTempo()
        let exerciseID = session.exercises[0].id
        let setID = session.exercises[0].sets[0].id
        let sensor = makeSensorSummary(concentric: 2.1, eccentric: 2.9)

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .completeSet(
                exerciseID: exerciseID,
                setID: setID,
                isCompleted: true,
                completedAt: Date(),
                sensorSummary: sensor
            )
        ))
        XCTAssertEqual(session.exercises[0].sets[0].tempoPerformance?.achievement, .onTarget)
        XCTAssertEqual(session.exercises[0].sets[0].tempoPerformance?.wasManuallyCorrected, false)

        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .updateObservedTempo(
                exerciseID: exerciseID,
                setID: setID,
                concentricSeconds: 1.2,
                eccentricSeconds: 4,
                wasManuallyCorrected: true
            )
        ))
        XCTAssertTrue(WatchWorkoutSessionReducer.reduce(
            session: &session,
            action: .completeSet(
                exerciseID: exerciseID,
                setID: setID,
                isCompleted: true,
                completedAt: Date(),
                sensorSummary: sensor
            )
        ))
        XCTAssertEqual(session.exercises[0].sets[0].tempoPerformance?.achievement, .mixed)
        XCTAssertEqual(session.exercises[0].sets[0].tempoPerformance?.wasManuallyCorrected, true)
    }

    func testLegacyWorkoutSetsDecodeWithoutTempoPerformance() throws {
        let watchSet = WatchWorkoutSetSnapshot(setOrder: 1, targetWeight: 50, targetReps: 10)
        var watchJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(watchSet)) as? [String: Any]
        )
        watchJSON.removeValue(forKey: "tempoPerformance")
        watchJSON.removeValue(forKey: "hasUserAdjustedWeight")
        let decodedWatchSet = try JSONDecoder().decode(
            WatchWorkoutSetSnapshot.self,
            from: JSONSerialization.data(withJSONObject: watchJSON)
        )
        XCTAssertNil(decodedWatchSet.tempoPerformance)
        XCTAssertNil(decodedWatchSet.hasUserAdjustedWeight)

        let workoutSet = WorkoutSet(setOrder: 1, targetWeight: 50, targetReps: 10)
        var workoutJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(workoutSet)) as? [String: Any]
        )
        workoutJSON.removeValue(forKey: "tempoPerformance")
        let decodedWorkoutSet = try JSONDecoder().decode(
            WorkoutSet.self,
            from: JSONSerialization.data(withJSONObject: workoutJSON)
        )
        XCTAssertNil(decodedWorkoutSet.tempoPerformance)
    }

    func testWorkoutSetRoundTripPreservesManualTempoCorrection() throws {
        let performance = try XCTUnwrap(TempoPerformance(
            plannedConcentricSeconds: 2,
            plannedEccentricSeconds: 3,
            observedConcentricSeconds: 1.5,
            observedEccentricSeconds: 3.7,
            wasManuallyCorrected: true
        ))
        let set = WorkoutSet(
            setOrder: 1,
            targetWeight: 50,
            targetReps: 10,
            plannedConcentricSeconds: 2,
            plannedEccentricSeconds: 3,
            tempoPerformance: performance
        )

        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(WorkoutSet.self, from: data)

        XCTAssertEqual(decoded.tempoPerformance, performance)
        XCTAssertTrue(decoded.tempoPerformance?.wasManuallyCorrected == true)
    }

    func testPlanTempoSpeedSurvivesWatchAndWorkoutRoundTrip() throws {
        let plan = TrainingPlan(
            name: "テンポ",
            exercises: [
                PlanExercise(
                    exercise: Exercise(
                        name: "ベンチプレス",
                        primaryMuscle: .chest,
                        equipment: .barbell,
                        instruction: ""
                    ),
                    sortOrder: 0,
                    sets: [
                        PlanSetTarget(
                            setOrder: 1,
                            targetWeight: 50,
                            targetReps: 8,
                            plannedConcentricSeconds: 2,
                            plannedEccentricSeconds: 4,
                            plannedTempoBeatSpeed: 3
                        )
                    ]
                )
            ]
        )

        let watchPlan = WatchWorkoutPlanSnapshot(plan: plan, weightUnit: .kg)
        XCTAssertEqual(watchPlan.exercises[0].sets[0].plannedTempoBeatSpeed, 3)

        var watchSession = WatchWorkoutSessionSnapshot(plan: watchPlan)
        watchSession.exercises[0].sets[0].isCompleted = true
        let workout = WorkoutSession(watchSession: watchSession)
        XCTAssertEqual(workout.exercises[0].sets[0].plannedTempoBeatSpeed, 3)

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: data)
        XCTAssertEqual(decoded.exercises[0].sets[0].plannedTempoBeatSpeed, 3)
    }

    private func makeSession() -> WatchWorkoutSessionSnapshot {
        WatchWorkoutSessionSnapshot(
            sourcePlanID: UUID(),
            title: "胸の日",
            weightUnit: .kg,
            exercises: [
                WatchWorkoutExerciseSnapshot(
                    planExerciseID: UUID(),
                    exerciseID: UUID(),
                    name: "ベンチプレス",
                    primaryMuscleName: "胸",
                    primaryMuscleRawValue: "chest",
                    equipmentRawValue: "barbell",
                    sortOrder: 0,
                    restSeconds: 60,
                    sets: (1...3).map {
                        WatchWorkoutSetSnapshot(
                            setOrder: $0,
                            targetWeight: 50,
                            targetReps: 10
                        )
                    }
                )
            ]
        )
    }

    private func makeSessionWithTempo() -> WatchWorkoutSessionSnapshot {
        var session = makeSession()
        session.exercises[0].sets[0].plannedConcentricSeconds = 2
        session.exercises[0].sets[0].plannedEccentricSeconds = 3
        return session
    }

    private func makeSensorSummary(
        concentric: Double,
        eccentric: Double
    ) -> WatchSetSensorSummary {
        WatchSetSensorSummary(
            heartRateAtStart: nil,
            heartRateAtEnd: nil,
            averageHeartRate: nil,
            maximumHeartRate: nil,
            heartRateRecovery: nil,
            estimatedReps: 10,
            averageRepDuration: concentric + eccentric,
            movementConsistency: nil,
            confidence: 0.9,
            averageConcentricDuration: concentric,
            averageEccentricDuration: eccentric,
            averagePauseDuration: nil,
            relativeRangeOfMotion: nil,
            rangeOfMotionConsistency: nil,
            velocityLossPercent: nil,
            exerciseCandidateName: nil,
            exerciseCandidateConfidence: nil
        )
    }
}
