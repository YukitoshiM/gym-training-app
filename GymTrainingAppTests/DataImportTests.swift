import XCTest
@testable import GymTrainingApp

@MainActor
final class DataImportTests: XCTestCase {
    func testStrongAutodetectionRequiresExplicitUnitAndTimeZoneThenNormalizes() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let data = try fixtureData("strong-export.csv")

        let blocked = try store.prepareDataImport(data: data, fileName: "strong-export.csv")
        XCTAssertEqual(blocked.format, .strongCSV)
        XCTAssertTrue(blocked.requiresWeightUnit)
        XCTAssertTrue(blocked.requiresTimeZoneConfirmation)
        XCTAssertFalse(blocked.canImport)

        let options = DataImportOptions(
            ambiguousWeightUnit: .kg,
            timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            hasConfirmedTimeZone: true
        )
        let preview = try store.prepareDataImport(
            data: data,
            fileName: "strong-export.csv",
            options: options
        )

        XCTAssertTrue(preview.canImport)
        XCTAssertEqual(preview.summary.workoutCount, 1)
        XCTAssertEqual(preview.summary.setCount, 2)
        XCTAssertEqual(preview.payload.workouts[0].exercises[0].sets[1].actualWeight, 62.5, accuracy: 0.001)
        XCTAssertTrue(preview.payload.workouts[0].exercises[0].sets.allSatisfy(\.isAdded))
        XCTAssertTrue(preview.payload.workouts[0].exercises[0].sets[0].note?.contains("Controlled\ntempo") == true)
    }

    func testHevyVariantNormalizesZeroBasedSetIndexAndPreservesSetType() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let options = DataImportOptions(
            timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            hasConfirmedTimeZone: true
        )
        let preview = try store.prepareDataImport(
            data: fixtureData("hevy-export.csv"),
            fileName: "hevy-export.csv",
            options: options
        )

        XCTAssertEqual(preview.format, .hevyCSV)
        let sets = try XCTUnwrap(preview.payload.workouts.first?.exercises.first?.sets)
        XCTAssertEqual(sets.map(\.setOrder), [1, 2])
        XCTAssertEqual(sets.map(\.actualWeight), [30, 50])
        XCTAssertTrue(sets[0].note?.contains("warmup") == true)
    }

    func testJEFITAndGenericFormatsAreAutodetectedAndWeightsNormalizeToKilograms() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let confirmed = DataImportOptions(
            timeZone: TimeZone(identifier: "America/New_York")!,
            hasConfirmedTimeZone: true
        )
        let jefit = try store.prepareDataImport(
            data: fixtureData("jefit-export.csv"),
            fileName: "jefit-export.csv",
            options: confirmed
        )
        let generic = try store.prepareDataImport(
            data: fixtureData("generic-workouts.csv"),
            fileName: "training.csv"
        )

        XCTAssertEqual(jefit.format, .jefitCSV)
        XCTAssertEqual(jefit.payload.workouts[0].exercises[0].sets[0].actualWeight, 99.7903, accuracy: 0.001)
        XCTAssertEqual(generic.format, .genericCSV)
        XCTAssertEqual(generic.summary.workoutCount, 1)
        XCTAssertEqual(generic.payload.workouts[0].exercises[0].sets[0].rpe, 7.5)
    }

    func testAppleHealthXMLImportsAndNormalizesBodyMetricsAndWorkout() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let preview = try store.prepareDataImport(
            data: fixtureData("apple-health-export.xml"),
            fileName: "export.xml"
        )

        XCTAssertEqual(preview.format, .appleHealthXML)
        XCTAssertEqual(preview.summary.workoutCount, 1)
        XCTAssertEqual(preview.summary.bodyMetricCount, 3)
        let weight = try XCTUnwrap(preview.payload.bodyMetrics.first { $0.kind == .bodyWeight })
        let waist = try XCTUnwrap(preview.payload.bodyMetrics.first { $0.kind == .waist })
        XCTAssertEqual(weight.value, 70, accuracy: 0.01)
        XCTAssertEqual(waist.value, 82, accuracy: 0.001)
        XCTAssertEqual(preview.payload.workouts[0].endedAt?.timeIntervalSince(preview.payload.workouts[0].startedAt), 2_700)
    }

    func testBodyModeSchemaSixRestoresWithEmptyPlanRevisionProposals() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let preview = try store.prepareDataImport(
            data: fixtureData("bodymode-schema-6.json"),
            fileName: "bodymode-export.json"
        )

        XCTAssertEqual(preview.format, .bodyModeJSON)
        XCTAssertTrue(preview.canImport)
        XCTAssertEqual(preview.payload.bodyModeRestore?.schemaVersion, 6)
        XCTAssertEqual(preview.payload.bodyModeRestore?.planRevisionProposals, [])
    }

    func testSchemaEightExportIncludesPlanRevisionProposals() throws {
        let store = AppStore(storage: TestAppDataRepository())
        let plan = TrainingPlan(name: "Strength A")
        store.planRevisionProposals = [PlanRevisionProposal(
            triggerSessionID: UUID(),
            originalPlan: plan,
            summary: "Increase load",
            baselineAchievementRate: 1
        )]

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: store.makeExportData()) as? [String: Any])
        XCTAssertEqual(payload["schemaVersion"] as? Int, 8)
        XCTAssertEqual((payload["planRevisionProposals"] as? [[String: Any]])?.count, 1)
    }

    func testApplyPreventsFingerprintAndSemanticDuplicates() throws {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let data = try fixtureData("generic-workouts.csv")
        let first = try store.prepareDataImport(data: data, fileName: "training.csv")
        try store.applyDataImport(first)

        let sameFile = try store.prepareDataImport(data: data, fileName: "renamed.csv")
        XCTAssertTrue(sameFile.wasPreviouslyImported)
        XCTAssertFalse(sameFile.canImport)

        var changedBytes = data
        changedBytes.append(contentsOf: Data("\n".utf8))
        let sameRecords = try store.prepareDataImport(data: changedBytes, fileName: "different.csv")
        XCTAssertEqual(sameRecords.summary.duplicateCount, 1)
        XCTAssertEqual(sameRecords.summary.workoutCount, 0)
        XCTAssertFalse(sameRecords.canImport)
        XCTAssertEqual(store.workoutHistory.count, 1)
    }

    func testBatchRollbackRestoresAllChangedCollections() throws {
        let repository = TestAppDataRepository()
        let original = WorkoutSession(title: "Original", sourcePlanID: nil, exercises: [])
        repository.workoutHistory = [original]
        let store = AppStore(storage: repository)
        let preview = try store.prepareDataImport(
            data: fixtureData("generic-workouts.csv"),
            fileName: "training.csv"
        )

        let receipt = try store.applyDataImport(preview)
        XCTAssertEqual(store.workoutHistory.count, 2)
        XCTAssertEqual(store.latestUndoableDataImport?.id, receipt.id)

        let rolledBack = try store.rollbackLatestDataImport()
        XCTAssertEqual(rolledBack.state, .rolledBack)
        XCTAssertEqual(store.workoutHistory.map(\.id), [original.id])
        XCTAssertNil(store.latestUndoableDataImport)

        let again = try store.prepareDataImport(
            data: fixtureData("generic-workouts.csv"),
            fileName: "training.csv"
        )
        XCTAssertTrue(again.canImport)
    }

    func testBodyModeRestoreIncludesPlanRevisionsAndRollbackRestoresPreviousData() throws {
        let source = AppStore(storage: TestAppDataRepository())
        let restoredPlan = TrainingPlan(name: "Restored Plan")
        source.plans = [restoredPlan]
        source.planRevisionProposals = [PlanRevisionProposal(
            triggerSessionID: UUID(),
            originalPlan: restoredPlan,
            summary: "Restored revision",
            baselineAchievementRate: 0.9
        )]
        let backup = try source.makeExportData()

        let destinationRepository = TestAppDataRepository()
        let previousPlan = TrainingPlan(name: "Previous Plan")
        destinationRepository.plans = [previousPlan]
        let destination = AppStore(storage: destinationRepository)
        let preview = try destination.prepareDataImport(
            data: backup,
            fileName: "bodymode-export.json"
        )

        try destination.applyDataImport(preview)
        XCTAssertEqual(destination.plans.map(\.name), ["Restored Plan"])
        XCTAssertEqual(destination.planRevisionProposals.map(\.summary), ["Restored revision"])

        _ = try destination.rollbackLatestDataImport()
        XCTAssertEqual(destination.plans.map(\.id), [previousPlan.id])
        XCTAssertTrue(destination.planRevisionProposals.isEmpty)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile.deletingLastPathComponent()
            .appendingPathComponent("Fixtures/DataImport")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
