import XCTest
@testable import GymTrainingApp

final class UsageAnalyticsTests: XCTestCase {
    func testCreditEventsExportOnlyFixedNameAndDimension() throws {
        let suiteName = "UsageAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = UsageAnalytics(defaults: defaults)
        analytics.setCollectionEnabled(true)

        analytics.record(.aiCreditInsufficientShown, dimension: "body_photo")
        analytics.record(.creditPurchaseCompleted)

        var events: [[String: Any]] = []
        for _ in 0..<100 {
            events = (try JSONSerialization.jsonObject(with: analytics.exportData()) as? [[String: Any]]) ?? []
            if events.contains(where: { $0["name"] as? String == "credit_purchase_completed" }) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let insufficient = try XCTUnwrap(events.first { $0["name"] as? String == "ai_credit_insufficient_shown" })
        XCTAssertEqual(insufficient["dimension"] as? String, "body_photo")
        XCTAssertNil(insufficient["properties"] as? [String: Any])
        let purchase = try XCTUnwrap(events.first { $0["name"] as? String == "credit_purchase_completed" })
        XCTAssertNil(purchase["dimension"])
        XCTAssertNil(purchase["properties"] as? [String: Any])
    }

    func testLegacyDeviceOnlyOptInDoesNotAuthorizeServerUpload() throws {
        let suiteName = "UsageAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "bodymode.usageAnalytics.enabled")

        let analytics = UsageAnalytics(defaults: defaults)

        XCTAssertFalse(analytics.isCollectionEnabled)
    }

    func testCollectionPreferenceCanBeChangedWithoutEventQueueSynchronization() throws {
        let suiteName = "UsageAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = UsageAnalytics(defaults: defaults)

        analytics.setCollectionEnabled(true)
        XCTAssertTrue(analytics.isCollectionEnabled)

        analytics.setCollectionEnabled(false)
        XCTAssertFalse(analytics.isCollectionEnabled)
    }

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

    func testConcurrentEventPersistenceDoesNotBlockRatingReads() throws {
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

        for _ in 0..<100 {
            analytics.record(.tabSelected, dimension: "ai")
            XCTAssertEqual(analytics.coachResponseRating(for: messageID), .helpful)
        }

        XCTAssertEqual(
            analytics.coachResponseRatings(for: [messageID])[messageID],
            .helpful
        )

        analytics.deleteData()
        XCTAssertEqual(
            (try JSONSerialization.jsonObject(with: analytics.exportData()) as? [[String: Any]])?.count,
            0
        )
        XCTAssertNil(analytics.coachResponseRating(for: messageID))
    }

    func testDailyActionPropertiesContainOnlyCoarseEnumeratedContext() throws {
        let suiteName = "UsageAnalyticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = UsageAnalytics(defaults: defaults)
        analytics.setCollectionEnabled(true)
        let recommendation = DailyRecommendation(
            date: Date(),
            generatedAt: Date(),
            readiness: DailyReadiness(
                level: .normal,
                confidence: 0.7,
                contributingFactors: ["sensitive detail must not be exported"],
                missingData: ["sleep value"]
            ),
            actions: [
                DailyAction(
                    category: .workout,
                    title: "Private workout title",
                    completionRule: .manuallyConfirmed,
                    destination: .none,
                    priority: 0,
                    rationale: "Private rationale"
                )
            ],
            summary: "Private summary",
            contextVersion: 1,
            source: .localRule
        )
        let action = try XCTUnwrap(recommendation.activeActions.first)

        analytics.record(
            .dailyActionImpression,
            dimension: action.category.rawValue,
            properties: .dailyAction(
                profile: .default,
                recommendation: recommendation,
                action: action
            )
        )

        var exported = ""
        for _ in 0..<100 {
            exported = String(decoding: analytics.exportData(), as: UTF8.self)
            if exported.contains("actionCategory") { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(exported.contains("actionCategory"))
        XCTAssertTrue(exported.contains("workout"))
        XCTAssertFalse(exported.contains("Private workout title"))
        XCTAssertFalse(exported.contains("Private rationale"))
        XCTAssertFalse(exported.contains("sensitive detail"))
        XCTAssertFalse(exported.contains("sleep value"))
    }

    func testLegacyUsageEventWithoutPropertiesStillDecodes() throws {
        let eventID = UUID()
        let payload = """
        [{
          "id": "\(eventID.uuidString)",
          "timestamp": "2026-08-16T00:00:00Z",
          "name": "app_opened",
          "dimension": "home",
          "appVersion": "22",
          "locale": "ja_JP"
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([UsageEvent].self, from: Data(payload.utf8))

        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertNil(events.first?.properties)
    }
}
