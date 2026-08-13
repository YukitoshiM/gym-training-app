import Foundation
@preconcurrency import WatchConnectivity

extension WatchWorkoutStore {
    func configureSession() {
        guard WCSession.isSupported() else {
            statusMessage = "このWatchでは連携を利用できません"
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.unsupported",
                message: "WatchConnectivity is unavailable"
            )
            return
        }

        WatchDiagnostics.shared.record(
            category: "connectivity.activation",
            message: "WatchConnectivity activation requested"
        )
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func flushDiagnostics() {
        #if targetEnvironment(simulator)
        return
        #else
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard !session.outstandingUserInfoTransfers.contains(where: {
            $0.userInfo[WatchWorkoutTransfer.messageTypeKey] as? String
                == WatchWorkoutTransfer.diagnosticsBatchType
        }) else {
            return
        }

        let events = WatchDiagnostics.shared.pendingBatch()
        guard !events.isEmpty else { return }

        do {
            let payload = try encoder.encode(events)
            session.transferUserInfo([
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.diagnosticsBatchType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ])
            WatchDiagnostics.shared.remove(ids: Set(events.map(\.id)))
        } catch {
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.diagnostics_encode",
                message: "Failed to encode diagnostics batch",
                metadata: ["error": error.localizedDescription]
            )
        }
        #endif
    }

    func sendLiveSessionUpdate(force: Bool) {
        guard let activeSession,
              WCSession.isSupported() else {
            return
        }

        let now = Date()
        if !force,
           let lastLiveUpdateSentAt,
           now.timeIntervalSince(lastLiveUpdateSentAt) < 1.5 {
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return
        }

        do {
            let snapshot = WatchLiveWorkoutSnapshot(
                updatedAt: now,
                session: activeSession,
                restRemaining: restRemaining,
                isRestTimerRunning: isRestTimerRunning,
                restExerciseID: restExerciseID,
                liveMetrics: liveMetrics
            )
            let payload = try encoder.encode(snapshot)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.sessionLiveUpdateType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: now
            ]
            lastLiveUpdateSentAt = now
            Self.sendWithoutReply(
                message,
                through: session,
                failureContext: "Watch live update failed"
            )
        } catch {
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.live_encode",
                message: "Failed to encode live workout update",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func sendLiveSessionEnded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return
        }

        let message: [String: Any] = [
            WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.sessionLiveEndedType,
            WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
            WatchWorkoutTransfer.sentAtKey: Date()
        ]
        Self.sendWithoutReply(
            message,
            through: session,
            failureContext: "Watch live end failed"
        )
    }

    func apply(command: WatchWorkoutCommand) {
        switch command.action {
        case .startSet:
            guard let exerciseID = command.exerciseID, let setID = command.setID else { return }
            startSet(exerciseID: exerciseID, setID: setID)
        case .completeSet:
            guard let exerciseID = command.exerciseID, let setID = command.setID else { return }
            setCompletion(exerciseID: exerciseID, setID: setID, isCompleted: true)
        case .cancelSet:
            guard let exerciseID = command.exerciseID, let setID = command.setID else { return }
            cancelSet(exerciseID: exerciseID, setID: setID)
        case .updateSet:
            guard let exerciseID = command.exerciseID, let setID = command.setID else { return }
            if let actualWeight = command.actualWeight {
                setWeight(exerciseID: exerciseID, setID: setID, weight: actualWeight)
            }
            if let actualReps = command.actualReps {
                setReps(exerciseID: exerciseID, setID: setID, reps: actualReps)
            }
            if command.plannedConcentricSeconds != nil ||
                command.plannedEccentricSeconds != nil ||
                command.plannedTempoBeatSpeed != nil {
                setPlannedTempo(
                    exerciseID: exerciseID,
                    setID: setID,
                    concentricSeconds: command.plannedConcentricSeconds ?? 1,
                    eccentricSeconds: command.plannedEccentricSeconds ?? 1,
                    beatSpeed: command.plannedTempoBeatSpeed ?? 1
                )
            }
            updateRPE(exerciseID: exerciseID, setID: setID, rpe: command.rpe)
        case .stopRestTimer:
            stopRestTimer()
        case .finishWorkout:
            finishWorkout()
        case .cancelWorkout:
            cancelWorkout()
        }
    }

    func savePendingSession() {
        guard let pendingFinishedSession,
              let data = try? encoder.encode(pendingFinishedSession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: pendingSessionStorageKey)
    }

    func clearPendingSession() {
        pendingFinishedSession = nil
        UserDefaults.standard.removeObject(forKey: pendingSessionStorageKey)
    }

    func sendFinishedSession(_ finishedSession: WatchWorkoutSessionSnapshot) {
        guard WCSession.isSupported() else {
            statusMessage = "このWatchではiPhone連携を利用できません。記録はWatchに残しています"
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            statusMessage = "iPhone連携を準備中です。あとで再送できます"
            session.activate()
            return
        }

        do {
            let payload = try encoder.encode(finishedSession)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.sessionFinishedType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sessionIDKey: finishedSession.id.uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ]

            statusMessage = "\(finishedSession.title) をiPhoneへ送信中"

            if session.isReachable {
                sendImmediately(
                    message: message,
                    sessionID: finishedSession.id,
                    title: finishedSession.title,
                    session: session
                )
            } else {
                session.transferUserInfo(message)
                statusMessage = "\(finishedSession.title) はiPhoneへ送信予約しました"
                WatchDiagnostics.shared.record(
                    category: "connectivity.session_queued",
                    message: "Finished workout queued for iPhone",
                    metadata: [
                        "session_id": finishedSession.id.uuidString,
                        "completed_sets": String(finishedSession.completedSetCount)
                    ]
                )
                flushDiagnostics()
            }
        } catch {
            statusMessage = "iPhoneへ送る記録データを作れませんでした"
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.session_encode",
                message: "Failed to encode finished workout",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    @discardableResult
    nonisolated func receive(userInfo: [String: Any]) -> Bool {
        guard let messageType = userInfo[WatchWorkoutTransfer.messageTypeKey] as? String else {
            return false
        }

        switch messageType {
        case WatchWorkoutTransfer.planLibraryPushType:
            guard let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else { return false }
            guard let library = try? JSONDecoder().decode(WatchWorkoutPlanLibrarySnapshot.self, from: data) else {
                updateStatus("メニューデータを読み込めませんでした")
                WatchDiagnostics.shared.record(
                    level: "error",
                    category: "connectivity.plan_decode",
                    message: "Failed to decode workout plan library"
                )
                return false
            }

            WatchDiagnostics.shared.record(
                category: "connectivity.plan_received",
                message: "Workout plan library received",
                metadata: ["plan_count": String(library.plans.count)]
            )
            Task { @MainActor [weak self] in
                self?.apply(library: library, data: data)
            }
            return true

        case WatchWorkoutTransfer.planPushType:
            guard let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else { return false }
            guard let snapshot = try? JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data) else {
                updateStatus("メニューデータを読み込めませんでした")
                WatchDiagnostics.shared.record(
                    level: "error",
                    category: "connectivity.plan_decode",
                    message: "Failed to decode workout plan"
                )
                return false
            }

            WatchDiagnostics.shared.record(
                category: "connectivity.plan_received",
                message: "Workout plan received"
            )
            Task { @MainActor [weak self] in
                self?.apply(library: WatchWorkoutPlanLibrarySnapshot(plans: [snapshot]))
            }
            return true

        case WatchWorkoutTransfer.workoutCommandType:
            guard let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data,
                  let command = try? JSONDecoder().decode(WatchWorkoutCommand.self, from: data) else {
                return false
            }
            Task { @MainActor [weak self] in
                self?.apply(command: command)
            }
            return true

        default:
            return false
        }
    }

    nonisolated func updateStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }

    // WCSession invokes error handlers on its own operation queue. Defining the
    // callback outside MainActor prevents a runtime executor assertion.
    nonisolated static func sendWithoutReply(
        _ message: [String: Any],
        through session: WCSession,
        failureContext: String
    ) {
        session.sendMessage(message, replyHandler: nil) { error in
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.live_send",
                message: failureContext,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    nonisolated func sendImmediately(
        message: [String: Any],
        sessionID: UUID,
        title: String,
        session: WCSession
    ) {
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let acknowledged = WatchWorkoutTransfer.acceptsAcknowledgement(
                reply,
                expectedSessionID: sessionID
            )
            let acknowledgedSessionID = WatchWorkoutTransfer.finishedSessionID(in: reply)
                ?? sessionID
            WatchDiagnostics.shared.record(
                level: acknowledged ? "info" : "error",
                category: "connectivity.session_acknowledged",
                message: acknowledged
                    ? "iPhone acknowledged finished workout"
                    : "iPhone rejected or mismatched finished workout acknowledgement",
                metadata: [
                    "session_id": sessionID.uuidString,
                    "acknowledged_session_id": acknowledgedSessionID.uuidString
                ]
            )
            self?.updateSendResult(
                acknowledged: acknowledged,
                sessionID: sessionID,
                successMessage: "\(title) をiPhone履歴へ保存しました"
            )
        }, errorHandler: { [weak self] error in
            session.transferUserInfo(message)
            self?.updateStatus("\(title) はiPhoneへ送信予約しました")
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.session_immediate_send",
                message: "Immediate workout send failed; queued for delivery",
                metadata: ["error": error.localizedDescription]
            )
        })
    }

    nonisolated func updateSendResult(
        acknowledged: Bool,
        sessionID: UUID,
        successMessage: String
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: pendingFinishedSession?.id,
                completedSessionID: sessionID,
                succeeded: acknowledged
            )
            switch resolution {
            case .clearPending:
                clearPendingSession()
                statusMessage = successMessage
            case .retainPending:
                statusMessage = "iPhone側で保存できませんでした。あとで再送できます"
            case .ignoreStaleCompletion:
                WatchDiagnostics.shared.record(
                    category: "connectivity.session_stale_ack",
                    message: "Ignored acknowledgement for a non-pending workout",
                    metadata: ["session_id": sessionID.uuidString]
                )
            }
            flushDiagnostics()
        }
    }

    nonisolated func updateQueuedTransferResult(
        sessionID: UUID?,
        succeeded: Bool,
        errorDescription: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = WatchPendingFinishedSessionResolution.resolve(
                pendingSessionID: pendingFinishedSession?.id,
                completedSessionID: sessionID,
                succeeded: succeeded
            )
            switch resolution {
            case .clearPending:
                let title = pendingFinishedSession?.title ?? "ワークアウト"
                clearPendingSession()
                statusMessage = "\(title) をiPhoneへ送信しました"
                WatchDiagnostics.shared.record(
                    category: "connectivity.session_queue_delivered",
                    message: "Queued finished workout delivered to iPhone",
                    metadata: ["session_id": sessionID?.uuidString ?? "unknown"]
                )
            case .retainPending:
                statusMessage = "iPhoneへ送信できませんでした。記録を残して再送します"
                WatchDiagnostics.shared.record(
                    level: "error",
                    category: "connectivity.session_queue_failed",
                    message: "Queued finished workout delivery failed",
                    metadata: [
                        "session_id": sessionID?.uuidString ?? "unknown",
                        "error": errorDescription ?? "unknown"
                    ]
                )
            case .ignoreStaleCompletion:
                WatchDiagnostics.shared.record(
                    category: "connectivity.session_queue_stale",
                    message: "Ignored queued transfer completion for a non-pending workout",
                    metadata: ["session_id": sessionID?.uuidString ?? "unknown"]
                )
            }
            flushDiagnostics()
        }
    }

    nonisolated func updateActivationStatus(
        activationState: WCSessionActivationState,
        errorDescription: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let errorDescription {
                statusMessage = "接続失敗: \(errorDescription)"
                WatchDiagnostics.shared.record(
                    level: "error",
                    category: "connectivity.activation",
                    message: "WatchConnectivity activation failed",
                    metadata: ["error": errorDescription]
                )
            } else if activationState == .activated {
                WatchDiagnostics.shared.record(
                    category: "connectivity.activation",
                    message: "WatchConnectivity activated"
                )
                if pendingFinishedSession != nil {
                    resendPendingSession()
                } else {
                    statusMessage = activeSession == nil ? "iPhoneと接続しました" : "\(activeSession?.title ?? "ワークアウト") を記録中"
                }
                flushDiagnostics()
            }
        }
    }
}
extension WatchWorkoutStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        updateActivationStatus(
            activationState: activationState,
            errorDescription: error?.localizedDescription
        )
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            Task { @MainActor [weak self] in
                if self?.pendingFinishedSession != nil {
                    self?.resendPendingSession()
                }
                self?.flushDiagnostics()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        let messageType = userInfoTransfer.userInfo[WatchWorkoutTransfer.messageTypeKey] as? String
        if messageType == WatchWorkoutTransfer.sessionFinishedType {
            updateQueuedTransferResult(
                sessionID: WatchWorkoutTransfer.finishedSessionID(in: userInfoTransfer.userInfo),
                succeeded: error == nil,
                errorDescription: error?.localizedDescription
            )
            return
        }

        guard messageType == WatchWorkoutTransfer.diagnosticsBatchType,
              let payload = userInfoTransfer.userInfo[WatchWorkoutTransfer.payloadKey] as? Data,
              let events = try? JSONDecoder().decode([WatchDiagnosticEvent].self, from: payload) else {
            return
        }

        if let error {
            WatchDiagnostics.shared.restore(events)
            WatchDiagnostics.shared.record(
                level: "error",
                category: "connectivity.diagnostics_transfer",
                message: "Diagnostics transfer failed",
                metadata: ["error": error.localizedDescription]
            )
            return
        }

        Task { @MainActor [weak self] in
            self?.flushDiagnostics()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(userInfo: message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let accepted = receive(userInfo: message)
        replyHandler([WatchWorkoutTransfer.acknowledgementKey: accepted])
    }
}
