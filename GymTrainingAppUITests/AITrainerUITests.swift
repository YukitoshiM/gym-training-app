import XCTest

@MainActor
final class AITrainerUITests: GymTrainingAppUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        app.terminate()
        app.launchArguments.append("--stub-ai-trainer")
        app.launch()
    }

    func testAIHubProvidesOneTapAccessToPrimaryAIFeatures() {
        tapTab("AI")

        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["aiHubTrainerLink"].exists)
        XCTAssertTrue(app.buttons["aiHubMealPhotoLink"].exists)
        XCTAssertTrue(app.buttons["aiHubBodyPhotoLink"].exists)
        XCTAssertTrue(app.buttons["aiHubReportLink"].exists)
        XCTAssertTrue(app.buttons["aiHubPlanCoachButton"].exists)

        let hubScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hubScreenshot.name = "AI hub"
        hubScreenshot.lifetime = .keepAlways
        add(hubScreenshot)

        app.buttons["aiHubMealPhotoLink"].tap()
        XCTAssertTrue(app.navigationBars["食事を記録"].waitForExistence(timeout: 5))
        app.navigationBars["食事を記録"].buttons["キャンセル"].tap()
        XCTAssertTrue(app.navigationBars["食事"].waitForExistence(timeout: 5))
        app.navigationBars["食事"].buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 5))
        app.buttons["aiHubBodyPhotoLink"].tap()
        XCTAssertTrue(app.navigationBars["撮影セットを追加"].waitForExistence(timeout: 5))
        app.navigationBars["撮影セットを追加"].buttons["キャンセル"].tap()
        XCTAssertTrue(app.navigationBars["体型写真"].waitForExistence(timeout: 5))
    }

    func testMonthlyReviewRequiresConfirmationBeforeSaving() {
        app.terminate()
        app.launchArguments.append("--stub-monthly-ai")
        app.launch()
        tapTab("AI")

        let reportLink = scrollToHittable(app.buttons["aiHubReportLink"])
        XCTAssertTrue(reportLink.isHittable)
        reportLink.tap()

        let generate = app.buttons["generateMonthlyAIReviewButton"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        XCTAssertTrue(app.navigationBars["月次レビューを確認"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["保存した月次レビュー"].exists)
        app.buttons["saveMonthlyAIReviewButton"].tap()

        let savedSection = scrollToHittable(app.staticTexts["保存した月次レビュー"])
        XCTAssertTrue(savedSection.waitForExistence(timeout: 5))
        let review = scrollToHittable(
            app.staticTexts["継続できたトレーニングを軸に、回復とのバランスを確認できました。"]
        )
        XCTAssertTrue(review.exists)
    }

    func testWeeklyReportSeparatesConclusionEvidenceAndActions() {
        app.terminate()
        app.launchArguments.append("--seed-structured-weekly-report")
        app.launch()
        tapTab("AI")

        let reportLink = scrollToHittable(app.buttons["aiHubReportLink"])
        XCTAssertTrue(reportLink.isHittable)
        reportLink.tap()

        XCTAssertTrue(app.navigationBars["Noorのレポート"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(app.staticTexts["今週の結論"]).exists)
        XCTAssertTrue(scrollToHittable(app.staticTexts["良かった点"]).exists)
        XCTAssertTrue(scrollToHittable(app.staticTexts["課題"]).exists)
        XCTAssertTrue(scrollToHittable(app.staticTexts["判断の根拠"]).exists)
        XCTAssertTrue(scrollToHittable(app.staticTexts["次の行動"]).exists)
        XCTAssertTrue(scrollToHittable(app.staticTexts["睡眠を3日記録する"]).exists)
    }

    func testAIPlanCreationCanBeReviewedAndSaved() {
        tapTab("AI")

        let planButton = app.buttons["aiHubPlanCoachButton"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        XCTAssertTrue(app.navigationBars["Noorと計画作成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["aiPlanCoachIdentity"].exists)
        let generateButton = app.buttons["generateAIPlanButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        let applyButton = app.buttons["applyAIPlanButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 8))
        let proposalScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proposalScreenshot.name = "AI plan proposal"
        proposalScreenshot.lifetime = .keepAlways
        add(proposalScreenshot)
        applyButton.tap()

        XCTAssertTrue(app.navigationBars["AI 全身バランス"].waitForExistence(timeout: 5))
        let saveButton = app.buttons["savePlanPinnedButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        tapTab("計画")
        XCTAssertTrue(app.staticTexts["AI 全身バランス"].waitForExistence(timeout: 5))
    }

    func testChatReplyAndExplicitMemoryApproval() {
        tapTab("AI")
        let chatLink = app.descendants(matching: .any)["aiHubTrainerLink"]
        XCTAssertTrue(chatLink.waitForExistence(timeout: 5))
        chatLink.tap()

        let contextButton = app.buttons["coachContextCoverageButton"]
        XCTAssertTrue(contextButton.waitForExistence(timeout: 5))
        contextButton.tap()
        XCTAssertTrue(app.navigationBars["Noorの参照情報"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activeCoachIdentity"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["coachContextCoverageRow-profile"].exists)
        app.buttons["完了"].tap()

        let field = app.descendants(matching: .any)["aiTrainerMessageField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Can I increase the weight next time?")
        let sendButton = app.buttons["sendAITrainerMessageButton"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: sendButton)
        waitForExpectations(timeout: 5)
        sendButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["aiTrainerReply"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Noor"].exists)
        XCTAssertTrue(app.navigationBars["記憶を確認"].waitForExistence(timeout: 5))

        let candidate = app.buttons["memoryCandidateToggle-0"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        let approve = app.buttons["approveMemoryCandidatesButton"]
        XCTAssertTrue(approve.isEnabled)
        approve.tap()

        XCTAssertTrue(app.staticTexts["判断"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["次にやること"].exists)
        let evidence = scrollToHittable(app.staticTexts["科学的根拠 1件"])
        XCTAssertTrue(evidence.isHittable)
        evidence.tap()
        let citation = scrollToHittable(
            app.staticTexts["Resistance training volume and muscle hypertrophy"]
        )
        XCTAssertTrue(citation.isHittable)
        let helpfulButton = app.buttons["役に立った"]
        XCTAssertTrue(helpfulButton.waitForExistence(timeout: 5))
        helpfulButton.tap()
        XCTAssertTrue(helpfulButton.isSelected)
        let readabilityScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        readabilityScreenshot.name = "AI trainer formatted reply"
        readabilityScreenshot.lifetime = .keepAlways
        add(readabilityScreenshot)

        let reportBackButton = app.navigationBars.buttons["AI"]
        XCTAssertTrue(reportBackButton.waitForExistence(timeout: 5))
        reportBackButton.tap()

        let memoryLink = app.descendants(matching: .any)["aiHubMemoryLink"]
        XCTAssertTrue(memoryLink.waitForExistence(timeout: 5))
        memoryLink.tap()

        XCTAssertTrue(app.descendants(matching: .any)["coachMemoryRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["重量は小刻みに上げたい"].exists)
    }
}
