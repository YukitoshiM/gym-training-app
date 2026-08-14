import XCTest

@MainActor
final class SettingsAndAccessibilityUITests: GymTrainingAppUITestCase {
    func testTrainerAvatarSelectionPersistsAndAppearsOnHome() throws {
        openSettings()

        let maya = scrollToHittable(app.buttons["coachPersona-maya"], maxSwipes: 4)
        XCTAssertTrue(maya.isHittable)
        maya.tap()
        app.buttons["saveProfileSettingsButton"].tap()

        XCTAssertTrue(app.staticTexts["Mayaからの提案"].waitForExistence(timeout: 5))

        tapTab("AI")
        XCTAssertTrue(app.staticTexts["担当 Maya"].waitForExistence(timeout: 5))
        app.buttons["aiHubTrainerLink"].tap()
        XCTAssertTrue(app.navigationBars["Maya"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["aiChatCoachHeader"].waitForExistence(timeout: 3)
        )
        let mayaChatScreenshot = XCTAttachment(screenshot: app.screenshot())
        mayaChatScreenshot.name = "Selected Maya coach in AI chat"
        mayaChatScreenshot.lifetime = .keepAlways
        add(mayaChatScreenshot)

        openSettings()
        let persistedMaya = scrollToHittable(app.buttons["coachPersona-maya"], maxSwipes: 4)
        XCTAssertTrue(persistedMaya.isSelected)
    }

    func testRetiredBundledAIURLMigratesOnLaunch() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-retired-ai-settings"
        ]
        app.launch()

