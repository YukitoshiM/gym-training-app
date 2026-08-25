import XCTest
@testable import GymTrainingApp

final class BodyMetricEstimateServiceTests: XCTestCase {
    func testOldActualValueCreatesClearlyMarkedEstimateWithoutChangingActual() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let actual = BodyMetricEntry(
            kind: .waist,
            value: 82,
            recordedAt: now.addingTimeInterval(-8 * 86_400)
        )

        let estimate = try XCTUnwrap(BodyMetricEstimateService.estimates(
            entries: [actual],
            profile: .default,
            now: now
        ).first(where: { $0.kind == .waist }))
        let approved = estimate.approvedEntry(at: now)

        XCTAssertEqual(actual.value, 82)
        XCTAssertNotEqual(actual.id, approved.id)
        XCTAssertEqual(approved.isEstimated, true)
        XCTAssertNotNil(approved.estimateLowerBound)
        XCTAssertNotNil(approved.estimateUpperBound)
    }

    func testRecentActualValueDoesNotCreateStaleEstimate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let actual = BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now.addingTimeInterval(-2 * 86_400))

        let estimates = BodyMetricEstimateService.estimates(entries: [actual], profile: .default, now: now)

        XCTAssertFalse(estimates.contains(where: { $0.kind == .bodyWeight }))
    }

    func testBodyFatEstimateRequiresSpecifiedSex() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weight = BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)
        var profile = UserProfile.default
        profile.heightCm = 175
        profile.birthYear = 1990
        profile.sex = .unspecified

        let estimates = BodyMetricEstimateService.estimates(entries: [weight], profile: profile, now: now)

        XCTAssertFalse(estimates.contains(where: { $0.kind == .bodyFatPercentage }))
    }

    func testBodyFatEstimateUsesLatestActualWeight() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = BodyMetricEntry(kind: .bodyWeight, value: 110, recordedAt: now.addingTimeInterval(-20 * 86_400))
        let latest = BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: now)
        var profile = UserProfile.default
        profile.heightCm = 175
        profile.birthYear = 1990
        profile.sex = .male

        let estimate = try XCTUnwrap(BodyMetricEstimateService.estimates(
            entries: [older, latest],
            profile: profile,
            now: now
        ).first(where: { $0.kind == .bodyFatPercentage }))

        XCTAssertLessThan(estimate.value, 30)
    }

    func testPhotoEstimateAutomaticallyCreatesEstimatedBodyFatEntry() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let references = [
            BodyPhotoReferenceEstimate(
                metric: "body_fat_percent",
                lowerBound: 14,
                upperBound: 20,
                unit: "%",
                confidence: "low",
                rationale: "写真条件で変動する参考範囲"
            )
        ]

        let entry = try XCTUnwrap(BodyMetricEstimateService.photoEstimates(
            from: references,
            existingEntries: [],
            at: date
        ).first)

        XCTAssertEqual(entry.kind, .bodyFatPercentage)
        XCTAssertEqual(entry.value, 17)
        XCTAssertEqual(entry.isEstimated, true)
        XCTAssertEqual(entry.estimateLowerBound, 14)
        XCTAssertEqual(entry.estimateUpperBound, 20)
    }

    func testPhotoEstimateDoesNotOverwriteSameDayEntry() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let actual = BodyMetricEntry(kind: .bodyFatPercentage, value: 18, recordedAt: date)
        let reference = BodyPhotoReferenceEstimate(
            metric: "body_fat_percent",
            lowerBound: 12,
            upperBound: 16,
            unit: "%",
            confidence: "low",
            rationale: "参考範囲"
        )

        let entries = BodyMetricEstimateService.photoEstimates(
            from: [reference],
            existingEntries: [actual],
            at: date
        )

        XCTAssertTrue(entries.isEmpty)
    }

    func testPhotoEstimateUsesLowerOfMeanAndMedianAcrossCandidates() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let references = [
            BodyPhotoReferenceEstimate(metric: "body_fat_percent", lowerBound: 10, upperBound: 14, unit: "%", confidence: "low", rationale: "a"),
            BodyPhotoReferenceEstimate(metric: "body_fat_percent", lowerBound: 12, upperBound: 16, unit: "%", confidence: "low", rationale: "b"),
            BodyPhotoReferenceEstimate(metric: "body_fat_percent", lowerBound: 28, upperBound: 32, unit: "%", confidence: "low", rationale: "c"),
        ]

        let entry = try XCTUnwrap(BodyMetricEstimateService.photoEstimates(
            from: references,
            existingEntries: [],
            at: date
        ).first)

        XCTAssertEqual(entry.value, 14)
    }
}
