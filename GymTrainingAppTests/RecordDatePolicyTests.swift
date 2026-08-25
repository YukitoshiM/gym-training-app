import XCTest
@testable import GymTrainingApp

final class RecordDatePolicyTests: XCTestCase {
    func testAllowedRangeIncludesTodayAndPreviousSevenDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 15, hour: 12
        )))

        let range = RecordDatePolicy.allowedRange(now: now, calendar: calendar)

        XCTAssertEqual(range.lowerBound, calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)))
        XCTAssertEqual(range.upperBound, now)
    }

    func testClampedRejectsOlderAndFutureDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 15, hour: 12
        )))
        let range = RecordDatePolicy.allowedRange(now: now, calendar: calendar)

        XCTAssertEqual(RecordDatePolicy.clamped(.distantPast, now: now, calendar: calendar), range.lowerBound)
        XCTAssertEqual(RecordDatePolicy.clamped(.distantFuture, now: now, calendar: calendar), range.upperBound)
    }

    func testNormalizedDayDropsTimeAndClampsToRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 15, hour: 12, minute: 34, second: 56
        )))

        let withTime = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 22, minute: 10, second: 8
        )))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13)))
        XCTAssertEqual(RecordDatePolicy.normalizedDay(withTime, now: now, calendar: calendar), expected)

        let beforeRange = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let expectedLower = RecordDatePolicy.allowedRange(now: now, calendar: calendar).lowerBound
        XCTAssertEqual(RecordDatePolicy.normalizedDay(beforeRange, now: now, calendar: calendar), expectedLower)
    }

    func testShiftingWorkoutDatePreservesTimeAndDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 18, minute: 30)))
        let end = start.addingTimeInterval(3_600)
        let destination = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let session = WorkoutSession(title: "Test", sourcePlanID: nil, startedAt: start, endedAt: end, exercises: [])

        let shifted = RecordDatePolicy.shifting(session, to: destination, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: shifted.startedAt), 12)
        XCTAssertEqual(calendar.component(.hour, from: shifted.startedAt), 18)
        XCTAssertEqual(shifted.endedAt?.timeIntervalSince(shifted.startedAt), 3_600)
    }
}