        openSettings()
        let baseURLField = scrollToHittable(app.textFields["aiBaseURLField"], maxSwipes: 12)
        XCTAssertTrue(baseURLField.isHittable)
        XCTAssertEqual(
            baseURLField.value as? String,
            "https://yukitoshinomac-mini.taild6630a.ts.net"
        )
        XCTAssertTrue(scrollToHittable(app.buttons["shareDiagnosticsButton"], maxSwipes: 15).isHittable)
    }

    func testAIDataSharingCanBeSelectedByCategory() throws {
        tapTab("ホーム")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))

        let disclosure = app.buttons["AIへ送るデータ"]
        for _ in 0..<5 where !disclosure.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        disclosure.tap()

        XCTAssertTrue(scrollToHittable(app.switches["身体KPI"]).isHittable)
        XCTAssertTrue(scrollToHittable(app.switches["睡眠・回復"]).isHittable)
        XCTAssertTrue(scrollToHittable(app.switches["ジム訪問"]).isHittable)
        XCTAssertTrue(scrollToHittable(app.switches["心拍・モーション"]).isHittable)
    }

    func testThemeAndAppearanceSelectionPersists() throws {
        openSettings()

        let blackChampagne = scrollToHittable(app.buttons["themeOption-blackChampagne"])
        XCTAssertTrue(blackChampagne.isHittable)
        blackChampagne.tap()

        let appearancePicker = scrollToHittable(app.segmentedControls["appearanceModePicker"])
        XCTAssertTrue(appearancePicker.isHittable)
        appearancePicker.buttons["ダーク"].tap()
        app.buttons["saveProfileSettingsButton"].tap()

        openSettings()
        let persistedBlackChampagne = scrollToHittable(app.buttons["themeOption-blackChampagne"])
        XCTAssertEqual(persistedBlackChampagne.value as? String, "選択中")
        let persistedDarkPicker = scrollToHittable(app.segmentedControls["appearanceModePicker"])
        XCTAssertTrue(persistedDarkPicker.buttons["ダーク"].isSelected)

        let royalCobalt = scrollToHittable(app.buttons["themeOption-royalCobalt"])
        XCTAssertTrue(royalCobalt.isHittable)
        royalCobalt.tap()
        XCTAssertTrue(waitForValue("選択中", of: royalCobalt))
        persistedDarkPicker.buttons["ライト"].tap()
        XCTAssertTrue(persistedDarkPicker.buttons["ライト"].isSelected)
        app.buttons["saveProfileSettingsButton"].tap()

        openSettings()
        let persistedRoyalCobalt = scrollToHittable(app.buttons["themeOption-royalCobalt"])
        XCTAssertEqual(persistedRoyalCobalt.value as? String, "選択中")
        let persistedLightPicker = scrollToHittable(app.segmentedControls["appearanceModePicker"])
        XCTAssertTrue(persistedLightPicker.buttons["ライト"].isSelected)
    }

    func testLegalPrivacyAndSupportDocumentsAreAccessible() throws {
        openSettings()

        let termsLink = scrollToHittable(app.buttons["termsOfUseLink"])
        XCTAssertTrue(termsLink.isHittable)
        termsLink.tap()
        XCTAssertTrue(app.navigationBars["利用規約"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["termsOfUseView"].exists)
        app.navigationBars["利用規約"].buttons.firstMatch.tap()

        let privacyLink = scrollToHittable(app.buttons["privacyPolicyLink"])
        XCTAssertTrue(privacyLink.isHittable)
        privacyLink.tap()
        XCTAssertTrue(app.navigationBars["プライバシーポリシー"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacyPolicyView"].exists)
        app.navigationBars["プライバシーポリシー"].buttons.firstMatch.tap()

        let noticeLink = scrollToHittable(app.buttons["healthAINoticeLink"])
        XCTAssertTrue(noticeLink.isHittable)
        noticeLink.tap()
        XCTAssertTrue(app.navigationBars["健康・AIに関する注意"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["healthAINoticeView"].exists)
        app.navigationBars["健康・AIに関する注意"].buttons.firstMatch.tap()

        let supportLink = scrollToHittable(app.buttons["supportInformationLink"])
        XCTAssertTrue(supportLink.isHittable)
        supportLink.tap()
        XCTAssertTrue(app.navigationBars["サポート"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["supportInformationView"].exists)
    }

    func testLegalConsentGateCanBeReviewedAndAccepted() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--force-legal-consent-ui-test"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["legalConsentView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["acceptLegalConsentButton"].exists)
        XCTAssertFalse(app.buttons["acceptLegalConsentButton"].isEnabled)

        app.buttons["consentTermsLink"].tap()
        XCTAssertTrue(app.navigationBars["利用規約"].waitForExistence(timeout: 5))
        app.navigationBars["利用規約"].buttons.firstMatch.tap()

        app.switches["legalConsentToggle"].tap()
        XCTAssertTrue(app.buttons["acceptLegalConsentButton"].isEnabled)
        app.buttons["acceptLegalConsentButton"].tap()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
    }

    func testAdvertisingDisclosureAndReportAreAccessible() throws {
        openSettings()

        let informationLink = scrollToHittable(app.buttons["advertisingInformationLink"])
        XCTAssertTrue(informationLink.isHittable)
        informationLink.tap()
        XCTAssertTrue(app.navigationBars["広告とデータ利用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["advertisingInformationView"].exists)
        app.navigationBars["広告とデータ利用"].buttons.firstMatch.tap()

        let reportLink = scrollToHittable(app.buttons["reportAdLink"])
        XCTAssertTrue(reportLink.isHittable)
        reportLink.tap()
        XCTAssertTrue(app.navigationBars["広告を報告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["adReportView"].exists)
        XCTAssertTrue(app.buttons["submitAdReportButton"].exists)
    }

    func testGoogleDemoBannerLoadsWhenNetworkIntegrationTestsAreEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_AD_NETWORK_TESTS"] == "1",
            "Google ad network integration is opt-in"
        )

        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--enable-test-ads-ui-test"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Test mode"].waitForExistence(timeout: 30),
            "Google demo banner did not finish loading"
        )
        XCTAssertTrue(app.descendants(matching: .any)["persistentBannerAd"].exists)

        let aiTab = app.buttons["rootTab-AI"].exists
            ? app.buttons["rootTab-AI"]
            : app.tabBars.buttons["AI"]
        XCTAssertTrue(aiTab.isHittable)
        aiTab.tap()

        XCTAssertTrue(
            app.staticTexts["Test mode"].waitForExistence(timeout: 5),
            "Banner disappeared after changing tabs"
        )
        XCTAssertTrue(app.descendants(matching: .any)["persistentBannerAd"].exists)
    }

    func testBannerRemainsVisibleAcrossPrimaryTabs() {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--show-banner-placeholder-ui-test"
        ]
        app.launch()

        assertPersistentBanner()

        for title in ["AI", "計画", "記録", "履歴"] {
            let customTab = app.buttons["rootTab-\(title)"]
            let tab = customTab.exists ? customTab : app.tabBars.buttons[title]
            XCTAssertTrue(tab.isHittable, "\(title) tab is not hittable")
            tab.tap()
            assertPersistentBanner()

            if title == "AI" {
                let trainerLink = app.buttons["aiHubTrainerLink"]
                XCTAssertTrue(trainerLink.waitForExistence(timeout: 5))
                trainerLink.tap()
                assertPersistentBanner()
            }
        }
    }

    private func assertPersistentBanner() {
        XCTAssertTrue(
            app.staticTexts["固定テスト広告"].waitForExistence(timeout: 5),
            "Persistent banner is missing"
        )
        XCTAssertTrue(app.descendants(matching: .any)["persistentBannerAd"].exists)
    }

    func testUsageAnalyticsIsOptInAndLocallyManageable() throws {
        openSettings()

        let toggle = scrollToHittable(app.switches["usageAnalyticsToggle"])
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let settledToggle = scrollToHittable(app.switches["usageAnalyticsToggle"])
        XCTAssertTrue(settledToggle.isHittable)
        settledToggle.tap()
        XCTAssertTrue(waitForValue("1", of: settledToggle))

        XCTAssertTrue(scrollToHittable(app.buttons["exportUsageAnalyticsButton"]).isHittable)
        XCTAssertTrue(scrollToHittable(app.buttons["deleteUsageAnalyticsButton"]).isHittable)
        XCTAssertTrue(scrollToHittable(app.buttons["deleteDiagnosticsButton"]).isHittable)
    }

    func testPrimaryNavigationAtLargestAccessibilityTextSize() throws {
        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rootTab-AI"].exists)
        XCTAssertTrue(app.buttons["rootTab-計画"].exists)
        XCTAssertTrue(app.buttons["rootTab-記録"].exists)
        XCTAssertTrue(app.buttons["rootTab-履歴"].exists)
        app.buttons["rootTab-記録"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dailyRecordChecklistCard"].waitForExistence(timeout: 5))
    }

    func testCoreScreensPassAutomatedAccessibilityAudit() throws {
        let auditTypes: XCUIAccessibilityAuditType = [
            .sufficientElementDescription,
            .hitRegion,
            .textClipped,
            .trait
        ]

        tapTab("ホーム")
        try app.performAccessibilityAudit(for: auditTypes)

        tapTab("記録")
        try app.performAccessibilityAudit(for: auditTypes)

        tapTab("履歴")
        try app.performAccessibilityAudit(for: auditTypes)

        app.terminate()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-alpha-ui-test-plan",
            "--seed-theme-black-champagne",
            "--force-dark-appearance"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: auditTypes)
    }

    private func waitForValue(_ expectedValue: String, of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

}
