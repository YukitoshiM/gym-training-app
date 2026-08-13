import XCTest
@testable import GymTrainingApp

final class UsageAnalyticsTests: XCTestCase {
    func testCoachResponseRatingPersistsAndExportsCoarseEvent() throws {
        let suiteName = "UsageAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = UsageAnalytics(defaults: defaults)
        let messageID = UUID()

        analytics.setCollectionEnabled(true)
        analytics.recordCoachResponseRating(
            messageID: messageID,
            rating: .helpful,
            coachType: "hypertrophy"
        )
        analytics.recordCoachResponseRating(
            messageID: messageID,
            rating: .helpful,
            coachType: "hypertrophy"
        )

        XCTAssertEqual(analytics.coachResponseRating(for: messageID), .helpful)
        let object = try JSONSerialization.jsonObject(with: analytics.exportData())
        let events = try XCTUnwrap(object as? [[String: Any]])
        XCTAssertEqual(events.filter { event in
            event["name"] as? String == UsageEventName.coachResponseHelpful.rawValue
                && event["dimension"] as? String == "hypertrophy"
        }.count, 1)

        analytics.deleteData()
        XCTAssertNil(analytics.coachResponseRating(for: messageID))
        let emptyObject = try JSONSerialization.jsonObject(with: analytics.exportData())
        XCTAssertEqual((emptyObject as? [[String: Any]])?.count, 0)
    }
}
