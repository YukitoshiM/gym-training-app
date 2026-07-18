import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published private(set) var plan: WatchWorkoutPlanSnapshot?
    @Published private(set) var activeSession: WatchWorkoutSessionSnapshot?
    @Published private(set) var pendingFinishedSession: WatchWorkoutSessionSnapshot?
    @Published private(set) var statusMessage = "iPhoneから今日の計画を送信してください"
    @Published private(set) var restRemaining = 0
    @Published private(set) var isRestTimerRunning = false

    private let planStorageKey = "gym.training.watch.currentPlan"
    private let activeSessionStorageKey = "gym.training.watch.activeSession"
    private let pendingSessionStorageKey = "gym.training.watch.pendingFinishedSession"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        super.init()
        loadSavedState()
        configureSession()
    }

    func startWorkout() {
        guard let plan else {
            statusMessage = "先にiPhoneから計画を送信してください"
            return
        }

        activeSession = WatchWorkoutSessionSnapshot(plan: plan)
        restRemaining = 0
        isRestTimerRunning = false
        statusMessage = "\(plan.name) を開始しました"
        saveActiveSession()
    }

    func cancelWorkout() {
        activeSession = nil
        restRemaining = 0
        isRestTimerRunning = false
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        statusMessage = plan == nil ? "iPhoneから今日の計画を送信してください" : "ワークアウトを破棄しました"
    }

    func adjustWeight(exerciseID: UUID, setID: UUID, delta: Double) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            set.actualWeight = max(0, min(999, set.actualWeight + delta))
        }
    }

    func adjustReps(exerciseID: UUID, setID: UUID, delta: Int) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            set.actualReps = max(0, min(999, set.actualReps + delta))
        }
    }

    func updateRPE(exerciseID: UUID, setID: UUID, rpe: Double?) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            set.rpe = rpe
        }
    }

    func setCompletion(exerciseID: UUID, setID: UUID, isCompleted: Bool) {
        var restSeconds = 0

        updateSession { session in
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
                return
            }

            restSeconds = session.exercises[exerciseIndex].restSeconds
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = isCompleted
            session.exercises[exerciseIndex].sets[setIndex].completedAt = isCompleted ? Date() : nil

            if !isCompleted {
                session.exercises[exerciseIndex].sets[setIndex].rpe = nil
            }
        }

        if isCompleted {
            startRestTimer(seconds: restSeconds)
        }
    }

    func tickRestTimer() {
        guard isRestTimerRunning else {
            return
        }

        if restRemaining > 0 {
            restRemaining -= 1
        }

        if restRemaining <= 0 {
            restRemaining = 0
            isRestTimerRunning = false
        }
    }

    func startRestTimer(seconds: Int? = nil) {
        let fallbackRest = activeSession?.exercises.first?.restSeconds ?? 90
        let nextRest = seconds ?? fallbackRest
        guard nextRest > 0 else {
            return
        }

        restRemaining = nextRest
        isRestTimerRunning = true
    }

    func stopRestTimer() {
        restRemaining = 0
        isRestTimerRunning = false
    }

    func finishWorkout() {
        guard var finished = activeSession else {
            statusMessage = "完了するワークアウトがありません"
            return
        }

        finished.endedAt = Date()
        pendingFinishedSession = finished
        activeSession = nil
        restRemaining = 0
        isRestTimerRunning = false
        savePendingSession()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        sendFinishedSession(finished)
    }

    func resendPendingSession() {
        guard let pendingFinishedSession else {
            statusMessage = "未送信のWatch記録はありません"
            return
        }

        sendFinishedSession(pendingFinishedSession)
    }

    private func configureSession() {
        guard WCSession.isSupported() else {
            statusMessage = "このWatchでは連携を利用できません"
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func loadSavedState() {
        if let data = UserDefaults.standard.data(forKey: planStorageKey),
           let savedPlan = try? decoder.decode(WatchWorkoutPlanSnapshot.self, from: data) {
            plan = savedPlan
            statusMessage = "前回受信した計画を表示しています"
        }

        if let data = UserDefaults.standard.data(forKey: activeSessionStorageKey),
           let savedSession = try? decoder.decode(WatchWorkoutSessionSnapshot.self, from: data) {
            activeSession = savedSession
            statusMessage = "\(savedSession.title) を再開できます"
        }

        if let data = UserDefaults.standard.data(forKey: pendingSessionStorageKey),
           let pendingSession = try? decoder.decode(WatchWorkoutSessionSnapshot.self, from: data) {
            pendingFinishedSession = pendingSession
            statusMessage = "\(pendingSession.title) はiPhoneへ再送できます"
        }
    }

    private func apply(plan snapshot: WatchWorkoutPlanSnapshot, data: Data) {
        plan = snapshot
        statusMessage = "\(snapshot.name) を受信しました"
        UserDefaults.standard.set(data, forKey: planStorageKey)
    }

    private func updateSession(_ body: (inout WatchWorkoutSessionSnapshot) -> Void) {
        guard var session = activeSession else {
            return
        }

        body(&session)
        activeSession = session
        saveActiveSession()
    }

    private func updateSet(
        exerciseID: UUID,
        setID: UUID,
        body: (inout WatchWorkoutSetSnapshot) -> Void
    ) {
        updateSession { session in
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
                return
            }

            body(&session.exercises[exerciseIndex].sets[setIndex])
        }
    }

    private func saveActiveSession() {
        guard let activeSession,
              let data = try? encoder.encode(activeSession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: activeSessionStorageKey)
    }

    private func savePendingSession() {
        guard let pendingFinishedSession,
              let data = try? encoder.encode(pendingFinishedSession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: pendingSessionStorageKey)
    }

    private func clearPendingSession() {
        pendingFinishedSession = nil
        UserDefaults.standard.removeObject(forKey: pendingSessionStorageKey)
    }

    private func sendFinishedSession(_ finishedSession: WatchWorkoutSessionSnapshot) {
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
                WatchWorkoutTransfer.sentAtKey: Date()
            ]

            statusMessage = "\(finishedSession.title) をiPhoneへ送信中"

            if session.isReachable {
                session.sendMessage(message, replyHandler: { [weak self] reply in
                    let acknowledged = reply[WatchWorkoutTransfer.acknowledgementKey] as? Bool ?? true
                    self?.updateSendResult(
                        acknowledged: acknowledged,
                        successMessage: "\(finishedSession.title) をiPhone履歴へ保存しました"
                    )
                }, errorHandler: { [weak self] error in
                    session.transferUserInfo(message)
                    self?.updateStatus("\(finishedSession.title) はiPhoneへ送信予約しました")
                    NSLog("Watch workout result immediate send failed: \(error.localizedDescription)")
                })
            } else {
                session.transferUserInfo(message)
                statusMessage = "\(finishedSession.title) はiPhoneへ送信予約しました"
            }
        } catch {
            statusMessage = "iPhoneへ送る記録データを作れませんでした"
        }
    }

    private nonisolated func receive(userInfo: [String: Any]) {
        guard userInfo[WatchWorkoutTransfer.messageTypeKey] as? String == WatchWorkoutTransfer.planPushType,
              let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else {
            return
        }

        do {
            let snapshot = try JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data)
            Task { @MainActor [weak self] in
                self?.apply(plan: snapshot, data: data)
            }
        } catch {
            updateStatus("計画データを読み込めませんでした")
        }
    }

    private nonisolated func updateStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }

    private nonisolated func updateSendResult(acknowledged: Bool, successMessage: String) {
        Task { @MainActor [weak self] in
            if acknowledged {
                self?.clearPendingSession()
                self?.statusMessage = successMessage
            } else {
                self?.statusMessage = "iPhone側で保存できませんでした。あとで再送できます"
            }
        }
    }

    private nonisolated func updateActivationStatus(
        activationState: WCSessionActivationState,
        errorDescription: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let errorDescription {
                statusMessage = "接続失敗: \(errorDescription)"
            } else if activationState == .activated {
                if pendingFinishedSession != nil {
                    resendPendingSession()
                } else {
                    statusMessage = activeSession == nil ? "iPhoneと接続しました" : "\(activeSession?.title ?? "ワークアウト") を記録中"
                }
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
                self?.resendPendingSession()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(userInfo: message)
    }
}
