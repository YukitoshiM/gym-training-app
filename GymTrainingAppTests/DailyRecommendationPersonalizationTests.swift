import XCTest
@testable import GymTrainingApp

final class DailyRecommendationPersonalizationTests: XCTestCase {
    func testPersonalizationCanBeDisabledAndResetWithoutDeletingRecords() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyRecommendationPersonalizationTests"))
        defaults.removePersistentDomain(forName: "DailyRecommendationPersonalizationTests")
        let old = recommendation(date: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            DailyRecommendationPersonalizationStore.history(from: [old], defaults: defaults).count,
            1
        )
        DailyRecommendationPersonalizationStore.setEnabled(false, defaults: defaults)
        XCTAssertTrue(DailyRecommendationPersonalizationStore.history(from: [old], defaults: defaults).isEmpty)

        DailyRecommendationPersonalizationStore.setEnabled(true, defaults: defaults)
        DailyRecommendationPersonalizationStore.reset(
            defaults: defaults,
            at: Date(timeIntervalSince1970: 200)
        )
        XCTAssertTrue(DailyRecommendationPersonalizationStore.history(from: [old], defaults: defaults).isEmpty)
        XCTAssertEqual([old].count, 1)
    }

    func testNotificationOptimizationKeepsTrialWeekThenSuppressesLowResponse() {
        XCTAssertTrue(
            DailyRecommendationNotificationManager.shouldScheduleEvening(
                scheduledDayCount: 6,
                openedDayCount: 0
            )
        )
        XCTAssertFalse(
            DailyRecommendationNotificationManager.shouldScheduleEvening(
                scheduledDayCount: 10,
                openedDayCount: 0
            )
        )
        XCTAssertTrue(
            DailyRecommendationNotificationManager.shouldScheduleEvening(
                scheduledDayCount: 10,
                openedDayCount: 2
            )
        )
    }

    func testNotificationMeasurementRecordsOnlySuccessfulSchedulesAndKeepsSlotsSeparate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyRecommendationNotificationMeasurementTests"))
        defaults.removePersistentDomain(forName: "DailyRecommendationNotificationMeasurementTests")
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        DailyRecommendationNotificationManager.recordSchedulingResult(
            identifier: DailyRecommendationNotificationManager.morningIdentifier,
            at: day,
            error: nil,
            defaults: defaults
        )
        DailyRecommendationNotificationManager.recordSchedulingResult(
            identifier: DailyRecommendationNotificationManager.eveningIdentifier,
            at: day,
            error: NSError(domain: "test", code: 1),
            defaults: defaults
        )
        DailyRecommendationNotificationManager.recordOpen(
            identifier: DailyRecommendationNotificationManager.morningIdentifier,
            at: day,
            defaults: defaults
        )
        DailyRecommendationNotificationManager.recordOpen(
            identifier: DailyRecommendationNotificationManager.eveningIdentifier,
            at: day,
            defaults: defaults
        )

        XCTAssertEqual(
            DailyRecommendationNotificationManager.metrics(
                for: DailyRecommendationNotificationManager.morningIdentifier,
                defaults: defaults
            ),
            .init(scheduledCount: 1, openedCount: 1)
        )
        XCTAssertEqual(
            DailyRecommendationNotificationManager.metrics(
                for: DailyRecommendationNotificationManager.eveningIdentifier,
                defaults: defaults
            ),
            .init(scheduledCount: 0, openedCount: 0)
        )
    }

    func testNotificationMeasurementDeduplicatesSameIdentifierAndDate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyRecommendationNotificationDeduplicationTests"))
        defaults.removePersistentDomain(forName: "DailyRecommendationNotificationDeduplicationTests")
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        for _ in 0..<3 {
            DailyRecommendationNotificationManager.recordSchedulingResult(
                identifier: DailyRecommendationNotificationManager.eveningIdentifier,
                at: day,
                error: nil,
                defaults: defaults
            )
            DailyRecommendationNotificationManager.recordOpen(
                identifier: DailyRecommendationNotificationManager.eveningIdentifier,
                at: day,
                defaults: defaults
            )
        }

        XCTAssertEqual(
            DailyRecommendationNotificationManager.metrics(
                for: DailyRecommendationNotificationManager.eveningIdentifier,
                defaults: defaults
            ),
            .init(scheduledCount: 1, openedCount: 1)
        )
    }

    func testNotificationMeasurementMigratesLegacyHistoryWithoutGuessingEveningResponses() throws {
        let suite = "DailyRecommendationNotificationLegacyMigrationTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["2026-08-10", "2026-08-11"], forKey: "bodymode.omakase.notificationScheduledDays")
        defaults.set(["2026-08-10"], forKey: "bodymode.omakase.notificationOpenedDays")

        XCTAssertEqual(
            DailyRecommendationNotificationManager.metrics(
                for: DailyRecommendationNotificationManager.morningIdentifier,
                defaults: defaults
            ),
            .init(scheduledCount: 2, openedCount: 1)
        )
        XCTAssertEqual(
            DailyRecommendationNotificationManager.metrics(
                for: DailyRecommendationNotificationManager.eveningIdentifier,
                defaults: defaults
            ),
            .init(scheduledCount: 0, openedCount: 0)
        )
    }

    func testEvaluationSeparatesCompletionAdoptionAndAIChangeRates() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyRecommendationEvaluationTests"))
        defaults.removePersistentDomain(forName: "DailyRecommendationEvaluationTests")
        var first = recommendation(date: Date(timeIntervalSince1970: 100))
        first.actions.append(
            DailyAction(
                category: .steps,
                title: "歩数",
                completionRule: .stepsAtLeast(8_000),
                destination: .steps,
                status: .inProgress,
                adoptedAt: Date(timeIntervalSince1970: 105),
                priority: 1,
                rationale: "test"
            )
        )
        let revision = RecommendationRevision(
            date: first.date,
            timestamp: Date(timeIntervalSince1970: 110),
            previousActions: first.actions,
            newActions: first.actions,
            reason: "回復を反映",
            source: .ai
        )
        let duplicateSameDayRevision = RecommendationRevision(
            date: first.date,
            timestamp: Date(timeIntervalSince1970: 120),
            previousActions: first.actions,
            newActions: first.actions,
            reason: "同日の再補正",
            source: .ai
        )

        let evaluation = DailyRecommendationPersonalizationStore.evaluation(
            recommendations: [first],
            revisions: [revision, duplicateSameDayRevision],
            defaults: defaults
        )

        XCTAssertEqual(evaluation.completionRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(evaluation.adoptionRate, 1, accuracy: 0.001)
        XCTAssertEqual(evaluation.aiChangeRate, 1, accuracy: 0.001)
    }

    func testInProgressWithoutExplicitAdoptionDoesNotCountAsAdopted() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyRecommendationExplicitAdoptionTests"))
        defaults.removePersistentDomain(forName: "DailyRecommendationExplicitAdoptionTests")
        var item = recommendation(date: Date(timeIntervalSince1970: 100))
        item.actions[0].status = .inProgress
        item.actions[0].adoptedAt = nil

        let evaluation = DailyRecommendationPersonalizationStore.evaluation(
            recommendations: [item],
            revisions: [],
            defaults: defaults
        )

        XCTAssertEqual(evaluation.adoptionRate, 0, accuracy: 0.001)
    }

    private func recommendation(date: Date) -> DailyRecommendation {
        DailyRecommendation(
            date: date,
            generatedAt: date,
            readiness: DailyReadiness(level: .normal, confidence: 0.5, contributingFactors: [], missingData: []),
            actions: [
                DailyAction(
                    category: .protein,
                    title: "たんぱく質",
                    completionRule: .proteinAtLeast(100),
                    destination: .meal,
                    status: .completed,
                    priority: 0,
                    rationale: "test"
                )
            ],
            summary: "test",
            contextVersion: 1,
            source: .localRule
        )
    }
}
