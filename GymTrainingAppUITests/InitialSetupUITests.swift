import XCTest

final class InitialSetupUITests: XCTestCase {
    @MainActor
    func testCompletesInitialSetupAndOpensHome() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--force-initial-setup",
            "--force-dark-appearance"
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["initialSetupStep-welcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["理想の身体へ、迷わず進む。"].exists)
        addScreenshot(named: "Initial setup welcome")
        app.buttons["setupContinueButton"].tap()

        XCTAssertTrue(app.otherElements["initialSetupStep-purpose"].waitForExistence(timeout: 5))
        app.buttons["setupGoal-muscleGain"].tap()
        app.buttons["setupContinueButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["initialSetupStep-pace"].waitForExistence(timeout: 3))
        app.buttons["setupContinueButton"].tap()

        XCTAssertTrue(app.otherElements["initialSetupStep-equipment"].waitForExistence(timeout: 3))
        app.buttons["setupContinueButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["initialSetupStep-metrics"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["setupFinishButton"].tap()

        XCTAssertTrue(app.buttons["rootTab-ホーム"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["appTourOverlay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今日やることはここ"].exists)
        XCTAssertTrue(app.buttons["rootTab-ホーム"].isSelected)
        addScreenshot(named: "App tour home")

        assertTourStep(
            app: app,
            title: "ここから今日を開始",
            selectedTab: "ホーム",
            screenshotName: "App tour home control"
        )
        assertTourStep(
            app: app,
            title: "写真と数値はここ",
            selectedTab: "記録",
            screenshotName: "App tour record"
        )
        assertTourStep(
            app: app,
            title: "記録する項目をタップ",
            selectedTab: "記録",
            screenshotName: "App tour record controls"
        )
        assertTourStep(
            app: app,
            title: "迷ったらここ",
            selectedTab: "AI",
            screenshotName: "App tour AI"
        )
        assertTourStep(
            app: app,
            title: "担当コーチに相談",
            selectedTab: "AI",
            screenshotName: "App tour AI trainer"
        )
        assertTourStep(
            app: app,
            title: "写真からすぐ分析",
            selectedTab: "AI",
            screenshotName: "App tour AI photo tools"
        )
        assertTourStep(
            app: app,
            title: "メニューはここ",
            selectedTab: "計画",
            screenshotName: "App tour plans"
        )
        assertTourStep(
            app: app,
            title: "AIとメニューを作る",
            selectedTab: "計画",
            screenshotName: "App tour plan coach"
        )
        assertTourStep(
            app: app,
            title: "種目を探す・追加する",
            selectedTab: "計画",
            screenshotName: "App tour exercise library"
        )
        assertTourStep(
            app: app,
            title: "変化はここ",
            selectedTab: "履歴",
            screenshotName: "App tour history"
        )
        assertTourStep(
            app: app,
            title: "記録はここにたまる",
            selectedTab: "履歴",
            screenshotName: "App tour history control"
        )

        app.buttons["appTourFinishButton"].tap()
        XCTAssertFalse(app.otherElements["appTourOverlay"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func assertTourStep(
        app: XCUIApplication,
        title: String,
        selectedTab: String,
        screenshotName: String? = nil
    ) {
        app.buttons["appTourNextButton"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rootTab-\(selectedTab)"].isSelected)
        if let screenshotName {
            addScreenshot(named: screenshotName)
        }
    }

    @MainActor
    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
