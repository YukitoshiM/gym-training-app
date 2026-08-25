import XCTest
@testable import GymTrainingApp

@MainActor
final class ScheduledReportServiceTests: XCTestCase {
    func testAutomaticAICreditUseIsOffByDefault() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        ReportScheduleStore.registerDefaults(defaults)

        XCTAssertFalse(defaults.bool(forKey: ReportScheduleStore.automaticAICreditUseKey))
    }

    func testWeeklyScheduleBecomesDueOnlyAfterTimeAndOncePerDay() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ReportScheduleStore.weeklyEnabledKey)
        defaults.set(2, forKey: ReportScheduleStore.weeklyWeekdayKey)
        defaults.set(20, forKey: ReportScheduleStore.hourKey)
        defaults.set(0, forKey: ReportScheduleStore.minuteKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 19, minute: 59)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 20, minute: 1)))

        XCTAssertFalse(ScheduledReportService.isWeeklyDue(now: before, defaults: defaults, calendar: calendar))
        XCTAssertTrue(ScheduledReportService.isWeeklyDue(now: after, defaults: defaults, calendar: calendar))
        defaults.set(after, forKey: ReportScheduleStore.lastWeeklyKey)
        XCTAssertFalse(ScheduledReportService.isWeeklyDue(now: after, defaults: defaults, calendar: calendar))
    }

    func testMonthlyScheduleUsesConfiguredDay() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ReportScheduleStore.monthlyEnabledKey)
        defaults.set(15, forKey: ReportScheduleStore.monthlyDayKey)
        defaults.set(8, forKey: ReportScheduleStore.hourKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 9)))

        XCTAssertTrue(ScheduledReportService.isMonthlyDue(now: due, defaults: defaults, calendar: calendar))
    }
}
