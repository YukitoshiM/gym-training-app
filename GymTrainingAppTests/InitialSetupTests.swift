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
        XCTAssertEqual(profile.healthIntake, .default)
    }

    func testLegacyProfileKeepsPersonaSpecificCoachingStyle() throws {
        let data = Data(#"{"goalType":"muscleGain","coachPersona":"maya"}"#.utf8)

        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(profile.coachPersona, .camila)
        XCTAssertEqual(profile.coachingStyle, .encouraging)
    }

    func testEveryCoachTypeOffersOneWomanAndOneMan() {
        for coachType in CoachType.allCases {
            let personas = CoachPersona.options(for: coachType)

            XCTAssertEqual(personas.count, 2, "Expected exactly two personas for \(coachType)")
            XCTAssertEqual(Set(personas.map(\.gender)), Set([.woman, .man]))
        }
    }

    func testChangingPurposePreservesPersonaGender() {
        XCTAssertEqual(CoachPersona.hana.replacement(for: .strength), .ada)
        XCTAssertEqual(CoachPersona.omar.replacement(for: .wellness), .koa)
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
        first.coachPersona = .nia

        var second = first
        second.sex = .male
        second.coachPersona = .mateo

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

    func testHealthIntakeNormalizesGoalSpecificAnswers() {
        var intake = HealthIntakeProfile.default
        intake.activityLevel = .regular
        intake.plannedIntensity = .vigorous
        intake.safetyStatus = .noKnownConcerns
        intake.typicalSleep = .sevenToNine
        intake.goalFocus = .strengthAndPower
        intake.nutritionGuidanceMode = .followProfessionalPlan
        intake.otherTrainingDays = 18
        intake.sportOrActivity = "  Powerlifting  "

        let performance = intake.normalized(for: .performance)
        let health = intake.normalized(for: .health)

        XCTAssertEqual(performance.goalFocus, .strengthAndPower)
        XCTAssertEqual(performance.otherTrainingDays, 14)
        XCTAssertEqual(performance.sportOrActivity, "Powerlifting")
        XCTAssertEqual(performance.nutritionGuidanceMode, .notAnswered)
        XCTAssertEqual(health.goalFocus, .notAnswered)
        XCTAssertNil(health.otherTrainingDays)
        XCTAssertTrue(health.sportOrActivity.isEmpty)
    }

    func testExerciseRelatedSymptomsTriggerConservativeGuardrail() {
        var intake = HealthIntakeProfile.default
        intake.safetyStatus = .hasConsiderations
        intake.considerations = [.jointOrMuscleDiscomfort, .chestPainOrPressure]

        XCTAssertTrue(intake.requiresLoadAdjustment)
        XCTAssertTrue(intake.requiresProfessionalGuidance)
        XCTAssertTrue(intake.hasWarningSymptoms)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "InitialSetupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
