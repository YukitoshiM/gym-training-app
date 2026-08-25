import XCTest
@testable import GymTrainingApp

final class InAppFeedbackTests: XCTestCase {
    func testReportContainsOnlyEnteredContentAndBasicAppContext() {
        let report = FeedbackReportBuilder.body(
            category: .bug,
            message: "保存後に画面が閉じません",
            appVersion: "0.1.0 (18)",
            operatingSystemVersion: "iOS 26.5"
        )

        XCTAssertTrue(report.contains("種類: 不具合"))
        XCTAssertTrue(report.contains("保存後に画面が閉じません"))
        XCTAssertTrue(report.contains("0.1.0 (18)"))
        XCTAssertTrue(report.contains("iOS 26.5"))
        XCTAssertFalse(report.contains("体重"))
        XCTAssertFalse(report.contains("APIキー"))
    }

    func testReportTrimsMessageWhitespace() {
        let report = FeedbackReportBuilder.body(
            category: .request,
            message: "  休憩タイマーを見やすくして  \n",
            appVersion: "1",
            operatingSystemVersion: "iOS"
        )

        XCTAssertTrue(report.contains("内容:\n休憩タイマーを見やすくして\n"))
    }
}
