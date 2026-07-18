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

        let startButton = app.buttons["watchStartWorkoutButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))

        let firstSetStartButton = findHittableElement(in: app, identifier: "watchSetStart-0-1")
        XCTAssertTrue(firstSetStartButton.isHittable)
        firstSetStartButton.tap()

        let repsPlusButton = findHittableElement(in: app, identifier: "watchSetRepsPlus-0-1")
        XCTAssertTrue(repsPlusButton.isHittable)
        repsPlusButton.tap()

        XCTAssertTrue(app.staticTexts["実績 20 kg × 11回"].exists)
        attachScreenshot(named: "watch-set-result-entry", app: app)

        let rpeButton = findHittableElement(in: app, identifier: "watchSetRPE-0-1")
        XCTAssertTrue(rpeButton.isHittable)
        rpeButton.tap()

        let rpeEightButton = findHittableElement(in: app, identifier: "watchRPE-8")
        XCTAssertTrue(rpeEightButton.isHittable)
        rpeEightButton.tap()

        let firstSetButton = findHittableElement(in: app, identifier: "watchSetComplete-0-1")
        XCTAssertTrue(firstSetButton.isHittable)
        firstSetButton.tap()

        XCUIDevice.shared.rotateDigitalCrown(delta: -1)
        XCTAssertTrue(app.staticTexts["1/3セット・11回記録"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["watchRestTimer"].waitForExistence(timeout: 5))
        attachScreenshot(named: "watch-rest-timer", app: app)

        let extendRestButton = app.buttons["+30秒"]
        XCTAssertTrue(extendRestButton.isHittable)
        extendRestButton.tap()

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.staticTexts["1/3セット・11回記録"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["watchRestTimer"].waitForExistence(timeout: 5))

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
        maxRotations: Int = 6
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]

        for _ in 0..<maxRotations where !element.isHittable {
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.15)
        }

        return element
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
