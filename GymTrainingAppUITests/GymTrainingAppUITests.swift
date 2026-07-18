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

        let copyButton = app.buttons["copyPreviousSet-0-1"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
    }

    func testWorkoutWeightSupportsManualDecimalEntry() throws {
        startWorkoutFromPlan()

        let weightField = app.textFields["workoutWeightField-0-1"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        weightField.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        weightField.typeText("20.1")

        let dismissButton = app.buttons["dismiss-workoutWeightField-0-1"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
        dismissButton.tap()

        XCTAssertEqual(weightField.value as? String, "20.1")

        let wheelButton = app.buttons["wheel-workoutWeightField-0-1"]
        XCTAssertTrue(wheelButton.waitForExistence(timeout: 5))
        wheelButton.tap()

        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 2)
        let tenthsPicker = app.pickerWheels.element(boundBy: 1)
        tenthsPicker.adjust(toPickerWheelValue: "2")

        let saveButton = app.buttons["saveWeightWheelButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertEqual(weightField.value as? String, "20.2")

        let repsField = app.textFields["workoutRepsField-0-1"]
        let repsWheelButton = app.buttons["wheel-workoutRepsField-0-1"]
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        XCTAssertTrue(repsWheelButton.waitForExistence(timeout: 5))
        repsWheelButton.tap()

        let repsPicker = app.pickerWheels.firstMatch
        XCTAssertTrue(repsPicker.waitForExistence(timeout: 5))
        repsPicker.adjust(toPickerWheelValue: "11")

        let saveRepsButton = app.buttons["saveRepsWheelButton"]
        XCTAssertTrue(saveRepsButton.waitForExistence(timeout: 5))
        saveRepsButton.tap()

        XCTAssertEqual(repsField.value as? String, "11")
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

    func testWatchPlanTransfer() throws {
        app.tabBars.buttons["記録"].tap()

        let sendButton = app.buttons["sendPlanToWatchButton"]
        for _ in 0..<3 where !sendButton.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))

        guard app.staticTexts["Apple Watchへメニューを同期できます"].waitForExistence(timeout: 8) else {
            throw XCTSkip("ペアリング済みでWatchアプリが入った環境でのみ実行します")
        }

        XCTAssertTrue(sendButton.isHittable)
        sendButton.tap()

        let immediateResult = app.staticTexts["1件のメニューをApple Watchへ同期しました"]
        let queuedResult = app.staticTexts["Apple Watchが近くにないため、次回起動時に届くよう予約しました"]
        let deadline = Date().addingTimeInterval(20)

        while Date() < deadline && !immediateResult.exists && !queuedResult.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTAssertTrue(immediateResult.exists || queuedResult.exists)
    }

    func testConditionDashboardWithSeededSensorData() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-sensor-ui-test-data"
        ]
        app.launch()

        let conditionCard = app.buttons["conditionSummaryCard"]
        XCTAssertTrue(conditionCard.waitForExistence(timeout: 5))
        conditionCard.tap()

        XCTAssertTrue(app.navigationBars["コンディション"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["readinessCard"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["activityProgressCard"].exists)
        XCTAssertTrue(app.staticTexts["7,842"].exists)

        let sleepValue = app.staticTexts["7.4 時間"]
        for _ in 0..<3 where !sleepValue.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sleepValue.waitForExistence(timeout: 3))
    }

    func testExtendedSensorDashboardAndAnalysisSurfaces() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-sensor-ui-test-data"
        ]
        app.launch()

        let conditionCard = app.buttons["conditionSummaryCard"]
        XCTAssertTrue(conditionCard.waitForExistence(timeout: 5))
        conditionCard.tap()

        let analysisLink = app.descendants(matching: .any)["sensorTrainingAnalysisLink"]
        XCTAssertTrue(analysisLink.waitForExistence(timeout: 5))
        analysisLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["setQualityBreakdownCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["conditionComparisonCard"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["plateauEvidenceCard"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        let sleepCard = app.descendants(matching: .any)["sleepDetailsCard"]
        for _ in 0..<4 where !sleepCard.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sleepCard.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["品質 86"].exists)

        let routeCard = app.descendants(matching: .any)["outdoorRunningRouteCard"]
        for _ in 0..<8 where !routeCard.exists {
            app.swipeUp()
        }
        XCTAssertTrue(routeCard.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["5.1 km"].exists)
    }

    func testAIDataSharingCanBeSelectedByCategory() throws {
        app.tabBars.buttons["ホーム"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))

        let disclosure = app.buttons["AIへ送るデータ"]
        for _ in 0..<5 where !disclosure.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        disclosure.tap()

        XCTAssertTrue(app.switches["身体KPI"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["睡眠・回復"].exists)
        let workoutSensors = app.switches["心拍・モーション"]
        for _ in 0..<4 where !workoutSensors.exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.switches["ジム訪問"].exists)
        XCTAssertTrue(workoutSensors.waitForExistence(timeout: 3))
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

        let restButton = app.buttons["planRestSeconds-0"]
        XCTAssertTrue(restButton.waitForExistence(timeout: 5))
        restButton.tap()

        let restPicker = app.pickerWheels.firstMatch
        XCTAssertTrue(restPicker.waitForExistence(timeout: 5))
        restPicker.adjust(toPickerWheelValue: "1:35")

        let saveRestButton = app.buttons["saveRestSecondsButton"]
        XCTAssertTrue(saveRestButton.waitForExistence(timeout: 5))
        saveRestButton.tap()

        let strengthPreset = app.buttons["planSetPreset-strength"]
        XCTAssertTrue(strengthPreset.waitForExistence(timeout: 5))
        strengthPreset.tap()

        let repsField = app.textFields["planRepsField-0-1"]
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        XCTAssertEqual(repsField.value as? String, "5")
        let restField = app.textFields["planRestSeconds-0-field"]
        XCTAssertTrue(restField.exists)
        XCTAssertEqual(restField.value as? String, "95")

        let saveButton = app.buttons["savePlanPinnedButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["背中の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["20セット"].waitForExistence(timeout: 5))
    }

    private func completeWorkoutFromPlan() {
        startWorkoutFromPlan()

        for index in 1...3 {
            let toggle = app.switches["completeSetToggle-0-\(index)"]
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
        XCTAssertTrue(app.staticTexts["3セット・30回"].exists)
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
