import XCTest

@MainActor
final class GymTrainingWatchAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Watch notification permission") { alert in
            MainActor.assumeIsolated {
                for label in ["許可", "Allow"] {
                    let button = alert.buttons[label]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
    }

    func testWorkoutRecordingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2件から選択"].exists)
        XCTAssertTrue(app.staticTexts["胸の日"].exists)

        let chestMenu = findHittableElement(in: app, identifier: "watchMenu-胸の日")
        XCTAssertTrue(chestMenu.isHittable)
        chestMenu.tap()

        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ベンチプレス・3セット・計30回"].exists)

        let startButton = findHittableElement(in: app, identifier: "watchStartWorkoutButton")
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()

        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["watchLiveMetrics"].exists)
        XCTAssertTrue(app.staticTexts["118"].exists)
        XCTAssertTrue(app.staticTexts["平均112"].exists)
        XCTAssertTrue(app.staticTexts["最大126"].exists)
        XCTAssertTrue(app.staticTexts["Z2 3:00"].exists)

        let firstSetStartButton = app.buttons["watchStartNextSetButton"]
        XCTAssertTrue(firstSetStartButton.waitForExistence(timeout: 5))
        XCTAssertTrue(firstSetStartButton.isHittable)
        firstSetStartButton.tap()

        let cancelSetButton = app.buttons["watchCancelActiveSetButton"]
        XCTAssertTrue(cancelSetButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["watchCompleteActiveSetButton"].exists)
        cancelSetButton.tap()

        XCTAssertTrue(firstSetStartButton.waitForExistence(timeout: 5))
        firstSetStartButton.tap()
        XCTAssertTrue(app.buttons["watchCompleteActiveSetButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["watchTempoCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["watchTempoPauseButton"].exists)
        XCTAssertTrue(app.buttons["watchTempoSkipButton"].exists)

        let weightEntryButton = findHittableElement(in: app, identifier: "watchActiveWeightEntry")
        XCTAssertTrue(weightEntryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightEntryButton.isHittable)
        weightEntryButton.tap()

        let weightPicker = app.descendants(matching: .any)["watchWeightPicker"]
        XCTAssertTrue(weightPicker.waitForExistence(timeout: 5))
        let initialWeight = decimalValue(of: weightPicker)
        weightPicker.swipeUp()
        let selectedWeightValue = try XCTUnwrap(decimalValue(of: weightPicker))
        XCTAssertNotEqual(selectedWeightValue, initialWeight)

        let saveWeightButton = findHittableElement(in: app, identifier: "saveWatchWeightButton")
        XCTAssertTrue(saveWeightButton.isHittable)
        saveWeightButton.tap()

        let repsEntryButton = findHittableElement(in: app, identifier: "watchActiveRepsEntry")
        XCTAssertTrue(repsEntryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(repsEntryButton.isHittable)
        repsEntryButton.tap()

        let repsPicker = app.descendants(matching: .any)["watchRepsPicker"]
        XCTAssertTrue(repsPicker.waitForExistence(timeout: 5))
        let initialReps = integerValue(of: repsPicker)
        repsPicker.swipeUp()
        let selectedReps = try XCTUnwrap(integerValue(of: repsPicker))
        XCTAssertNotEqual(selectedReps, initialReps)

        let saveRepsButton = findHittableElement(in: app, identifier: "saveWatchRepsButton")
        XCTAssertTrue(saveRepsButton.isHittable)
        saveRepsButton.tap()

        let selectedWeight = "\(selectedWeightValue.formatted(.number.precision(.fractionLength(0...1)))) kg"
        let actualResult = app.staticTexts["watchActiveSetActual"]
        XCTAssertTrue(actualResult.waitForExistence(timeout: 5))
        XCTAssertEqual(actualResult.label, "実績 \(selectedWeight) × \(selectedReps)回")
        attachScreenshot(named: "watch-set-result-entry", app: app)

        let rpeButton = findHittableElement(in: app, identifier: "watchActiveRPEEntry")
        XCTAssertTrue(rpeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(rpeButton.isHittable)
        rpeButton.tap()

        let rpePicker = app.descendants(matching: .any)["watchRPEPicker"]
        XCTAssertTrue(rpePicker.waitForExistence(timeout: 5))
        let initialRPE = decimalValue(of: rpePicker)
        rpePicker.swipeUp()
        XCTAssertNotEqual(decimalValue(of: rpePicker), initialRPE)

        let saveRPEButton = findHittableElement(in: app, identifier: "saveWatchRPEButton")
        XCTAssertTrue(saveRPEButton.isHittable)
        saveRPEButton.tap()

        let firstSetButton = findHittableElement(in: app, identifier: "watchCompleteActiveSetButton")
        XCTAssertTrue(firstSetButton.waitForExistence(timeout: 5))
        XCTAssertTrue(firstSetButton.isHittable)
        firstSetButton.tap()

        let restLabel = app.descendants(matching: .any)["watchRestTimer"]
        XCTAssertTrue(restLabel.waitForExistence(timeout: 5))
        attachScreenshot(named: "watch-rest-timer", app: app)

        let restEntryButton = findHittableElement(in: app, identifier: "watchRestTimerEntry")
        XCTAssertTrue(restEntryButton.exists)
        XCTAssertTrue(restEntryButton.isHittable)
        restEntryButton.tap()

        let restPicker = app.descendants(matching: .any)["watchRestSecondsPicker"]
        if !restPicker.waitForExistence(timeout: 2) {
            let retryButton = findHittableElement(in: app, identifier: "watchRestTimerEntry")
            XCTAssertTrue(retryButton.isHittable)
            retryButton.tap()
        }
        XCTAssertTrue(restPicker.waitForExistence(timeout: 5))
        let initialRest = durationValue(of: restPicker)
        restPicker.swipeUp()
        XCTAssertNotEqual(durationValue(of: restPicker), initialRest)

        let saveRestButton = findHittableElement(in: app, identifier: "saveWatchRestSecondsButton")
        XCTAssertTrue(saveRestButton.isHittable)
        saveRestButton.tap()

        app.terminate()
        app.launchArguments = ["--suppress-watch-tutorial"]
        app.launch()

        let restLabelAfterRelaunch = app.descendants(matching: .any)["watchRestTimer"]
        XCTAssertTrue(restLabelAfterRelaunch.waitForExistence(timeout: 10))

        app.swipeUp()
        let finishButton = app.buttons["watchFinishWorkoutButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertTrue(finishButton.isHittable)
        finishButton.tap()

        let confirmButton = app.buttons["完了してiPhoneへ送信"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2件から選択"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watchRecentSession"].exists)
        let restoredMenu = findHittableElement(in: app, identifier: "watchMenu-胸の日")
        XCTAssertTrue(restoredMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredMenu.isHittable)
    }

    func testCanChooseAnotherMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))

        let backMenu = findHittableElement(in: app, identifier: "watchMenu-背中の日")
        XCTAssertTrue(backMenu.isHittable)
        backMenu.tap()

        XCTAssertTrue(app.staticTexts["背中の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ラットプルダウン・3セット・計36回"].exists)
        XCTAssertTrue(app.buttons["watchStartWorkoutButton"].exists)
    }

    func testOutdoorWorkoutCanBeConfiguredAndStartedWithoutStrengthPlan() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial"
        ]
        app.launch()

        let outdoorLink = findHittableElement(in: app, identifier: "watchOutdoorWorkoutLink")
        XCTAssertTrue(outdoorLink.waitForExistence(timeout: 10))
        outdoorLink.tap()

        let startButton = findHittableElement(in: app, identifier: "watchStartOutdoorWorkoutButton")
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["watchOutdoorDistance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["一時停止"].exists)
    }

    func testSwitchingSetsResetsThePreviousSetAndCarriesWeightForward() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial",
            "--seed-watch-set-switch-state"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["記録中"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ベンチプレス・セット2"].waitForExistence(timeout: 5))
        let activeSetActual = app.staticTexts["watchActiveSetActual"]
        XCTAssertTrue(activeSetActual.waitForExistence(timeout: 5))
        XCTAssertEqual(activeSetActual.label, "実績 52.5 kg × 10回")
    }

    func testSetStartsAtPlanTargetAndTempoCanBeConfiguredBeforeStart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial"
        ]
        app.launch()

        let chestMenu = findHittableElement(in: app, identifier: "watchMenu-胸の日")
        XCTAssertTrue(chestMenu.waitForExistence(timeout: 10))
        chestMenu.tap()
        findHittableElement(in: app, identifier: "watchStartWorkoutButton").tap()

        let tempoButton = findHittableElement(in: app, identifier: "watchSelectedTempoEntry-0-1")
        XCTAssertTrue(tempoButton.waitForExistence(timeout: 5))
        XCTAssertTrue(tempoButton.isHittable)
        XCTAssertEqual(tempoButton.value as? String, "上2s・下3s・1回/秒")
        tempoButton.tap()

        let speedPicker = app.descendants(matching: .any)["watchTempoSpeedPicker"]
        XCTAssertTrue(speedPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittableElement(in: app, element: speedPicker))
        speedPicker.swipeUp()
        speedPicker.swipeUp()
        findHittableElement(in: app, identifier: "saveWatchTempoButton").tap()

        let savedTempoButton = findHittableElement(in: app, identifier: "watchSelectedTempoEntry-0-1")
        XCTAssertTrue(savedTempoButton.waitForExistence(timeout: 5))
        XCTAssertNotEqual(savedTempoButton.value as? String, "上2s・下3s・1回/秒")
        let savedSpeed = savedTempoButton.value as? String
        XCTAssertEqual(savedSpeed, "上2s・下3s・3回/秒")

        let startButton = findHittableElement(in: app, identifier: "watchStartNextSetButton")
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()

        let actual = app.staticTexts["watchActiveSetActual"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        XCTAssertEqual(actual.label, "実績 50 kg × 10回")
        let tempoCue = app.staticTexts["watchTempoCue"].firstMatch
        XCTAssertTrue(tempoCue.waitForExistence(timeout: 5))
        XCTAssertEqual(tempoCue.value as? String, savedSpeed?.components(separatedBy: "・").last)
    }

    func testTutorialAppearsOnFirstLaunchWithoutForceFlag() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 10))
        app.buttons["skipWatchTutorialButton"].tap()
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 5))
    }

    func testTutorialCanBeCompletedAndReopened() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--show-watch-tutorial"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 10))
        for page in 1...5 {
            XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-\(page)"].exists)
            app.buttons["nextWatchTutorialButton"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-6"].waitForExistence(timeout: 5))
        app.buttons["completeWatchTutorialButton"].tap()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 5))
        let tutorialButton = app.buttons["Apple Watchの使い方"].firstMatch
        XCTAssertTrue(tutorialButton.waitForExistence(timeout: 5))
        XCTAssertEqual(tutorialButton.label, "Apple Watchの使い方")
        tutorialButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 5))
        app.buttons["skipWatchTutorialButton"].tap()
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 5))
    }

    func testTutorialCanBeSkippedWithoutAutomaticallyReappearing() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--show-watch-tutorial"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 10))
        let skipButton = app.buttons["skipWatchTutorialButton"]
        XCTAssertTrue(skipButton.exists)
        skipButton.tap()
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skipWatchTutorialButton"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 2))

        let tutorialButton = app.buttons["Apple Watchの使い方"].firstMatch
        XCTAssertTrue(tutorialButton.waitForExistence(timeout: 5))
        XCTAssertEqual(tutorialButton.label, "Apple Watchの使い方")
        tutorialButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchTutorialPage-1"].waitForExistence(timeout: 5))
    }

    func testEnglishSocialPromoActiveSetScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let menu = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "watchMenu-")
        ).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(findHittableElement(in: app, identifier: menu.identifier).isHittable)
        menu.tap()

        let startWorkout = findHittableElement(in: app, identifier: "watchStartWorkoutButton")
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 5))
        startWorkout.tap()

        let startSet = app.buttons["watchStartNextSetButton"]
        XCTAssertTrue(startSet.waitForExistence(timeout: 5))
        startSet.tap()
        XCTAssertTrue(app.buttons["watchCompleteActiveSetButton"].waitForExistence(timeout: 5))

        let directory = URL(fileURLWithPath: "/tmp/bodymode-social-en", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(
            to: directory.appendingPathComponent("02-active-set-en.png")
        )
    }

    func testEnglishAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan",
            "--suppress-watch-tutorial",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let directory = URL(fileURLWithPath: "/tmp/bodymode-watch-app-store-en", isDirectory: true)
        try FileManager.default.removeItemIfExists(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let menu = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "watchMenu-")
        ).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        try writeScreenshot(named: "01-menu-selection.png", app: app, directory: directory)

        let hittableMenu = findHittableElement(in: app, identifier: menu.identifier)
        XCTAssertTrue(hittableMenu.isHittable)
        hittableMenu.tap()

        let startWorkout = findHittableElement(in: app, identifier: "watchStartWorkoutButton")
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 5))
        try writeScreenshot(named: "03-plan-detail.png", app: app, directory: directory)
        startWorkout.tap()

        XCTAssertTrue(app.descendants(matching: .any)["watchLiveMetrics"].waitForExistence(timeout: 5))
        let startSet = findHittableElement(in: app, identifier: "watchStartNextSetButton")
        XCTAssertTrue(startSet.waitForExistence(timeout: 5))
        startSet.tap()
        XCTAssertTrue(app.buttons["watchCompleteActiveSetButton"].waitForExistence(timeout: 5))
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.35)
        try writeScreenshot(named: "02-active-set.png", app: app, directory: directory)

    }

    private func findHittableElement(
        in app: XCUIApplication,
        identifier: String,
        maxRotations: Int = 12
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]

        for _ in 0..<maxRotations {
            if element.exists, element.isHittable {
                return element
            }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.2)
        }

        return element
    }

    private func scrollToHittableElement(
        in app: XCUIApplication,
        element: XCUIElement,
        maxRotations: Int = 12
    ) -> Bool {
        for _ in 0..<maxRotations {
            if element.exists, element.isHittable {
                return true
            }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.2)
        }
        return element.exists && element.isHittable
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func writeScreenshot(named name: String, app: XCUIApplication, directory: URL) throws {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name))
    }

    private func integerValue(of element: XCUIElement) -> Int? {
        let digits = rawValue(of: element).filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private func decimalValue(of element: XCUIElement) -> Double? {
        let value = rawValue(of: element)
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(value)
    }

    private func durationValue(of element: XCUIElement) -> Int? {
        let parts = rawValue(of: element).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private func rawValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? String(describing: element.value)
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else { return }
        try removeItem(at: url)
    }
}
