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

    func testBodyMetricFlow() throws {
        openBodyMetricDetail()
        setBodyMetricGoal()
        addBodyMetricEntry()
        verifyBodyMetricSummary()
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

    private func openBodyMetricDetail() {
        app.tabBars.buttons["ホーム"].tap()

        let bodyMetricListLink = app.buttons["bodyMetricListLink"]
        XCTAssertTrue(bodyMetricListLink.waitForExistence(timeout: 5))
        bodyMetricListLink.tap()

        let bodyWeightRow = app.descendants(matching: .any)["bodyMetricRow-bodyWeight"]
        XCTAssertTrue(bodyWeightRow.waitForExistence(timeout: 5))
        bodyWeightRow.tap()

        XCTAssertTrue(app.navigationBars["体重"].waitForExistence(timeout: 5))
    }

    private func setBodyMetricGoal() {
        app.buttons["目標設定"].tap()

        let goalField = app.textFields["bodyMetricGoalField"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 5))
        goalField.tap()
        goalField.typeText("70")

        let keyboardDoneButton = app.buttons["入力完了"]
        if keyboardDoneButton.waitForExistence(timeout: 2) {
            keyboardDoneButton.tap()
        }

        let saveButton = app.buttons["saveBodyMetricGoalButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }

    private func addBodyMetricEntry() {
        let addButton = app.buttons["addBodyMetricEntryButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let valueField = app.textFields["bodyMetricValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        valueField.tap()
        valueField.typeText("72")

        let keyboardDoneButton = app.buttons["入力完了"]
        if keyboardDoneButton.waitForExistence(timeout: 2) {
            keyboardDoneButton.tap()
        }

        let saveButton = app.buttons["saveBodyMetricEntryButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }

    private func verifyBodyMetricSummary() {
        XCTAssertTrue(app.staticTexts["72 kg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["目標"].exists)
        XCTAssertTrue(app.staticTexts["目標差"].exists)
        XCTAssertTrue(app.staticTexts["達成率"].exists)

        let chart = app.descendants(matching: .any)["bodyMetricChart-bodyWeight"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
    }
}
