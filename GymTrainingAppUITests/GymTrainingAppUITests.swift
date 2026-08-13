import XCTest

@MainActor
class GymTrainingAppUITestCase: XCTestCase {
    var app: XCUIApplication!
    static let calendarDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--expand-home-details"
        ]
        app.launch()
    }

    func verifySeededPlan() {
        tapTab("計画")

        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)
    }

    func openSettings() {
        tapTab("ホーム")
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
    }

    func createPlanFromQuickTemplate() {
        tapTab("計画")

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

    func tapTab(_ title: String) {
        let stableTabButton = app.buttons["rootTab-\(title)"]
        if stableTabButton.waitForExistence(timeout: 1) {
            stableTabButton.tap()
            return
        }

        let systemTabButton = app.tabBars.buttons[title]
        XCTAssertTrue(systemTabButton.waitForExistence(timeout: 5))
        systemTabButton.tap()
    }

    func completeWorkoutFromPlan() {
        startWorkoutFromPlan()
        completeCurrentWorkout()
    }

    func completeCurrentWorkout() {
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

        app.buttons["閉じる"].tap()
    }

    func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        field.typeText(text)
    }

    func replaceNumericText(in field: XCUIElement, with text: String) {
        let identifier = field.identifier
        replaceText(in: field, with: text)

        let dismissButton = app.buttons["dismiss-\(identifier)"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
        dismissButton.tap()
    }

    func startWorkoutFromPlan() {
        tapTab("記録")

        let planButton = app.descendants(matching: .any)["startWorkout-胸の日"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        XCTAssertTrue(app.navigationBars["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス"].exists)
        XCTAssertTrue(app.staticTexts["計画セット"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/3"].exists)
        XCTAssertTrue(app.staticTexts["-600 kg"].exists)
    }

    func verifyHistory() {
        tapTab("履歴")

        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))

        let todayID = Self.calendarDayFormatter.string(from: Date())
        let todayCalendarButton = app.buttons["historyCalendarDay-\(todayID)"]
        XCTAssertTrue(todayCalendarButton.waitForExistence(timeout: 5))
        XCTAssertTrue(todayCalendarButton.label.contains("筋トレ1件"))
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

    func openBodyMetricDetail() {
        tapTab("ホーム")

        let bodyMetricListLink = app.buttons["bodyMetricListLink"]
        XCTAssertTrue(bodyMetricListLink.waitForExistence(timeout: 5))
        bodyMetricListLink.tap()

        let bodyWeightRow = app.descendants(matching: .any)["bodyMetricRow-bodyWeight"]
        XCTAssertTrue(bodyWeightRow.waitForExistence(timeout: 5))
        bodyWeightRow.tap()

        XCTAssertTrue(app.navigationBars["体重"].waitForExistence(timeout: 5))
    }

    func setBodyMetricGoal() {
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

    func addBodyMetricEntry() {
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

    func verifyBodyMetricSummary() {
        XCTAssertTrue(app.staticTexts["72 kg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["目標"].exists)
        XCTAssertTrue(app.staticTexts["目標差"].exists)
        XCTAssertTrue(app.staticTexts["達成率"].exists)

        let chart = app.descendants(matching: .any)["bodyMetricChart-bodyWeight"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))

        let chartMode = app.segmentedControls["bodyMetricChartModePicker"]
        XCTAssertTrue(chartMode.waitForExistence(timeout: 5))
        chartMode.buttons["週平均"].tap()
        XCTAssertTrue(chart.exists)
    }

    func verifyPreviousBodyMetricPrefillsNextEntry() {
        app.buttons["addBodyMetricEntryButton"].tap()

        let valueField = app.textFields["bodyMetricValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        XCTAssertEqual(valueField.value as? String, "72")

        app.buttons["wheel-bodyMetricValueField"].tap()
        let picker = app.pickerWheels.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "72.0")

        app.navigationBars["値"].buttons["キャンセル"].tap()
        app.navigationBars["体重を記録"].buttons["キャンセル"].tap()
    }

    func verifyFreeWorkoutEntryPoint() {
        tapTab("記録")

        XCTAssertTrue(app.descendants(matching: .any)["dailyRecordChecklistCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recordHubBodyWeightLink"].exists)
        XCTAssertTrue(app.buttons["recordHubMealLink"].exists)

        let freeWorkoutButton = app.descendants(matching: .any)["startFreeWorkoutButton"]
        XCTAssertTrue(freeWorkoutButton.waitForExistence(timeout: 5))
    }

    func addCustomExercise() {
        tapTab("計画")

        let libraryLink = app.buttons["exerciseLibraryLink"]
        XCTAssertTrue(libraryLink.waitForExistence(timeout: 5))
        libraryLink.tap()
        XCTAssertTrue(app.navigationBars["種目"].waitForExistence(timeout: 5))

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

    func verifySettingsSurface() {
        tapTab("ホーム")

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["saveProfileSettingsButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        let aiBaseURLField = scrollToHittable(app.textFields["aiBaseURLField"])
        XCTAssertTrue(aiBaseURLField.isHittable)
        saveButton.tap()
    }

    func verifyAISettingsFailureMessage() {
        tapTab("ホーム")

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        let aiBaseURLField = scrollToHittable(app.textFields["aiBaseURLField"])
        XCTAssertTrue(aiBaseURLField.isHittable)

        let checkButton = scrollToHittable(app.buttons["checkAIHealthButton"])
        XCTAssertTrue(checkButton.isHittable)
        checkButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["aiConnectionResultCard"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["AIサーバーに接続できません。時間をおいて再試行してください。"].waitForExistence(timeout: 5))

        app.buttons["saveProfileSettingsButton"].tap()
    }

    func verifyAIReportFailureMessage() {
        tapTab("ホーム")

        let aiReportLink = scrollToHittable(app.descendants(matching: .any)["aiReportLink"])
        XCTAssertTrue(aiReportLink.isHittable)
        aiReportLink.tap()

        let generateButton = app.buttons["generateWeeklyAIReportButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        let recoveryCard = app.descendants(matching: .any)["aiErrorRecoveryCard"]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !recoveryCard.exists {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertTrue(recoveryCard.exists)
        XCTAssertTrue(app.staticTexts["記録は保存されたままです。あとで接続できる状態になってから、もう一度生成できます。"].exists)
    }

    func verifyHistoryAnalyticsLinks() {
        tapTab("ホーム")
        XCTAssertTrue(app.descendants(matching: .any)["aiReportLink"].waitForExistence(timeout: 5))

        tapTab("履歴")

        let weeklyVolumeLink = app.descendants(matching: .any)["weeklyVolumeLink"]
        XCTAssertTrue(weeklyVolumeLink.waitForExistence(timeout: 5))

        let exerciseHistoryLink = app.descendants(matching: .any)["exerciseHistoryLink"]
        XCTAssertTrue(exerciseHistoryLink.waitForExistence(timeout: 5))
    }

    func verifyDailyJournalForManualLogs() {
        tapTab("履歴")

        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))
        let todayID = Self.calendarDayFormatter.string(from: Date())
        let todayCalendarButton = app.buttons["historyCalendarDay-\(todayID)"]
        XCTAssertTrue(todayCalendarButton.waitForExistence(timeout: 5))
        XCTAssertTrue(todayCalendarButton.label.contains("食事1件"))
        XCTAssertTrue(todayCalendarButton.label.contains("写真1件"))
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

    func addManualMealEntry() {
        tapTab("記録")
        let mealListLink = scrollToHittable(app.descendants(matching: .any)["recordHubMealLink"])
        XCTAssertTrue(mealListLink.isHittable)
        mealListLink.tap()

        let addMealButton = app.buttons["addMealButton"]
        XCTAssertTrue(addMealButton.waitForExistence(timeout: 5))
        addMealButton.tap()

        let nameField = app.textFields["mealNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("鶏むね肉定食")

        let proteinField = app.textFields["mealProteinField"]
        XCTAssertTrue(proteinField.waitForExistence(timeout: 5))
        proteinField.tap()
        proteinField.typeText("31")
        app.buttons["dismiss-mealProteinField"].tap()

        let fatField = app.textFields["mealFatField"]
        XCTAssertTrue(fatField.waitForExistence(timeout: 5))
        fatField.tap()
        fatField.typeText("20")
        app.buttons["dismiss-mealFatField"].tap()

        let carbsField = app.textFields["mealCarbsField"]
        XCTAssertTrue(carbsField.waitForExistence(timeout: 5))
        carbsField.tap()
        carbsField.typeText("52")
        app.buttons["dismiss-mealCarbsField"].tap()

        XCTAssertTrue(app.staticTexts["P×4 + F×9 + C×4 = 512 kcal"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["saveMealButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let savedMeal = scrollToHittable(app.descendants(matching: .any)["mealRow-鶏むね肉定食"])
        XCTAssertTrue(savedMeal.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["512 kcal"].exists)
        XCTAssertTrue(app.staticTexts["1/3回"].exists)
        XCTAssertTrue(app.staticTexts["栄養途中"].exists)
    }

    func addBodyPhotoMemoEntry() {
        tapTab("記録")
        let bodyPhotoListLink = scrollToHittable(app.descendants(matching: .any)["recordHubBodyPhotoLink"])
        XCTAssertTrue(bodyPhotoListLink.isHittable)
        bodyPhotoListLink.tap()

        let addBodyPhotoButton = app.buttons["addBodyPhotoButton"]
        XCTAssertTrue(addBodyPhotoButton.waitForExistence(timeout: 5))
        addBodyPhotoButton.tap()

        let memoField = scrollToHittable(app.textFields["bodyPhotoMemoField"])
        XCTAssertTrue(memoField.exists)
        memoField.tap()
        memoField.typeText("正面メモ")

        let saveButton = app.buttons["saveBodyPhotoButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["bodyPhotoRow-front"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正面メモ"].exists)
    }

    func relaunchWithUnreachableAI() {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-ai-unreachable-settings",
            "--expand-home-details"
        ]
        app.launch()
    }

    func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 10) -> XCUIElement {
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable {
                return element
            }
            app.swipeUp()
        }
        return element
    }
}
