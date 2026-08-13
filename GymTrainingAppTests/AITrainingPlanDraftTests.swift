import XCTest
@testable import GymTrainingApp

final class AITrainingPlanDraftTests: XCTestCase {
    func testParserAcceptsFencedJSONAndBuildsEditablePlan() throws {
        let reply = """
        ```json
        {
          "name":"胸と背中",
          "summary":"上半身をバランスよく行います。",
          "exercises":[
            {"exercise_name":"ベンチプレス","sets":3,"reps":8,"weight":60.25,"rest_seconds":92},
            {"exercise_name":"ラットプルダウン","sets":4,"reps":10,"weight":45,"rest_seconds":120}
          ]
        }
        ```
        """

        let proposal = try AITrainingPlanDraftParser().parse(
            reply: reply,
            availableExercises: PresetExerciseStore.exercises
        )

        XCTAssertEqual(proposal.plan.name, "胸と背中")
        XCTAssertEqual(proposal.plan.exercises.map(\.exercise.name), ["ベンチプレス", "ラットプルダウン"])
        XCTAssertEqual(proposal.plan.exercises[0].sets.count, 3)
        XCTAssertEqual(proposal.plan.exercises[0].sets[0].targetWeight, 60.3)
        XCTAssertEqual(proposal.plan.exercises[0].restSeconds, 90)
        XCTAssertEqual(proposal.summary, "上半身をバランスよく行います。")
    }

    func testParserRemovesUnknownExercisesAndClampsValues() throws {
        let reply = #"{"name":"安全確認","summary":"","exercises":[{"exercise_name":"存在しない種目","sets":3,"reps":10,"weight":20,"rest_seconds":90},{"exercise_name":"ベンチプレス","sets":99,"reps":0,"weight":2000,"rest_seconds":2}]}"#

        let proposal = try AITrainingPlanDraftParser().parse(
            reply: reply,
            availableExercises: PresetExerciseStore.exercises
        )

        XCTAssertEqual(proposal.ignoredExerciseNames, ["存在しない種目"])
        XCTAssertEqual(proposal.plan.exercises.count, 1)
        XCTAssertEqual(proposal.plan.exercises[0].sets.count, 10)
        XCTAssertEqual(proposal.plan.exercises[0].sets[0].targetReps, 1)
        XCTAssertEqual(proposal.plan.exercises[0].sets[0].targetWeight, 999)
        XCTAssertEqual(proposal.plan.exercises[0].restSeconds, 5)
    }

    func testRevisionPreservesPlanIdentityAndUsesExistingWeightWhenMissing() throws {
        let exercise = try XCTUnwrap(PresetExerciseStore.exercises.first { $0.name == "チェストプレス" })
        let existingPlan = TrainingPlan(
            name: "元の計画",
            exercises: [
                PlanExercise(
                    exercise: exercise,
                    sortOrder: 0,
                    sets: [PlanSetTarget(setOrder: 1, targetWeight: 37.5, targetReps: 10)]
                )
            ]
        )
        let reply = #"{"name":"修正版","summary":"疲労に配慮","exercises":[{"exercise_name":"チェストプレス","sets":2,"reps":12,"weight":null,"rest_seconds":100}]}"#

        let proposal = try AITrainingPlanDraftParser().parse(
            reply: reply,
            availableExercises: PresetExerciseStore.exercises,
            existingPlan: existingPlan
        )

        XCTAssertEqual(proposal.plan.id, existingPlan.id)
        XCTAssertEqual(proposal.plan.createdAt, existingPlan.createdAt)
        XCTAssertEqual(proposal.plan.exercises[0].sets[0].targetWeight, 37.5)
    }

    func testPromptIncludesGoalAndOnlySelectedEquipment() {
        var profile = UserProfile.default
        profile.goalType = .muscleGain
        profile.outcomeStyle = .vShape
        let prompt = AITrainingPlanPromptBuilder().makePrompt(
            profile: profile,
            exercises: PresetExerciseStore.exercises,
            selectedEquipment: [.machine],
            request: "肩を重点的に",
            currentPlan: nil
        )

        XCTAssertTrue(prompt.contains("目的: 筋肥大"))
        XCTAssertTrue(prompt.contains("目標像: Vシェイプ"))
        XCTAssertTrue(prompt.contains("チェストプレス[胸/マシン]"))
        XCTAssertFalse(prompt.contains("ベンチプレス[胸/バーベル]"))
        XCTAssertTrue(prompt.contains("肩を重点的に"))
        XCTAssertLessThanOrEqual(prompt.count, CoachChatRequest.maximumMessageCharacters)
    }

    func testParserRejectsResponseWithoutKnownExercises() {
        let reply = #"{"name":"不明","summary":"","exercises":[{"exercise_name":"架空種目","sets":3,"reps":10,"weight":20,"rest_seconds":90}]}"#

        XCTAssertThrowsError(
            try AITrainingPlanDraftParser().parse(
                reply: reply,
                availableExercises: PresetExerciseStore.exercises
            )
        ) { error in
            XCTAssertEqual(error as? AITrainingPlanDraftError, .noUsableExercises)
        }
    }
}
