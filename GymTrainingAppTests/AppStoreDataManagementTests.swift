import XCTest
@testable import GymTrainingApp

@MainActor
final class AppStoreDataManagementTests: XCTestCase {
    func testAllDataExportIncludesDailyWorkoutSelection() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let plan = TrainingPlan(name: "朝のメニュー")
        store.plans = [plan]
        store.dailyWorkoutSelection = DailyWorkoutSelection(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            planID: plan.id
        )

        let data = try store.makeExportData()
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let selection = try XCTUnwrap(payload["dailyWorkoutSelection"] as? [String: Any])

        XCTAssertEqual(payload["schemaVersion"] as? Int, 6)
        XCTAssertEqual(selection["planID"] as? String, plan.id.uuidString)
    }

    func testSameDayWorkoutSessionsRemainIndependentAndOrdered() {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let morning = WorkoutSession(
            title: "朝トレ",
            sourcePlanID: nil,
            startedAt: calendar.date(byAdding: .hour, value: 1, to: day)!,
            endedAt: calendar.date(byAdding: .hour, value: 2, to: day),
            exercises: []
        )
        let evening = WorkoutSession(
            title: "夜トレ",
            sourcePlanID: nil,
            startedAt: calendar.date(byAdding: .hour, value: 8, to: day)!,
            endedAt: calendar.date(byAdding: .hour, value: 9, to: day),
            exercises: []
        )

        store.saveWorkoutHistorySession(morning)
        store.saveWorkoutHistorySession(evening)
        let sessions = store.workoutSessions(on: day)

        XCTAssertEqual(sessions.map(\.id), [evening.id, morning.id])
        XCTAssertEqual(repository.workoutHistory.count, 2)
    }
}
