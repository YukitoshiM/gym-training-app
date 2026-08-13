import Foundation
import XCTest
@testable import GymTrainingApp

final class WatchConnectivityReliabilityTests: XCTestCase {
    func testPersistenceAcknowledgesOnlyAfterSavedSessionCanBeReadBack() {
        let session = makeWorkoutSession()
        var persisted: [WorkoutSession] = []
        var operations: [String] = []

        let result = WatchFinishedSessionPersistenceVerifier.persist(
            session,
            loadPersistedSessions: {
                operations.append("load")
                return persisted
            },
            save: {
                operations.append("save")
                persisted = [session]
            }
        )

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(operations, ["load", "save", "load"])
    }

    func testPersistenceFailureIsReportedWhenSessionCannotBeReadBack() {
        let session = makeWorkoutSession()
        var saveCount = 0

        let result = WatchFinishedSessionPersistenceVerifier.persist(
            session,
            loadPersistedSessions: { [] },
            save: { saveCount += 1 }
        )

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(saveCount, 1)
    }

    func testAcknowledgementRequiresSavedOrConfirmedDuplicateSession() {
        XCTAssertTrue(WatchFinishedSessionPersistenceResult.saved.canAcknowledge)
        XCTAssertTrue(WatchFinishedSessionPersistenceResult.duplicate.canAcknowledge)
        XCTAssertFalse(WatchFinishedSessionPersistenceResult.failed.canAcknowledge)
    }

    func testPersistedDuplicateIsAcknowledgedWithoutSavingAgain() {
        let session = makeWorkoutSession()
        var saveCount = 0

        let result = WatchFinishedSessionPersistenceVerifier.persist(
            session,
            loadPersistedSessions: { [session] },
            save: { saveCount += 1 }
        )

        XCTAssertEqual(result, .duplicate)
        XCTAssertEqual(saveCount, 0)
    }

    func testSuccessfulCompletionClearsOnlyMatchingPendingSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: sessionID,
                completedSessionID: sessionID,
                succeeded: true
            ),
            .clearPending
        )
    }

    func testFailedQueuedTransferRetainsMatchingPendingSession() {
        let sessionID = UUID()

        XCTAssertEqual(
            WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: sessionID,
                completedSessionID: sessionID,
                succeeded: false
            ),
            .retainPending
        )
    }

    func testStaleAcknowledgementCannotClearDifferentPendingSession() {
        XCTAssertEqual(
            WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: UUID(),
                completedSessionID: UUID(),
                succeeded: true
            ),
            .ignoreStaleCompletion
        )
    }

    func testDuplicateAcknowledgementAfterPendingWasClearedIsIgnored() {
        XCTAssertEqual(
            WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: nil,
                completedSessionID: UUID(),
                succeeded: true
            ),
            .ignoreStaleCompletion
        )
    }

    func testFinishedSessionIdentityUsesMetadataForNewBuilds() throws {
        let metadataID = UUID()
        let payloadSession = makeWatchSession(id: UUID())
        let message: [String: Any] = [
            WatchWorkoutTransfer.sessionIDKey: metadataID.uuidString,
            WatchWorkoutTransfer.payloadKey: try JSONEncoder().encode(payloadSession)
        ]

        XCTAssertEqual(WatchWorkoutTransfer.finishedSessionID(in: message), metadataID)
    }

    func testFinishedSessionIdentityFallsBackToPayloadForOlderBuilds() throws {
        let session = makeWatchSession(id: UUID())
        let legacyMessage: [String: Any] = [
            WatchWorkoutTransfer.payloadKey: try JSONEncoder().encode(session)
        ]

        XCTAssertEqual(WatchWorkoutTransfer.finishedSessionID(in: legacyMessage), session.id)
    }

    func testAcknowledgementCarriesSessionIdentity() {
        let sessionID = UUID()
        let reply = WatchWorkoutTransfer.acknowledgement(
            accepted: true,
            sessionID: sessionID
        )

        XCTAssertEqual(reply[WatchWorkoutTransfer.acknowledgementKey] as? Bool, true)
        XCTAssertEqual(WatchWorkoutTransfer.finishedSessionID(in: reply), sessionID)
    }

    func testMatchingSessionAcknowledgementIsAccepted() {
        let sessionID = UUID()
        let reply = WatchWorkoutTransfer.acknowledgement(
            accepted: true,
            sessionID: sessionID
        )

        XCTAssertTrue(
            WatchWorkoutTransfer.acceptsAcknowledgement(
                reply,
                expectedSessionID: sessionID
            )
        )
    }

    func testMismatchedSessionAcknowledgementIsRejected() {
        let reply = WatchWorkoutTransfer.acknowledgement(
            accepted: true,
            sessionID: UUID()
        )

        XCTAssertFalse(
            WatchWorkoutTransfer.acceptsAcknowledgement(
                reply,
                expectedSessionID: UUID()
            )
        )
    }

    func testNegativeAcknowledgementIsRejected() {
        let sessionID = UUID()
        let reply = WatchWorkoutTransfer.acknowledgement(
            accepted: false,
            sessionID: sessionID
        )

        XCTAssertFalse(
            WatchWorkoutTransfer.acceptsAcknowledgement(
                reply,
                expectedSessionID: sessionID
            )
        )
    }

    func testLegacyAcknowledgementWithoutSessionIdentityRemainsCompatible() {
        let reply: [String: Any] = [
            WatchWorkoutTransfer.acknowledgementKey: true
        ]

        XCTAssertTrue(
            WatchWorkoutTransfer.acceptsAcknowledgement(
                reply,
                expectedSessionID: UUID()
            )
        )
    }

    private func makeWorkoutSession(id: UUID = UUID()) -> WorkoutSession {
        WorkoutSession(
            id: id,
            title: "Watch workout",
            sourcePlanID: nil,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            exercises: [],
            sourceDevice: .appleWatch,
            watchSyncState: .received
        )
    }

    private func makeWatchSession(id: UUID) -> WatchWorkoutSessionSnapshot {
        WatchWorkoutSessionSnapshot(
            id: id,
            sourcePlanID: nil,
            title: "Watch workout",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            weightUnit: .kg,
            exercises: []
        )
    }
}
