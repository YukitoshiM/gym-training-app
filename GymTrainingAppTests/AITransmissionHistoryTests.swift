import XCTest
@testable import GymTrainingApp

@MainActor
final class AITransmissionHistoryTests: XCTestCase {
    func testFailureStoresRecoveryAndQuotaState() {
        let repository = TestAppDataRepository()
        let store = AppStore(storage: repository)
        let record = AITransmissionRecord(
            purpose: "test",
            sharedCategories: ["workout"],
            itemCount: 1
        )
        store.saveAITransmission(record)

        store.recordAITransmissionFailure(
            id: record.id,
            error: AIClientError.requestFailed(URLError(.timedOut))
        )

        let saved = store.aiTransmissionHistory[0]
        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.canRetry, true)
        XCTAssertEqual(saved.consumedQuota, false)
        XCTAssertFalse(saved.failureMessage?.isEmpty ?? true)
        XCTAssertFalse(saved.recoverySuggestion?.isEmpty ?? true)
    }

    func testLegacyRecordDecodesWithoutFailureMetadata() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","sentAt":0,"purpose":"legacy","sharedCategories":[],"itemCount":0,"status":"completed"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let record = try decoder.decode(AITransmissionRecord.self, from: data)

        XCTAssertNil(record.failureMessage)
        XCTAssertNil(record.canRetry)
        XCTAssertNil(record.consumedQuota)
    }
}
