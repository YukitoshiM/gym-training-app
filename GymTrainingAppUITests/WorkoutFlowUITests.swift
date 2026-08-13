import XCTest

@MainActor
final class WorkoutFlowUITests: GymTrainingAppUITestCase {
    func testExerciseDetailShowsMuscleEquipmentAndMovementIllustration() {
        tapTab("計画")

        let library = app.buttons["exerciseLibraryLink"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("ベンチプレス")
        let keyboardSearch = app.keyboards.buttons["Search"]
        if keyboardSearch.exists {
            keyboardSearch.tap()
        }

        let libraryScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        libraryScreenshot.name = "Exercise library with photos"
        libraryScreenshot.lifetime = .keepAlways
        add(libraryScreenshot)

        let detailLink = scrollToHittable(
            app.descendants(matching: .any)["exerciseDetailLink-ベンチプレス"]
        )
        XCTAssertTrue(detailLink.isHittable)
        detailLink.tap()

        XCTAssertTrue(app.navigationBars["種目詳細"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.descendants(matching: .any)["exerciseIllustration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["exercisePhoto"].exists)
        XCTAssertTrue(app.staticTexts["フォーム参考"].exists)
        XCTAssertTrue(app.staticTexts["押し出す"].exists)
        XCTAssertTrue(app.staticTexts["バーベル"].exists)

        let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailScreenshot.name = "Exercise visual detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    func testAlphaWorkoutFlow() throws {
        verifySeededPlan()
        completeWorkoutFromPlan()
        verifyHistory()
    }

    func testPreviousPerformanceCopy() throws {
        completeWorkoutFromPlan()
        startWorkoutFromPlan()

        XCTAssertTrue(app.staticTexts["前回 20 kg × 10回"].waitForExistence(timeout: 5))

        let copyButton = app.buttons["copyPreviousSet-0-1"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
    }

    func testPreviousPerformancePrefillsNextWorkout() throws {
        startWorkoutFromPlan()

        replaceText(in: app.textFields["workoutWeightField-0-1"], with: "20.1")
        app.buttons["dismiss-workoutWeightField-0-1"].tap()
        replaceText(in: app.textFields["workoutRepsField-0-1"], with: "11")
        app.buttons["dismiss-workoutRepsField-0-1"].tap()

        completeCurrentWorkout()
        startWorkoutFromPlan()

        XCTAssertEqual(app.textFields["workoutWeightField-0-1"].value as? String, "20.1")
        XCTAssertEqual(app.textFields["workoutRepsField-0-1"].value as? String, "11")
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
        XCTAssertEqual(app.pickerWheels.count, 1)
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "20.2")

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

    func testAddingPlanSetCopiesPreviousSetTargets() throws {
        tapTab("計画")
        let createButton = app.buttons["createPlanToolbarButton"]
        if !createButton.waitForExistence(timeout: 5) {
            tapTab("計画")
        }
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let backTemplate = app.buttons["planTemplate-back"]
        XCTAssertTrue(backTemplate.waitForExistence(timeout: 5))
        backTemplate.tap()

        let initialWeight = app.textFields["planWeightField-0-1"]
        XCTAssertTrue(initialWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(initialWeight.value as? String, "50")

        let weightField = scrollToHittable(app.textFields["planWeightField-0-3"])
        XCTAssertTrue(weightField.isHittable)
        weightField.tap()
        weightField.typeText("42.3")
        app.buttons["dismiss-planWeightField-0-3"].tap()

        let repsField = app.textFields["planRepsField-0-3"]
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
        repsField.tap()
        repsField.typeText("7")
        app.buttons["dismiss-planRepsField-0-3"].tap()

        let addSetButton = scrollToHittable(app.buttons.matching(identifier: "addPlanSetButton").firstMatch)
        XCTAssertTrue(addSetButton.isHittable)
        addSetButton.tap()

        let copiedWeight = app.textFields["planWeightField-0-4"]
        let copiedReps = app.textFields["planRepsField-0-4"]
        XCTAssertTrue(copiedWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(copiedWeight.value as? String, "42.3")
        XCTAssertEqual(copiedReps.value as? String, "7")
    }

    func testLastPlanSetWeightPersistsWhenSavedWhileFocused() throws {
        tapTab("計画")
        app.buttons["createPlanToolbarButton"].tap()
        app.buttons["planTemplate-back"].tap()

        let weightField = scrollToHittable(app.textFields["planWeightField-0-3"])
        XCTAssertTrue(weightField.isHittable)
        weightField.tap()
        weightField.typeText("42.3")

        let saveButton = app.buttons["savePlanPinnedButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["背中の日"].waitForExistence(timeout: 5))
        app.staticTexts["背中の日"].firstMatch.tap()

        let savedWeightField = scrollToHittable(app.textFields["planWeightField-0-3"])
        XCTAssertTrue(savedWeightField.waitForExistence(timeout: 5))
        XCTAssertEqual(savedWeightField.value as? String, "42.3")
    }

    func testWatchWeightSuggestionUpdatesTheSourcePlan() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-watch-plan-weight-suggestion"
        ]
        app.launch()

        let alert = app.alerts["計画重量を更新しますか？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts["胸の日の目標重量を更新します。\nベンチプレス 20 kg → 22.5 kg（1セット）"].exists)
        alert.buttons["計画に反映"].tap()

        tapTab("計画")
        XCTAssertTrue(app.navigationBars["計画"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        app.staticTexts["胸の日"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["胸の日"].waitForExistence(timeout: 5))

        let updatedWeightField = app.textFields["planWeightField-0-1"]
        XCTAssertTrue(updatedWeightField.waitForExistence(timeout: 5))
        XCTAssertEqual(updatedWeightField.value as? String, "22.5")
    }

    func testAssistedDipWeightAndBodyweightSummary() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-assisted-ui-test-plan"
        ]
        app.launch()

        tapTab("記録")
        let startButton = app.descendants(matching: .any)["startWorkout-アシスト種目"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let weightField = app.textFields["workoutWeightField-0-1"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        XCTAssertEqual(weightField.value as? String, "-20")

        let summary = app.staticTexts["dipLoadSummary-0-1"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("体重 70 kg - アシスト 20 kg = 参考負荷 50 kg"))
    }

}
