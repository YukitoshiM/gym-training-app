import XCTest

@MainActor
final class AppStoreReviewScreenshotUITests: XCTestCase {
    func testAICreditStoreReviewScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-ui-test-data",
            "--seed-theme-royal-cobalt",
            "--force-light-appearance",
            "--show-ai-credit-store-review",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Add Credits"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["aiCreditProduct-50"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["aiCreditProduct-150"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["aiCreditProduct-500"].waitForExistence(timeout: 5))

        let output = URL(fileURLWithPath: "/tmp/bodymode-iap-review.png")
        try app.screenshot().pngRepresentation.write(to: output, options: .atomic)

        let attachment = XCTAttachment(contentsOfFile: output)
        attachment.name = "bodymode-ai-credit-store-review"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
