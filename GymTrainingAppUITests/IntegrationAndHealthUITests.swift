import XCTest

@MainActor
final class IntegrationAndHealthUITests: GymTrainingAppUITestCase {
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
        tapTab("記録")

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
            "--seed-sensor-ui-test-data",
            "--expand-home-details"
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

    func testConditionRecordAndHistoryNavigationRemainsStable() throws {
        completeWorkoutFromPlan()

        for _ in 0..<2 {
            tapTab("ホーム")
            let conditionCard = app.buttons["conditionSummaryCard"]
            XCTAssertTrue(conditionCard.waitForExistence(timeout: 5))
            conditionCard.tap()
            XCTAssertTrue(app.navigationBars["コンディション"].waitForExistence(timeout: 5))
            app.navigationBars["コンディション"].buttons.firstMatch.tap()

            tapTab("記録")
            let bodyWeightLink = app.buttons["recordHubBodyWeightLink"]
            XCTAssertTrue(bodyWeightLink.waitForExistence(timeout: 5))
            bodyWeightLink.tap()
            XCTAssertTrue(app.navigationBars["体重"].waitForExistence(timeout: 5))
            app.navigationBars["体重"].buttons.firstMatch.tap()

            tapTab("履歴")
            let historyRow = app.descendants(matching: .any)["historyRow-胸の日"]
            for _ in 0..<3 where !historyRow.exists {
                app.swipeUp()
            }
            XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
            historyRow.tap()
            XCTAssertTrue(app.navigationBars["履歴詳細"].waitForExistence(timeout: 5))
            app.navigationBars["履歴詳細"].buttons.firstMatch.tap()
        }
    }

    func testExtendedSensorDashboardAndAnalysisSurfaces() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-sensor-ui-test-data",
            "--expand-home-details"
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

}
