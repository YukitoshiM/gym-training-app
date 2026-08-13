import XCTest
@testable import GymTrainingApp

@MainActor
final class BeginnerProgramTests: XCTestCase {
    func testRecommendationsStayLockedUntilThreeWorkoutsAreCompleted() {
        let store = makeStore()
        store.plans = [TrainingPlan(name: "Starter")]
        store.workoutHistory = completedSessions(count: 2)

        XCTAssertTrue(store.makeBeginnerProgramRecommendations().isEmpty)

        store.workoutHistory = completedSessions(count: 3)
        XCTAssertFalse(store.makeBeginnerProgramRecommendations().isEmpty)
    }

    func testRecommendationsUseOnlyEquipmentSavedInProfile() {
        let store = makeStore()
        store.plans = [TrainingPlan(name: "Starter")]
        store.workoutHistory = completedSessions(count: 3)
        store.userProfile = profile(
            goal: .muscleGain,
            equipment: [.dumbbell, .bodyweight]
        )

        let recommendations = store.makeBeginnerProgramRecommendations()
        let generatedEquipment = recommendations.flatMap(\.plan.exercises).map(\.exercise.equipment)

        XCTAssertEqual(recommendations.count, 3)
        XCTAssertFalse(generatedEquipment.isEmpty)
        XCTAssertTrue(generatedEquipment.allSatisfy { [.dumbbell, .bodyweight].contains($0) })
    }

    func testPrescriptionChangesWithGoal() {
        let store = makeStore()
        store.plans = [TrainingPlan(name: "Starter")]
        store.workoutHistory = completedSessions(count: 3)

        store.userProfile = profile(goal: .muscleGain, equipment: [.dumbbell])
        let muscleGainSet = try! XCTUnwrap(
            store.makeBeginnerProgramRecommendations().first?.plan.exercises.first?.sets.first
        )
        let muscleGainSetCount = store.makeBeginnerProgramRecommendations()
            .first?.plan.exercises.first?.sets.count

        store.userProfile = profile(goal: .diet, equipment: [.dumbbell])
        let dietSet = try! XCTUnwrap(
            store.makeBeginnerProgramRecommendations().first?.plan.exercises.first?.sets.first
        )
        let dietSetCount = store.makeBeginnerProgramRecommendations()
            .first?.plan.exercises.first?.sets.count

        XCTAssertEqual(muscleGainSet.targetReps, 10)
        XCTAssertEqual(muscleGainSetCount, 3)
        XCTAssertEqual(dietSet.targetReps, 12)
        XCTAssertEqual(dietSetCount, 2)
    }

    func testAchievedDumbbellSetsIncreaseNextRecommendationByOneKilogram() throws {
        let store = makeStore()
        store.plans = [TrainingPlan(name: "Starter")]
        store.userProfile = profile(goal: .muscleGain, equipment: [.dumbbell])
        store.workoutHistory = completedSessions(count: 3)

        let initialExercise = try XCTUnwrap(
            store.makeBeginnerProgramRecommendations().first?.plan.exercises.first
        )
        let initialWeight = try XCTUnwrap(initialExercise.sets.first?.targetWeight)
        let achievedExercise = WorkoutExercise(
            exercise: initialExercise.exercise,
            sortOrder: 0,
            restSeconds: initialExercise.restSeconds,
            sets: initialExercise.sets.map {
                WorkoutSet(
                    setOrder: $0.setOrder,
                    targetWeight: $0.targetWeight,
                    targetReps: $0.targetReps,
                    actualWeight: $0.targetWeight,
                    actualReps: $0.targetReps,
                    isCompleted: true
                )
            }
        )
        store.workoutHistory = [
            WorkoutSession(
                title: "Achieved",
                sourcePlanID: nil,
                startedAt: Date(),
                endedAt: Date(),
                exercises: [achievedExercise]
            )
        ] + completedSessions(count: 2)

        let progressedExercise = try XCTUnwrap(
            store.makeBeginnerProgramRecommendations()
                .flatMap(\.plan.exercises)
                .first { $0.exercise.id == initialExercise.exercise.id }
        )

        XCTAssertEqual(progressedExercise.sets.first?.targetWeight, initialWeight + 1)
    }

    private func makeStore() -> AppStore {
        let store = AppStore(storage: LocalJSONStorage())
        store.plans = []
        store.workoutHistory = []
        store.customExercises = []
        store.userProfile = .default
        return store
    }

    private func completedSessions(count: Int) -> [WorkoutSession] {
        (0..<count).map { index in
            let date = Date().addingTimeInterval(TimeInterval(-index * 86_400))
            return WorkoutSession(
                title: "Completed \(index)",
                sourcePlanID: nil,
                startedAt: date,
                endedAt: date.addingTimeInterval(1_800),
                exercises: []
            )
        }
    }

    private func profile(goal: GoalType, equipment: [Equipment]) -> UserProfile {
        UserProfile(
            goalType: goal,
            focusMuscles: goal.supportsFocusMuscles ? [.chest, .back] : [],
            weeklyTrainingDays: 3,
            preferredSessionMinutes: 45,
            availableEquipment: equipment,
            heightCm: nil,
            birthYear: nil,
            sex: .unspecified,
            experienceLevel: .beginner,
            weightUnit: .kg
        )
    }
}
