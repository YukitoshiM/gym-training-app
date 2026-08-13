import XCTest

@MainActor
final class BeginnerOnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-beginner-onboarding",
            "--expand-home-details"
        ]
        app.launch()
    }

    func testHomePlanCallToActionOpensGuidedBeginnerPlan() throws {
        let createButton = app.buttons["createPlanFromHomeButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        XCTAssertTrue(app.navigationBars["初心者 全身スタート"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["beginnerStarterGuide"].exists)
        XCTAssertTrue(app.staticTexts["レッグプレス"].exists)
        XCTAssertTrue(app.staticTexts["チェストプレス"].exists)
        let latPulldown = app.staticTexts["ラットプルダウン"]
        for _ in 0..<3 where !latPulldown.exists {
            app.swipeUp()
        }
        XCTAssertTrue(latPulldown.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["planTemplate-back"].exists)
    }

    func testLevelThreeOpensEquipmentBasedProgressionPlan() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-beginner-level-three",
            "--expand-home-details"
        ]
        app.launch()

        let nextStageCard = app.buttons["beginnerNextStageCard"]
        XCTAssertTrue(nextStageCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["beginnerJourneyCard"].exists)
        nextStageCard.tap()

        XCTAssertTrue(app.navigationBars["計画"].waitForExistence(timeout: 5))
        let recommendation = app.buttons["beginnerRecommendation-level-3-0-上半身"]
        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ダンベル")).firstMatch.exists
        )
        recommendation.tap()

        XCTAssertTrue(app.navigationBars["LEVEL 3 上半身"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["beginnerProgressionGuide"].exists)
    }
}
