import XCTest

@MainActor
final class WatchFigmaReferenceScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--reset-watch-ui-test-data",
            "--seed-watch-ui-test-plan"
        ]
        app.launch()
    }

    func testWatchFeatureScreens() throws {
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        capture("01-watch-menu-selection")

        let chestMenu = findHittable("watchMenu-胸の日")
        XCTAssertTrue(chestMenu.isHittable)
        chestMenu.tap()
        XCTAssertTrue(app.staticTexts["胸の日"].waitForExistence(timeout: 5))
        capture("02-watch-plan-detail")

        let benchPress = findHittableElement(app.staticTexts["ベンチプレス"].firstMatch)
        XCTAssertTrue(benchPress.isHittable)
        benchPress.tap()
        XCTAssertTrue(app.navigationBars["ベンチプレス"].waitForExistence(timeout: 5))
        capture("03-watch-exercise-preview")
        app.navigationBars["ベンチプレス"].buttons.firstMatch.tap()
        XCUIDevice.shared.rotateDigitalCrown(delta: -1)

        let startButton = findHittable("watchStartWorkoutButton")
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()
        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))
        capture("04-watch-active-workout")

        let nextSetButton = findHittable("watchStartNextSetButton")
        XCTAssertTrue(nextSetButton.isHittable)
        nextSetButton.tap()
        XCTAssertTrue(app.buttons["watchCompleteActiveSetButton"].waitForExistence(timeout: 5))
        capture("05-watch-active-set")

        let weightButton = findBySwiping(
            app.buttons["重量をリールで設定"].firstMatch,
            direction: .up
        )
        XCTAssertTrue(weightButton.isHittable)
        weightButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchWeightPicker"].waitForExistence(timeout: 5))
        capture("06-watch-weight-wheel")
        findHittable("saveWatchWeightButton").tap()

        let repsButton = findBySwiping(
            app.buttons["回数をリールで設定"].firstMatch,
            direction: .up
        )
        XCTAssertTrue(repsButton.isHittable)
        repsButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchRepsPicker"].waitForExistence(timeout: 5))
        capture("07-watch-reps-wheel")
        findHittable("saveWatchRepsButton").tap()

        let completeButton = findBySwiping(
            app.buttons["watchCompleteActiveSetButton"],
            direction: .down
        )
        XCTAssertTrue(completeButton.isHittable)
        completeButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchRestTimer"].waitForExistence(timeout: 5))
        capture("08-watch-rest-timer")

        let restEntry = findBySwiping(
            app.descendants(matching: .any)["watchRestTimerEntry"],
            direction: .up
        )
        XCTAssertTrue(restEntry.isHittable)
        restEntry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchRestSecondsPicker"].waitForExistence(timeout: 5))
        capture("09-watch-rest-timer-wheel")
        findHittable("saveWatchRestSecondsButton").tap()

        let finishButton = findBySwiping(
            app.buttons["watchFinishWorkoutButton"],
            direction: .up
        )
        XCTAssertTrue(finishButton.isHittable)
        finishButton.tap()
        XCTAssertTrue(app.buttons["完了してiPhoneへ送信"].waitForExistence(timeout: 5))
        app.buttons["完了してiPhoneへ送信"].tap()

        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        let recentSession = findBySwiping(
            app.descendants(matching: .any)["watchRecentSession"],
            direction: .up
        )
        XCTAssertTrue(recentSession.isHittable)
        recentSession.tap()
        XCTAssertTrue(app.navigationBars["完了セット"].waitForExistence(timeout: 5))
        capture("10-watch-completed-set-archive")
    }

    func testWatchAdditionalFeatureScreens() throws {
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        let chestMenu = findHittable("watchMenu-胸の日")
        XCTAssertTrue(chestMenu.isHittable)
        chestMenu.tap()

        let startButton = findHittable("watchStartWorkoutButton")
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()
        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))

        swipe(.up)

        let nextSetButton = findBySwiping(
            app.buttons["watchStartNextSetButton"],
            direction: .down
        )
        XCTAssertTrue(nextSetButton.isHittable)
        nextSetButton.tap()

        let rpeButton = findBySwiping(
            app.descendants(matching: .any)["watchSetRPE-0-1"],
            direction: .up
        )
        XCTAssertTrue(rpeButton.isHittable)
        rpeButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watchRPEPicker"].waitForExistence(timeout: 5))
        capture("12-watch-rpe-wheel")
        findHittable("saveWatchRPEButton").tap()

        let noteButton = findBySwiping(
            app.buttons["watchWorkoutNoteButton"],
            direction: .up
        )
        XCTAssertTrue(noteButton.isHittable)
        noteButton.tap()
        XCTAssertTrue(app.navigationBars["メモ"].waitForExistence(timeout: 5))
        capture("13-watch-workout-note")
    }

    func testWatchLiveMetricsScreen() throws {
        XCTAssertTrue(app.staticTexts["今日のメニュー"].waitForExistence(timeout: 10))
        let chestMenu = findHittable("watchMenu-胸の日")
        XCTAssertTrue(chestMenu.isHittable)
        chestMenu.tap()

        let startButton = findHittable("watchStartWorkoutButton")
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()
        XCTAssertTrue(app.staticTexts["0/3セット・0回記録"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)
                ),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        capture("11-watch-live-metrics")
    }

    private func findHittable(
        _ identifier: String,
        maxRotations: Int = 16
    ) -> XCUIElement {
        findHittableElement(
            app.descendants(matching: .any)[identifier],
            maxRotations: maxRotations
        )
    }

    private func findHittableElement(
        _ element: XCUIElement,
        maxRotations: Int = 16
    ) -> XCUIElement {
        for _ in 0..<maxRotations {
            if element.exists, element.isHittable {
                return element
            }
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.18)
        }
        return element
    }

    private enum SwipeDirection {
        case up
        case down
    }

    private func findBySwiping(
        _ element: XCUIElement,
        direction: SwipeDirection,
        maxSwipes: Int = 8
    ) -> XCUIElement {
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable {
                return element
            }
            swipe(direction)
        }
        return element
    }

    private func swipe(_ direction: SwipeDirection) {
        let startY = direction == .up ? 0.78 : 0.30
        let endY = direction == .up ? 0.34 : 0.76
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.15,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                )
            )
    }

    private func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
