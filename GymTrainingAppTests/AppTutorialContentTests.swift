import XCTest
@testable import GymTrainingApp

final class AppTutorialContentTests: XCTestCase {
    func testTutorialCoversThePrimaryDailyFlowInOrder() {
        XCTAssertEqual(AppTutorialContent.steps.map(\.id), ["record", "coach", "execute"])
        XCTAssertEqual(AppTutorialContent.steps.map(\.destination), ["記録", "AI", "計画・Watch"])
        XCTAssertEqual(Set(AppTutorialContent.steps.map(\.systemImage)).count, 3)
    }

    func testAppTourCanBeScheduledAndCompleted() {
        let suiteName = "AppTourStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(AppTourStateStore.shouldPresent(defaults: defaults, arguments: []))
        AppTourStateStore.schedule(defaults: defaults)
        XCTAssertTrue(AppTourStateStore.shouldPresent(defaults: defaults, arguments: []))
        AppTourStateStore.markCompleted(defaults: defaults)
        XCTAssertFalse(AppTourStateStore.shouldPresent(defaults: defaults, arguments: []))
    }

    func testAppTourCanBeForcedForUITesting() {
        let suiteName = "AppTourStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            AppTourStateStore.shouldPresent(defaults: defaults, arguments: ["--force-app-tour"])
        )
    }
}
