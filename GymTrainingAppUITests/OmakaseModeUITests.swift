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
        XCTAssertTrue(app.descendants(matching: .any)["omakaseAICoachCard"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["omakasePrimaryActionButton"].exists)
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
}
