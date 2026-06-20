import XCTest

final class GymTrainingAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan"
        ]
        app.launch()
    }

    func testAlphaWorkoutFlow() throws {
        verifySeededPlan()
        completeWorkoutFromPlan()
        verifyHistory()
    }

    private func verifySeededPlan() {
        app.tabBars.buttons["計画"].tap()

        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)
    }

    private func completeWorkoutFromPlan() {
        app.tabBars.buttons["記録"].tap()

        let planButton = app.descendants(matching: .any)["startWorkout-胸の日"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        XCTAssertTrue(app.navigationBars["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)

        for index in 1...3 {
            let toggle = app.switches["completeSetToggle-\(index)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if toggle.value as? String == "0" {
                toggle.tap()
            }
        }

        app.buttons["finishWorkoutButton"].tap()

        let saveHistoryButton = app.buttons["完了して履歴に保存"]
        XCTAssertTrue(saveHistoryButton.waitForExistence(timeout: 5))
        saveHistoryButton.tap()

        XCTAssertTrue(app.staticTexts["総ボリューム"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)

        app.buttons["閉じる"].tap()
    }

    private func verifyHistory() {
        app.tabBars.buttons["履歴"].tap()

        let historyRow = app.descendants(matching: .any)["historyRow-胸の日"]
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.tap()

        XCTAssertTrue(app.navigationBars["履歴詳細"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["総ボリューム"].exists)
        XCTAssertTrue(app.staticTexts["実績 20 kg × 10回"].exists)
    }
}
