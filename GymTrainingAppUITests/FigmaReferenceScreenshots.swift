import XCTest

@MainActor
final class FigmaReferenceScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-theme-royal-cobalt",
            "--force-light-appearance",
            "--seed-sensor-ui-test-data"
        ]
        app.launch()
    }

    func test01ThemeSamples() throws {
        waitForHome()
        capture("01-iphone-theme-b-royal-cobalt-light")

        launch(
            additionalArguments: [
                "--seed-theme-black-champagne",
                "--force-light-appearance",
                "--seed-sensor-ui-test-data"
            ]
        )
        waitForHome()
        capture("02-iphone-theme-d-black-champagne-dark")
    }

    func test02HomeDashboard() {
        waitForHome()
        capture("03-iphone-home-dashboard")
    }

    func test03PlansAndExerciseLibrary() throws {
        tapTab("計画")
        XCTAssertTrue(app.navigationBars["計画"].waitForExistence(timeout: 5))
        capture("08-iphone-plan-list")

        app.buttons["createPlanToolbarButton"].tap()
        XCTAssertTrue(app.navigationBars["計画作成"].waitForExistence(timeout: 5))
        capture("09-iphone-plan-editor")

        app.buttons["planTemplate-back"].tap()
        XCTAssertTrue(app.navigationBars["背中の日"].waitForExistence(timeout: 5))
        capture("10-iphone-plan-template-and-sets")

        let addExerciseButton = scrollToHittable(app.buttons["addExerciseToPlanButton"])
        XCTAssertTrue(addExerciseButton.isHittable)
        addExerciseButton.tap()
        XCTAssertTrue(app.navigationBars["種目を選択"].waitForExistence(timeout: 5))
        capture("11-iphone-exercise-picker")

        app.navigationBars["種目を選択"].buttons["閉じる"].tap()
        app.navigationBars["背中の日"].buttons["キャンセル"].tap()

        let libraryLink = app.buttons["exerciseLibraryLink"]
        XCTAssertTrue(libraryLink.waitForExistence(timeout: 5))
        libraryLink.tap()
        XCTAssertTrue(app.navigationBars["種目"].waitForExistence(timeout: 5))
        capture("12-iphone-exercise-library")

        app.buttons["addCustomExerciseButton"].tap()
        XCTAssertTrue(app.navigationBars["カスタム種目"].waitForExistence(timeout: 5))
        capture("14-iphone-custom-exercise-editor")
        app.navigationBars["カスタム種目"].buttons["キャンセル"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("ベンチプレス")

        let benchPress = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "ベンチプレス")
        ).firstMatch
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5))
        benchPress.tap()
        XCTAssertTrue(app.navigationBars["種目詳細"].waitForExistence(timeout: 5))
        capture("13-iphone-exercise-detail")
    }

    func test04RecordsBodyMealsAndPhotos() throws {
        tapTab("記録")
        XCTAssertTrue(app.navigationBars["記録"].waitForExistence(timeout: 5))
        capture("15-iphone-record-hub")

        app.buttons["recordHubBodyWeightLink"].tap()
        XCTAssertTrue(app.navigationBars["体重"].waitForExistence(timeout: 5))
        capture("16-iphone-body-weight-chart")

        app.buttons["addBodyMetricEntryButton"].tap()
        XCTAssertTrue(app.navigationBars["体重を記録"].waitForExistence(timeout: 5))
        let metricField = app.textFields["bodyMetricValueField"]
        XCTAssertTrue(metricField.waitForExistence(timeout: 5))
        metricField.tap()
        metricField.typeText("72.4")
        dismissKeyboardIfPresent()
        capture("17-iphone-body-weight-entry")
        app.buttons["saveBodyMetricEntryButton"].tap()
        XCTAssertTrue(app.staticTexts["72.4 kg"].waitForExistence(timeout: 5))
        capture("18-iphone-body-weight-chart-recorded")

        navigateBack(from: "体重")
        app.buttons["recordHubMealLink"].tap()
        XCTAssertTrue(app.navigationBars["食事"].waitForExistence(timeout: 5))
        capture("19-iphone-meal-list")

        app.buttons["addMealButton"].tap()
        XCTAssertTrue(app.navigationBars["食事を記録"].waitForExistence(timeout: 5))
        fillMealDraft()
        capture("20-iphone-meal-manual-editor")
        app.buttons["saveMealButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mealRow-鶏むね肉定食"].waitForExistence(timeout: 5))
        capture("21-iphone-meal-list-recorded")

        navigateBack(from: "食事")
        app.buttons["recordHubBodyPhotoLink"].tap()
        XCTAssertTrue(app.navigationBars["体型写真"].waitForExistence(timeout: 5))
        capture("22-iphone-body-photo-list")

        app.buttons["addBodyPhotoButton"].tap()
        XCTAssertTrue(app.navigationBars["撮影セットを追加"].waitForExistence(timeout: 5))
        let memoField = scrollToHittable(app.descendants(matching: .any)["bodyPhotoMemoField"])
        XCTAssertTrue(memoField.isHittable)
        memoField.tap()
        memoField.typeText("正面・自然光・同じ姿勢")
        dismissKeyboardIfPresent()
        capture("23-iphone-body-photo-editor")
    }

    func test05WorkoutHistoryAndAnalytics() throws {
        tapTab("記録")
        let workoutButton = scrollToHittable(app.descendants(matching: .any)["startWorkout-胸の日"])
        XCTAssertTrue(workoutButton.isHittable)
        workoutButton.tap()

        XCTAssertTrue(app.navigationBars["胸の日"].waitForExistence(timeout: 5))
        capture("24-iphone-workout-session")

        let firstSet = app.switches["completeSetToggle-0-1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        XCTAssertTrue(app.buttons["restTimerButton"].waitForExistence(timeout: 5))
        capture("25-iphone-workout-rest-timer")

        for index in 2...3 {
            let toggle = app.switches["completeSetToggle-0-\(index)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.tap()
        }

        app.buttons["finishWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["完了して履歴に保存"].waitForExistence(timeout: 5))
        app.buttons["完了して履歴に保存"].tap()
        XCTAssertTrue(app.navigationBars["完了"].waitForExistence(timeout: 5))
        capture("26-iphone-workout-summary")
        app.buttons["閉じる"].tap()

        tapTab("履歴")
        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))
        capture("27-iphone-history-calendar")

        let historyRow = scrollToHittable(app.descendants(matching: .any)["historyRow-胸の日"])
        XCTAssertTrue(historyRow.isHittable)
        historyRow.tap()
        XCTAssertTrue(app.navigationBars["履歴詳細"].waitForExistence(timeout: 5))
        capture("28-iphone-history-detail")

        navigateBack(from: "履歴詳細")
        let weeklyVolume = scrollToHittable(app.descendants(matching: .any)["weeklyVolumeLink"])
        XCTAssertTrue(weeklyVolume.isHittable)
        weeklyVolume.tap()
        XCTAssertTrue(app.navigationBars["週次ボリューム"].waitForExistence(timeout: 5))
        capture("29-iphone-weekly-volume")

        navigateBack(from: "週次ボリューム")
        let exerciseHistory = app.descendants(matching: .any)["exerciseHistoryLink"]
        XCTAssertTrue(exerciseHistory.waitForExistence(timeout: 5))
        exerciseHistory.tap()
        XCTAssertTrue(app.navigationBars["種目別履歴"].waitForExistence(timeout: 5))
        capture("30-iphone-exercise-history")

        let benchPress = app.staticTexts["ベンチプレス"].firstMatch
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5))
        benchPress.tap()
        XCTAssertTrue(app.navigationBars["ベンチプレス"].waitForExistence(timeout: 5))
        capture("31-iphone-exercise-history-detail")
    }

    func test06Settings() throws {
        waitForHome()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        capture("32-iphone-settings-profile-and-appearance")

        let aiStatus = scrollToHittable(app.descendants(matching: .any)["aiManagedConnectionStatus"])
        XCTAssertTrue(aiStatus.isHittable)
        capture("33-iphone-settings-health-and-local-ai")
    }

    func test07AICoachExperience() throws {
        launch(
            additionalArguments: [
                "--seed-theme-royal-cobalt",
                "--force-light-appearance",
                "--stub-ai-trainer"
            ]
        )
        tapTab("AI")
        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 5))
        capture("34-iphone-ai-coach-hub")

        app.buttons["aiHubTrainerLink"].tap()
        XCTAssertTrue(app.navigationBars["Nia"].waitForExistence(timeout: 5))
        capture("35-iphone-ai-coach-chat")
    }

    func test08EnglishSocialPromoScreenshots() throws {
        launch(
            additionalArguments: [
                "--seed-theme-royal-cobalt",
                "--force-light-appearance",
                "--stub-ai-trainer",
                "--disable-app-tour",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US"
            ]
        )

        waitForHome()
        try captureEnglishStoreScreenshot("01-home-dashboard")

        tapTab("AI")
        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("02-ai-coach-hub")

        app.buttons["aiHubTrainerLink"].tap()
        XCTAssertTrue(app.navigationBars["Nia"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("03-ai-coach-chat")

        tapTab("Plan")
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("07-plan-list")

        tapTab("Record")
        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("08-record-hub")

        app.buttons["recordHubBodyWeightLink"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))

        app.buttons["addBodyMetricEntryButton"].tap()
        let metricField = app.textFields["bodyMetricValueField"]
        XCTAssertTrue(metricField.waitForExistence(timeout: 5))
        metricField.tap()
        metricField.typeText("72.4")
        let dismissButton = app.buttons["dismiss-bodyMetricValueField"]
        if dismissButton.waitForExistence(timeout: 2) {
            dismissButton.tap()
        }
        app.buttons["saveBodyMetricEntryButton"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("06-body-progress")
        app.navigationBars["Weight"].buttons.firstMatch.tap()

        let workoutButton = scrollToHittable(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "startWorkout-")
            ).firstMatch
        )
        XCTAssertTrue(workoutButton.isHittable)
        workoutButton.tap()
        XCTAssertTrue(app.buttons["finishWorkoutButton"].waitForExistence(timeout: 5))

        for index in 1...3 {
            let toggle = app.switches["completeSetToggle-0-\(index)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.tap()
        }
        app.buttons["finishWorkoutButton"].tap()
        XCTAssertTrue(app.buttons["Save to history"].waitForExistence(timeout: 5))
        app.buttons["Save to history"].tap()
        XCTAssertTrue(app.navigationBars["Completed"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("04-workout-session")
        app.buttons["Close"].tap()

        tapTab("History")
        XCTAssertTrue(app.descendants(matching: .any)["historyCalendar"].waitForExistence(timeout: 5))
        try captureEnglishStoreScreenshot("05-history-calendar")
    }

    private func launch(additionalArguments: [String]) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan"
        ] + additionalArguments
        app.launch()
    }

    private func waitForHome() {
        XCTAssertTrue(app.navigationBars["BodyMode"].waitForExistence(timeout: 10))
    }

    private func tapTab(_ title: String) {
        let stableTabButton = app.buttons["rootTab-\(title)"]
        if stableTabButton.waitForExistence(timeout: 1) {
            stableTabButton.tap()
            return
        }

        let systemTabButton = app.tabBars.buttons[title]
        XCTAssertTrue(systemTabButton.waitForExistence(timeout: 5))
        systemTabButton.tap()
    }

    private func navigateBack(from navigationTitle: String) {
        let navigationBar = app.navigationBars[navigationTitle]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        navigationBar.buttons.firstMatch.tap()
    }

    private enum ScrollDirection {
        case up
        case down
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        direction: ScrollDirection = .up,
        maxSwipes: Int = 12
    ) -> XCUIElement {
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable {
                return element
            }
            switch direction {
            case .up:
                app.swipeUp()
            case .down:
                app.swipeDown()
            }
        }
        return element
    }

    private func fillMealDraft() {
        let nameField = app.textFields["mealNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("鶏むね肉定食")

        enter("31", in: "mealProteinField")
        enter("20", in: "mealFatField")
        enter("52", in: "mealCarbsField")
        XCTAssertTrue(app.staticTexts["P×4 + F×9 + C×4 = 512 kcal"].waitForExistence(timeout: 5))
    }

    private func enter(_ value: String, in identifier: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(value)
        let dismissButton = app.buttons["dismiss-\(identifier)"]
        if dismissButton.waitForExistence(timeout: 2) {
            dismissButton.tap()
        }
    }

    private func dismissKeyboardIfPresent() {
        let doneButton = app.buttons["入力完了"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        }
    }

    private func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureEnglishStoreScreenshot(_ name: String) throws {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let directory = URL(fileURLWithPath: "/tmp/bodymode-app-store-en", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
