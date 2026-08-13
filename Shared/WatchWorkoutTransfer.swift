import Foundation

enum WatchWorkoutTransfer {
    static let messageTypeKey = "type"
    static let payloadKey = "payload"
    static let eventIDKey = "event_id"
    static let sessionIDKey = "session_id"
    static let sentAtKey = "sent_at"
    static let acknowledgementKey = "acknowledged"
    static let planPushType = "watch_plan_push"
    static let planLibraryPushType = "watch_plan_library_push"
    static let sessionFinishedType = "watch_session_finished"
    static let sessionLiveUpdateType = "watch_session_live_update"
    static let sessionLiveEndedType = "watch_session_live_ended"
    static let workoutCommandType = "watch_workout_command"
    static let diagnosticsBatchType = "watch_diagnostics_batch"

    static func finishedSessionID(in message: [String: Any]) -> UUID? {
        if let id = message[sessionIDKey] as? UUID {
            return id
        }
        if let value = message[sessionIDKey] as? String,
           let id = UUID(uuidString: value) {
            return id
        }
        guard let payload = message[payloadKey] as? Data,
              let session = try? JSONDecoder().decode(WatchWorkoutSessionSnapshot.self, from: payload) else {
            return nil
        }
        return session.id
    }

    static func acknowledgement(
        accepted: Bool,
        sessionID: UUID? = nil
    ) -> [String: Any] {
        var reply: [String: Any] = [acknowledgementKey: accepted]
        if let sessionID {
            reply[sessionIDKey] = sessionID.uuidString
        }
        return reply
    }

    static func acceptsAcknowledgement(
        _ reply: [String: Any],
        expectedSessionID: UUID
    ) -> Bool {
        guard reply[acknowledgementKey] as? Bool == true else {
            return false
        }
        guard let acknowledgedSessionID = finishedSessionID(in: reply) else {
            // Builds predating session-scoped acknowledgements returned only a Bool.
            return true
        }
        return acknowledgedSessionID == expectedSessionID
    }
}

enum WatchPendingFinishedSessionResolution: Equatable {
    case clearPending
    case retainPending
    case ignoreStaleCompletion

    static func resolve(
        pendingSessionID: UUID?,
        completedSessionID: UUID?,
        succeeded: Bool
    ) -> Self {
        guard let pendingSessionID,
              let completedSessionID,
              pendingSessionID == completedSessionID else {
            return .ignoreStaleCompletion
        }
        return succeeded ? .clearPending : .retainPending
    }
}

struct WatchDiagnosticEvent: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var timestamp: Date
    var level: String
    var category: String
    var message: String
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: String = "info",
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}

struct WatchLiveWorkoutSnapshot: Codable, Hashable, Sendable {
    var updatedAt: Date
    var session: WatchWorkoutSessionSnapshot
    var restRemaining: Int
    var isRestTimerRunning: Bool
    var restExerciseID: UUID?
    var liveMetrics: WatchLiveWorkoutMetrics
}

enum WatchWorkoutCommandAction: String, Codable, Hashable, Sendable {
    case startSet
    case completeSet
    case cancelSet
    case updateSet
    case stopRestTimer
    case finishWorkout
    case cancelWorkout
}

struct WatchWorkoutCommand: Codable, Hashable, Sendable {
    var action: WatchWorkoutCommandAction
    var exerciseID: UUID?
    var setID: UUID?
    var actualWeight: Double?
    var actualReps: Int?
    var rpe: Double?
    var plannedConcentricSeconds: Int?
    var plannedEccentricSeconds: Int?
    var plannedTempoBeatSpeed: Int?

    init(
        action: WatchWorkoutCommandAction,
        exerciseID: UUID? = nil,
        setID: UUID? = nil,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        rpe: Double? = nil,
        plannedConcentricSeconds: Int? = nil,
        plannedEccentricSeconds: Int? = nil,
        plannedTempoBeatSpeed: Int? = nil
    ) {
        self.action = action
        self.exerciseID = exerciseID
        self.setID = setID
        self.actualWeight = actualWeight
        self.actualReps = actualReps
        self.rpe = rpe
        self.plannedConcentricSeconds = plannedConcentricSeconds
        self.plannedEccentricSeconds = plannedEccentricSeconds
        self.plannedTempoBeatSpeed = plannedTempoBeatSpeed
    }
}
