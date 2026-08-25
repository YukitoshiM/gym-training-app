import XCTest

final class OmakaseModeUITests: XCTestCase {
    @MainActor
    func testHomeShowsImmediateRecommendationAndKeepsDetailsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--stub-ai-trainer",
            "--expand-home-details",
            "--disable-app-tour",
            "--force-dark-appearance",
            "-bodymode.omakase.notificationsEnabled",
            "YES"
        ]
        app.launch()

        let dashboard = app.descendants(matching: .any)["omakaseDashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseReadiness"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseRecommendationStatus"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseAICoachCard"].exists)
        let primaryAction = app.descendants(matching: .any)["omakasePrimaryActionButton"]
        XCTAssertTrue(primaryAction.exists)
        XCTAssertTrue(primaryAction.isHittable, "The primary action should be usable without scrolling")
        XCTAssertTrue(app.descendants(matching: .any)["omakaseReason-workout"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseQuickRecord-食事"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseQuickRecord-体重"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakaseQuickRecord-写真"].exists)

        let details = app.buttons["omakaseDetailsButton"]
        XCTAssertTrue(details.waitForExistence(timeout: 2))
        XCTAssertEqual(details.value as? String, "展開中")
        let condition = app.descendants(matching: .any)["conditionSummaryCard"]
        for _ in 0..<5 where !condition.exists {
            app.swipeUp()
        }
        XCTAssertTrue(condition.waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testDailyActionReasonCanOpenOptionalScientificEvidence() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--stub-ai-trainer",
            "--disable-app-tour",
            "--force-dark-appearance",
            "-bodymode.omakase.automaticAICreditUse",
            "YES"
        ]
        app.launch()

        let reasonButton = app.descendants(matching: .any)["omakaseReason-workout"]
        XCTAssertTrue(reasonButton.waitForExistence(timeout: 5), app.debugDescription)

        let reviewedStatus = NSPredicate(format: "label CONTAINS %@", "確認済み")
        expectation(
            for: reviewedStatus,
            evaluatedWith: app.descendants(matching: .any)["omakaseRecommendationStatus"]
        )
        waitForExpectations(timeout: 10)

        let evidenceLink = app.descendants(matching: .any)["dailyActionEvidenceLink"]
        reasonButton.tap()
        XCTAssertTrue(evidenceLink.waitForExistence(timeout: 3), app.debugDescription)
        evidenceLink.tap()

        XCTAssertTrue(app.navigationBars["提案の根拠"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Resistance training prescription review"].exists)
    }
}

private extension XCUIElement {
    @MainActor
    func tapIfExists() {
        if exists { tap() }
    }
}
