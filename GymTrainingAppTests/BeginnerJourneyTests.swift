import XCTest
@testable import GymTrainingApp

final class BeginnerJourneyTests: XCTestCase {
    func testJourneyStartsWithPlanCreation() {
        let progress = BeginnerJourneyProgress(
            hasPlan: false,
            completedWorkoutCount: 0
        )

        XCTAssertEqual(progress.level, 1)
        XCTAssertEqual(progress.completedMilestoneCount, 0)
        XCTAssertEqual(progress.progressValue, 0)
        XCTAssertEqual(progress.nextAction, .createPlan)
        XCTAssertFalse(progress.isFoundationComplete)
    }

    func testFirstWorkoutUnlocksLevelTwo() {
        let progress = BeginnerJourneyProgress(
            hasPlan: true,
            completedWorkoutCount: 1
        )

        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.completedMilestoneCount, 2)
        XCTAssertEqual(progress.progressValue, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(progress.nextAction, .startWorkout)
    }

    func testThreeWorkoutsUnlockPurposeBasedPlans() {
        let progress = BeginnerJourneyProgress(
            hasPlan: true,
            completedWorkoutCount: 3
        )

        XCTAssertEqual(progress.level, 3)
        XCTAssertEqual(progress.completedMilestoneCount, 3)
        XCTAssertEqual(progress.progressValue, 1)
        XCTAssertEqual(progress.nextAction, .explorePlans)
        XCTAssertTrue(progress.isFoundationComplete)
    }
}
