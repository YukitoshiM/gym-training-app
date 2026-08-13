import XCTest
@testable import GymTrainingApp

final class InitialSetupTests: XCTestCase {
    func testFreshInstallRequiresInitialSetup() {
        let defaults = makeDefaults()

        let version = InitialSetupStateStore.prepareForLaunch(defaults: defaults, arguments: [])

        XCTAssertEqual(version, 0)
        XCTAssertEqual(defaults.integer(forKey: InitialSetupStateStore.completedVersionKey), 0)
    }

    func testPreviousInstallSkipsNewInitialSetup() {
        let defaults = makeDefaults()
        defaults.set("previous", forKey: LegalConsentStore.acceptedVersionKey)

        let version = InitialSetupStateStore.prepareForLaunch(defaults: defaults, arguments: [])

        XCTAssertEqual(version, InitialSetupStateStore.currentVersion)
        XCTAssertEqual(
            defaults.integer(forKey: InitialSetupStateStore.completedVersionKey),
            InitialSetupStateStore.currentVersion
        )
    }

    func testCompletedInitialSetupPersists() {
        let defaults = makeDefaults()

        InitialSetupStateStore.markCompleted(defaults: defaults)

        XCTAssertEqual(
            InitialSetupStateStore.prepareForLaunch(defaults: defaults, arguments: []),
            InitialSetupStateStore.currentVersion
        )
    }

    func testLegacyProfileGetsGoalSpecificDefaults() throws {
        let data = Data(#"{"goalType":"muscleGain"}"#.utf8)

        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(profile.outcomeStyle, .leanMuscular)
        XCTAssertEqual(profile.weeklyTrainingDays, 3)
        XCTAssertEqual(profile.preferredSessionMinutes, 60)
        XCTAssertTrue(profile.focusMuscles.isEmpty)
        XCTAssertEqual(profile.availableEquipment, Equipment.allCases)
        XCTAssertEqual(profile.coachingStyle, .analytical)
    }

    func testLegacyProfileKeepsPersonaSpecificCoachingStyle() throws {
        let data = Data(#"{"goalType":"muscleGain","coachPersona":"maya"}"#.utf8)

        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(profile.coachPersona, .maya)
        XCTAssertEqual(profile.coachingStyle, .encouraging)
    }

    func testCoachRecommendationUsesGoalAndOutcome() {
        var profile = UserProfile.default
        profile.goalType = .muscleGain
        profile.outcomeStyle = .vShape

        let reason = CoachType.recommendationReason(for: profile)

        XCTAssertEqual(CoachType.recommended(for: profile.goalType), .hypertrophy)
        XCTAssertTrue(reason.contains("筋肥大"))
        XCTAssertTrue(reason.contains("Vシェイプ"))
        XCTAssertEqual(CoachType.recommendations(for: profile).count, 3)
        XCTAssertEqual(CoachType.recommendations(for: profile).first?.coachType, .hypertrophy)
    }

    func testCoachRecommendationsDoNotDependOnSexOrPersona() {
        var first = UserProfile.default
        first.goalType = .health
        first.outcomeStyle = .activeLifestyle
        first.sex = .female
        first.coachPersona = .maya

        var second = first
        second.sex = .male
        second.coachPersona = .ken

        XCTAssertEqual(
            CoachType.recommendations(for: first).map(\.coachType),
            CoachType.recommendations(for: second).map(\.coachType)
        )
    }

    func testOutcomeStyleOptionsFollowPurpose() {
        XCTAssertTrue(OutcomeStyle.available(for: .muscleGain).contains(.vShape))
        XCTAssertFalse(OutcomeStyle.available(for: .health).contains(.vShape))
        XCTAssertTrue(OutcomeStyle.available(for: .health).contains(.activeLifestyle))
        XCTAssertEqual(OutcomeStyle.available(for: .performance).last, .custom)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "InitialSetupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
