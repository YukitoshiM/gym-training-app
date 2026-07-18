import XCTest

@MainActor
final class GymTrainingWatchAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWorkoutRecordingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan"
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
        XCTAssertTrue(startButton.exists)
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

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
            )
        let weightEntryButton = app.buttons["重量をリールで設定"].firstMatch
        XCTAssertTrue(weightEntryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(weightEntryButton.isHittable)
        weightEntryButton.tap()

        let wholePicker = app.descendants(matching: .any)["watchWeightWholePicker"]
        let tenthsPicker = app.descendants(matching: .any)["watchWeightTenthsPicker"]
        XCTAssertTrue(wholePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(tenthsPicker.waitForExistence(timeout: 5))
        let initialTenths = integerValue(of: tenthsPicker)
        tenthsPicker.swipeUp()
        let selectedWhole = try XCTUnwrap(integerValue(of: wholePicker))
        let selectedTenths = try XCTUnwrap(integerValue(of: tenthsPicker))
        XCTAssertNotEqual(selectedTenths, initialTenths)

        let saveWeightButton = findHittableElement(in: app, identifier: "saveWatchWeightButton")
        XCTAssertTrue(saveWeightButton.isHittable)
        saveWeightButton.tap()

        let repsEntryButton = findHittableElement(in: app, identifier: "watchSetRepsEntry-0-1")
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

        let selectedWeight = "\(selectedWhole).\(selectedTenths) kg"
        XCTAssertTrue(app.staticTexts["実績 \(selectedWeight) × \(selectedReps)回"].exists)
        attachScreenshot(named: "watch-set-result-entry", app: app)

        let rpeButton = findHittableElement(in: app, identifier: "watchSetRPE-0-1")
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

        let firstSetButton = findHittableElement(in: app, identifier: "watchSetComplete-0-1")
        XCTAssertTrue(firstSetButton.isHittable)
        firstSetButton.tap()

        XCUIDevice.shared.rotateDigitalCrown(delta: -1)
        let progressText = "1/3セット・\(selectedReps)回記録"
        XCTAssertTrue(app.staticTexts[progressText].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.44))
            )
        let restLabel = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "休憩 ")
        ).firstMatch
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
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.staticTexts[progressText].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.44))
            )
        let restLabelAfterRelaunch = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "休憩 ")
        ).firstMatch
        XCTAssertTrue(restLabelAfterRelaunch.waitForExistence(timeout: 5))

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
        XCTAssertTrue(app.descendants(matching: .any)["watchMenu-胸の日"].exists)
    }

    func testCanChooseAnotherMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan"
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

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
