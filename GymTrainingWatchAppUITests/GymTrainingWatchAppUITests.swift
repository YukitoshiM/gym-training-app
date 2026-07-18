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

        XCTAssertTrue(app.staticTexts["Watch UIテスト"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ベンチプレス・3セット・計30回"].exists)

        let startButton = app.buttons["watchStartWorkoutButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))

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
        XCTAssertTrue(app.staticTexts["1/3セット・10回記録"].waitForExistence(timeout: 5))

        app.swipeUp()
        let finishButton = app.buttons["watchFinishWorkoutButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertTrue(finishButton.isHittable)
        finishButton.tap()

        let confirmButton = app.buttons["完了してiPhoneへ送信"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["Watch UIテスト"].waitForExistence(timeout: 10))
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
}
