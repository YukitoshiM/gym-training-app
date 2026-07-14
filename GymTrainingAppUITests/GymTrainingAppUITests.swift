import XCTest

@MainActor
final class GymTrainingAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private static let calendarDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

    func testPreviousPerformanceCopy() throws {
        completeWorkoutFromPlan()
        startWorkoutFromPlan()

        XCTAssertTrue(app.staticTexts["前回 20 kg × 10回"].waitForExistence(timeout: 5))

        let copyButton = app.buttons["copyPreviousSet-1"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
    }

    func testPlanQuickTemplateAndBulkSetPreset() throws {
        createPlanFromQuickTemplate()
    }

    func testGoalModeSelection() throws {
        app.tabBars.buttons["ホーム"].tap()

        let goalCard = app.buttons["goalActionCard"]
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["体型改善"].exists)

        goalCard.tap()

        let dietOption = app.buttons["goalOption-diet"]
        XCTAssertTrue(dietOption.waitForExistence(timeout: 5))
        dietOption.tap()

        XCTAssertTrue(app.staticTexts["ダイエット"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["体重・腹囲・食事を記録する"].exists)
    }

    func testManualMealAndBodyPhotoLogFlow() throws {
        addManualMealEntry()
        addBodyPhotoMemoEntry()
        verifyDailyJournalForManualLogs()
    }

    func testAIFreeMVPSurfaces() throws {
        verifyFreeWorkoutEntryPoint()
        addCustomExercise()
        verifySettingsSurface()
        completeWorkoutFromPlan()
        verifyHistoryAnalyticsLinks()
    }

    func testAIConnectionFailureUX() throws {
        relaunchWithUnreachableAI()
        verifyAISettingsFailureMessage()
        verifyAIReportFailureMessage()
    }

    private func verifySeededPlan() {
        app.tabBars.buttons["計画"].tap()

        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)
    }

    private func createPlanFromQuickTemplate() {
        app.tabBars.buttons["計画"].tap()

        let createButton = app.buttons["createPlanToolbarButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let backTemplate = app.buttons["planTemplate-back"]
        XCTAssertTrue(backTemplate.waitForExistence(timeout: 5))
        backTemplate.tap()

        XCTAssertTrue(app.navigationBars["背中の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ラットプルダウン"].exists)

        let strengthPreset = app.buttons["planSetPreset-strength"]
        XCTAssertTrue(strengthPreset.waitForExistence(timeout: 5))
        strengthPreset.tap()

        XCTAssertTrue(app.staticTexts["5回"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["savePlanPinnedButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["背中の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["20セット"].waitForExistence(timeout: 5))
    }

    private func completeWorkoutFromPlan() {
        startWorkoutFromPlan()

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
        XCTAssertTrue(app.staticTexts["計画セット"].exists)
        XCTAssertTrue(app.staticTexts["3/3"].exists)
        XCTAssertTrue(app.staticTexts["目標差"].exists)
        XCTAssertTrue(app.staticTexts["0 kg"].exists)

        app.buttons["閉じる"].tap()
    }

    private func startWorkoutFromPlan() {
        app.tabBars.buttons["記録"].tap()

        let planButton = app.descendants(matching: .any)["startWorkout-胸の日"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        XCTAssertTrue(app.navigationBars["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)
        XCTAssertTrue(app.staticTexts["計画セット"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/3"].exists)
        XCTAssertTrue(app.staticTexts["-600 kg"].exists)
    }

    private func verifyHistory() {
        app.tabBars.buttons["履歴"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))

        let todayID = Self.calendarDayFormatter.string(from: Date())
        let todayCalendarButton = app.buttons["historyCalendarDay-\(todayID)"]
        XCTAssertTrue(todayCalendarButton.waitForExistence(timeout: 5))
        todayCalendarButton.tap()

        let historyRow = app.descendants(matching: .any)["historyRow-胸の日"]
        for _ in 0..<3 where !historyRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.tap()

        XCTAssertTrue(app.navigationBars["履歴詳細"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["総ボリューム"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["historyPlanDeltaSummary"].exists)
        XCTAssertTrue(app.staticTexts["実績 20 kg × 10回"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["historySetDelta-1"].exists)
        XCTAssertTrue(app.staticTexts["重量差 0 kg / 回数差 0回"].exists)
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

    private func verifyFreeWorkoutEntryPoint() {
        app.tabBars.buttons["記録"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["dailyRecordChecklistCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recordHubBodyWeightLink"].exists)
        XCTAssertTrue(app.buttons["recordHubMealLink"].exists)

        let freeWorkoutButton = app.descendants(matching: .any)["startFreeWorkoutButton"]
        XCTAssertTrue(freeWorkoutButton.waitForExistence(timeout: 5))
    }

    private func addCustomExercise() {
        app.tabBars.buttons["種目"].tap()

        let addButton = app.buttons["addCustomExerciseButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.textFields["customExerciseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        let customExerciseName = "AAAテストローププレス"
        nameField.typeText(customExerciseName)

        let saveButton = app.buttons["saveCustomExerciseButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts[customExerciseName].waitForExistence(timeout: 5))
    }

    private func verifySettingsSurface() {
        app.tabBars.buttons["ホーム"].tap()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["saveProfileSettingsButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.textFields["aiBaseURLField"].waitForExistence(timeout: 5))
        saveButton.tap()
    }

    private func verifyAISettingsFailureMessage() {
        app.tabBars.buttons["ホーム"].tap()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.textFields["aiBaseURLField"].waitForExistence(timeout: 5))

        let checkButton = app.buttons["checkAIHealthButton"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["aiConnectionResultCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["ローカルLLMサーバーに接続できません。"].waitForExistence(timeout: 5))

        app.buttons["saveProfileSettingsButton"].tap()
    }

    private func verifyAIReportFailureMessage() {
        app.tabBars.buttons["ホーム"].tap()

        let aiReportLink = app.descendants(matching: .any)["aiReportLink"]
        XCTAssertTrue(aiReportLink.waitForExistence(timeout: 5))
        aiReportLink.tap()

        let generateButton = app.buttons["generateWeeklyAIReportButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["aiErrorRecoveryCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["記録は保存されたままです。あとで接続できる状態になってから、もう一度生成できます。"].exists)
    }

    private func verifyHistoryAnalyticsLinks() {
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["aiReportLink"].waitForExistence(timeout: 5))

        app.tabBars.buttons["履歴"].tap()

        let weeklyVolumeLink = app.descendants(matching: .any)["weeklyVolumeLink"]
        XCTAssertTrue(weeklyVolumeLink.waitForExistence(timeout: 5))

        let exerciseHistoryLink = app.descendants(matching: .any)["exerciseHistoryLink"]
        XCTAssertTrue(exerciseHistoryLink.waitForExistence(timeout: 5))
    }

    private func verifyDailyJournalForManualLogs() {
        app.tabBars.buttons["履歴"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dailyJournalSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["512 kcal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["トレーニングは未記録"].exists)

        let mealName = app.staticTexts["昼食 鶏むね肉定食"]
        for _ in 0..<3 where !mealName.exists {
            app.swipeUp()
        }
        XCTAssertTrue(mealName.exists)

        let bodyPhotoMemo = app.staticTexts["正面メモ"]
        for _ in 0..<3 where !bodyPhotoMemo.exists {
            app.swipeUp()
        }
        XCTAssertTrue(bodyPhotoMemo.exists)
    }

    private func addManualMealEntry() {
        app.tabBars.buttons["ホーム"].tap()

        let mealListLink = app.buttons["mealListLink"]
        XCTAssertTrue(mealListLink.waitForExistence(timeout: 5))
        mealListLink.tap()

        let addMealButton = app.buttons["addMealButton"]
        XCTAssertTrue(addMealButton.waitForExistence(timeout: 5))
        addMealButton.tap()

        let nameField = app.textFields["mealNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("鶏むね肉定食")

        let caloriesField = app.textFields["mealCaloriesField"]
        XCTAssertTrue(caloriesField.waitForExistence(timeout: 5))
        caloriesField.tap()
        caloriesField.typeText("512")

        let proteinField = app.textFields["mealProteinField"]
        XCTAssertTrue(proteinField.waitForExistence(timeout: 5))
        proteinField.tap()
        proteinField.typeText("31")

        let saveButton = app.buttons["saveMealButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mealRow-鶏むね肉定食"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["512 kcal"].exists)
    }

    private func addBodyPhotoMemoEntry() {
        app.tabBars.buttons["ホーム"].tap()

        let bodyPhotoListLink = app.buttons["bodyPhotoListLink"]
        XCTAssertTrue(bodyPhotoListLink.waitForExistence(timeout: 5))
        bodyPhotoListLink.tap()

        let addBodyPhotoButton = app.buttons["addBodyPhotoButton"]
        XCTAssertTrue(addBodyPhotoButton.waitForExistence(timeout: 5))
        addBodyPhotoButton.tap()

        let memoField = app.textFields["bodyPhotoMemoField"]
        XCTAssertTrue(memoField.waitForExistence(timeout: 5))
        memoField.tap()
        memoField.typeText("正面メモ")

        let saveButton = app.buttons["saveBodyPhotoButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["bodyPhotoRow-front"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正面メモ"].exists)
    }

    private func relaunchWithUnreachableAI() {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-ai-unreachable-settings"
        ]
        app.launch()
    }
}
