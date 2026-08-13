import Foundation
import XCTest
@testable import GymTrainingApp

final class BodyPhotoSetTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testEntriesFromSameDayBecomeOneCaptureSet() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let entries = [
            BodyPhotoEntry(recordedAt: day, angle: .front, imageData: Data([1])),
            BodyPhotoEntry(recordedAt: day.addingTimeInterval(60), angle: .side, imageData: Data([2])),
            BodyPhotoEntry(recordedAt: nextDay, angle: .back, imageData: Data([3]))
        ]

        let sets = BodyPhotoSet.grouped(entries, calendar: calendar)

        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.last?.photoEntries.count, 2)
        XCTAssertEqual(sets.last?.angleEntries.map(\.angle), [.front, .side])
    }

    func testLatestPhotoWinsWhenLegacyDataHasDuplicateAngle() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8)))
        let older = BodyPhotoEntry(recordedAt: day, angle: .front, imageData: Data([1]))
        let latest = BodyPhotoEntry(recordedAt: day.addingTimeInterval(60), angle: .front, imageData: Data([2]))

        let set = try XCTUnwrap(BodyPhotoSet.grouped([older, latest], calendar: calendar).first)

        XCTAssertEqual(set.photoEntries.count, 2)
        XCTAssertEqual(set.angleEntries.count, 1)
        XCTAssertEqual(set.angleEntries.first?.id, latest.id)
    }

    func testAddingUnanalyzedPhotoMarksSetForReanalysis() throws {
        let comment = BodyPhotoAIComment(
            summary: "分析済み",
            abdomen: "腹部",
            waist: "ウエスト",
            posture: "姿勢",
            score: nil,
            confidence: "medium"
        )
        let analyzed = BodyPhotoEntry(angle: .front, imageData: Data([1]), aiComment: comment)
        let addedLater = BodyPhotoEntry(angle: .side, imageData: Data([2]))

        let set = try XCTUnwrap(BodyPhotoSet.grouped([analyzed, addedLater]).first)
        XCTAssertTrue(set.needsAnalysis)

        let reanalyzedEntries = set.entries.map { entry in
            var updated = entry
            updated.aiComment = comment
            return updated
        }
        let reanalyzedSet = try XCTUnwrap(BodyPhotoSet.grouped(reanalyzedEntries).first)
        XCTAssertFalse(reanalyzedSet.needsAnalysis)
    }

    @MainActor
    func testAnalysisContextIncludesPreviousMetricsAndOnlyComparableDeltas() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let storage = TestAppDataRepository()
        storage.bodyMetricEntries = [
            BodyMetricEntry(kind: .bodyWeight, value: 70.4, recordedAt: yesterday),
            BodyMetricEntry(kind: .waist, value: 82.1, recordedAt: yesterday),
            BodyMetricEntry(kind: .bodyWeight, value: 70.0, recordedAt: today),
            BodyMetricEntry(kind: .bodyFatPercentage, value: 15.2, recordedAt: today)
        ]
        storage.bodyPhotoEntries = [
            BodyPhotoEntry(recordedAt: yesterday, angle: .front, imageData: Data([1]))
        ]
        let store = AppStore(storage: storage)

        let context = bodyPhotoAnalysisContext(appStore: store, date: today)

        XCTAssertEqual(context.previousMetrics?.weightKG, 70.4)
        XCTAssertEqual(context.previousMetrics?.waistCM, 82.1)
        XCTAssertNil(context.previousMetrics?.bodyFatPercentage)
        XCTAssertEqual(context.metricDeltas?.weightKG ?? 0, -0.4, accuracy: 0.0001)
        XCTAssertNil(context.metricDeltas?.waistCM)
        XCTAssertNil(context.metricDeltas?.bodyFatPercentage)
    }

    func testAnalysisContextEncodingOmitsEmptyComparisonMetrics() throws {
        let context = BodyPhotoAnalysisContext(
            profileGoal: "健康維持",
            outcomeStyle: "",
            focusAreas: [],
            experienceLevel: "初心者",
            currentMetrics: [],
            previousCaptureDate: nil,
            previousSummary: nil,
            previousMetrics: BodyPhotoAnalysisMetrics(),
            metricDeltas: BodyPhotoAnalysisMetrics()
        )

        let data = try JSONEncoder().encode(context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["previous_metrics"])
        XCTAssertNil(json["metric_deltas"])
    }
}
