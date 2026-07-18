import Foundation
import WatchKit
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published private(set) var plans: [WatchWorkoutPlanSnapshot] = []
    @Published private(set) var selectedPlan: WatchWorkoutPlanSnapshot?
    @Published private(set) var activeSession: WatchWorkoutSessionSnapshot?
    @Published private(set) var pendingFinishedSession: WatchWorkoutSessionSnapshot?
    @Published private(set) var statusMessage = "iPhoneからメニューを同期してください"
    @Published private(set) var restRemaining = 0
    @Published private(set) var isRestTimerRunning = false

    private let planStorageKey = "gym.training.watch.currentPlan"
    private let planLibraryStorageKey = "gym.training.watch.planLibrary"
    private let activeSessionStorageKey = "gym.training.watch.activeSession"
    private let pendingSessionStorageKey = "gym.training.watch.pendingFinishedSession"
    private let restTimerEndStorageKey = "gym.training.watch.restTimerEnd"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var restEndsAt: Date?

    override init() {
        super.init()
        prepareUITestStateIfNeeded()
        loadSavedState()
        configureSession()
    }

    func startWorkout() {
        guard let selectedPlan else {
            statusMessage = "今日のメニューを選んでください"
            return
        }

        activeSession = WatchWorkoutSessionSnapshot(plan: selectedPlan)
        stopRestTimer()
        statusMessage = "\(selectedPlan.name) を開始しました"
        saveActiveSession()
    }

    func selectPlan(_ plan: WatchWorkoutPlanSnapshot) {
        guard plans.contains(where: { $0.id == plan.id }) else { return }
        selectedPlan = plan
        statusMessage = "\(plan.name) を選択しました"
    }

    func clearPlanSelection() {
        selectedPlan = nil
        statusMessage = "今日のメニューを選んでください"
    }

    func cancelWorkout() {
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        statusMessage = plans.isEmpty ? "iPhoneからメニューを同期してください" : "ワークアウトを破棄しました"
    }

    func startSet(exerciseID: UUID, setID: UUID) {
        stopRestTimer()
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard !set.isCompleted else { return }
            set.startedAt = set.startedAt ?? Date()
        }
    }

    func adjustWeight(exerciseID: UUID, setID: UUID, delta: Double) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
            set.actualWeight = max(0, min(999, set.actualWeight + delta))
        }
    }

    func adjustReps(exerciseID: UUID, setID: UUID, delta: Int) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
            set.actualReps = max(0, min(999, set.actualReps + delta))
        }
    }

    func updateRPE(exerciseID: UUID, setID: UUID, rpe: Double?) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
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
            if isCompleted {
                session.exercises[exerciseIndex].sets[setIndex].startedAt =
                    session.exercises[exerciseIndex].sets[setIndex].startedAt ?? Date()
            }
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = isCompleted
            session.exercises[exerciseIndex].sets[setIndex].completedAt = isCompleted ? Date() : nil
        }

        if isCompleted {
            startRestTimer(seconds: restSeconds)
        }
    }

    func tickRestTimer() {
        guard isRestTimerRunning else { return }
        guard refreshRestTimer() else { return }

        if restRemaining == 0 {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    func startRestTimer(seconds: Int? = nil) {
        let fallbackRest = activeSession?.exercises.first?.restSeconds ?? 90
        let nextRest = seconds ?? fallbackRest
        guard nextRest > 0 else {
            return
        }

        restEndsAt = Date().addingTimeInterval(TimeInterval(nextRest))
        restRemaining = nextRest
        isRestTimerRunning = true
        UserDefaults.standard.set(restEndsAt, forKey: restTimerEndStorageKey)
    }

    func adjustRestTimer(by seconds: Int) {
        guard let restEndsAt else { return }

        let adjustedEnd = restEndsAt.addingTimeInterval(TimeInterval(seconds))
        guard adjustedEnd > Date() else {
            stopRestTimer()
            return
        }

        self.restEndsAt = adjustedEnd
        UserDefaults.standard.set(adjustedEnd, forKey: restTimerEndStorageKey)
        refreshRestTimer()
    }

    func stopRestTimer() {
        restEndsAt = nil
        restRemaining = 0
        isRestTimerRunning = false
        UserDefaults.standard.removeObject(forKey: restTimerEndStorageKey)
    }

    func finishWorkout() {
        guard var finished = activeSession else {
            statusMessage = "完了するワークアウトがありません"
            return
        }

        finished.endedAt = Date()
        pendingFinishedSession = finished
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
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
        if let data = UserDefaults.standard.data(forKey: planLibraryStorageKey),
           let library = try? decoder.decode(WatchWorkoutPlanLibrarySnapshot.self, from: data) {
            plans = library.plans
            statusMessage = "同期済みメニューから選べます"
        } else if let data = UserDefaults.standard.data(forKey: planStorageKey),
                  let savedPlan = try? decoder.decode(WatchWorkoutPlanSnapshot.self, from: data) {
            plans = [savedPlan]
            savePlanLibrary()
            statusMessage = "同期済みメニューから選べます"
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

        restoreRestTimer()
    }

    private func prepareUITestStateIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard

        if arguments.contains("--reset-watch-ui-test-data") {
            defaults.removeObject(forKey: planStorageKey)
            defaults.removeObject(forKey: planLibraryStorageKey)
            defaults.removeObject(forKey: activeSessionStorageKey)
            defaults.removeObject(forKey: pendingSessionStorageKey)
            defaults.removeObject(forKey: restTimerEndStorageKey)
        }

        guard arguments.contains("--seed-watch-ui-test-plan"),
              let libraryData = try? encoder.encode(
                WatchWorkoutPlanLibrarySnapshot(plans: Self.uiTestPlans())
              ) else {
            return
        }

        defaults.set(libraryData, forKey: planLibraryStorageKey)
    }

    private static func uiTestPlans() -> [WatchWorkoutPlanSnapshot] {
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

        return [
            WatchWorkoutPlanSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
                name: "胸の日",
                weightUnit: .kg,
                exercises: [
                    WatchPlanExerciseSnapshot(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                        exerciseID: exerciseID,
                        name: "ベンチプレス",
                        primaryMuscleName: "胸",
                        primaryMuscleRawValue: "chest",
                        equipmentRawValue: "barbell",
                        restSeconds: 60,
                        sets: (1...3).map { setOrder in
                            WatchPlanSetTargetSnapshot(
                                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 200 + setOrder))!,
                                setOrder: setOrder,
                                targetWeight: 20,
                                targetReps: 10
                            )
                        }
                    )
                ]
            ),
            WatchWorkoutPlanSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000300")!,
                name: "背中の日",
                weightUnit: .kg,
                exercises: [
                    WatchPlanExerciseSnapshot(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                        exerciseID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                        name: "ラットプルダウン",
                        primaryMuscleName: "背中",
                        primaryMuscleRawValue: "back",
                        equipmentRawValue: "machine",
                        restSeconds: 75,
                        sets: (1...3).map { setOrder in
                            WatchPlanSetTargetSnapshot(
                                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 400 + setOrder))!,
                                setOrder: setOrder,
                                targetWeight: 30,
                                targetReps: 12
                            )
                        }
                    )
                ]
            )
        ]
    }

    private func apply(plans snapshots: [WatchWorkoutPlanSnapshot], data: Data? = nil) {
        plans = snapshots
        selectedPlan = nil
        statusMessage = "\(snapshots.count)件のメニューを同期しました"

        if let data {
            UserDefaults.standard.set(data, forKey: planLibraryStorageKey)
        } else {
            savePlanLibrary()
        }

        UserDefaults.standard.removeObject(forKey: planStorageKey)
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

    private func savePlanLibrary() {
        guard let data = try? encoder.encode(WatchWorkoutPlanLibrarySnapshot(plans: plans)) else {
            return
        }

        UserDefaults.standard.set(data, forKey: planLibraryStorageKey)
    }

    @discardableResult
    private func refreshRestTimer(now: Date = Date()) -> Bool {
        guard let restEndsAt else {
            stopRestTimer()
            return false
        }

        let remaining = max(0, Int(ceil(restEndsAt.timeIntervalSince(now))))
        restRemaining = remaining

        if remaining == 0 {
            stopRestTimer()
            return true
        }

        isRestTimerRunning = true
        return true
    }

    private func restoreRestTimer() {
        guard activeSession != nil,
              let savedEnd = UserDefaults.standard.object(forKey: restTimerEndStorageKey) as? Date,
              savedEnd > Date() else {
            UserDefaults.standard.removeObject(forKey: restTimerEndStorageKey)
            return
        }

        restEndsAt = savedEnd
        refreshRestTimer()
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
                sendImmediately(message: message, title: finishedSession.title, session: session)
            } else {
                session.transferUserInfo(message)
                statusMessage = "\(finishedSession.title) はiPhoneへ送信予約しました"
            }
        } catch {
            statusMessage = "iPhoneへ送る記録データを作れませんでした"
        }
    }

    @discardableResult
    private nonisolated func receive(userInfo: [String: Any]) -> Bool {
        guard let messageType = userInfo[WatchWorkoutTransfer.messageTypeKey] as? String,
              let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else {
            return false
        }

        switch messageType {
        case WatchWorkoutTransfer.planLibraryPushType:
            guard let library = try? JSONDecoder().decode(WatchWorkoutPlanLibrarySnapshot.self, from: data) else {
                updateStatus("メニューデータを読み込めませんでした")
                return false
            }

            Task { @MainActor [weak self] in
                self?.apply(plans: library.plans, data: data)
            }
            return true

        case WatchWorkoutTransfer.planPushType:
            guard let snapshot = try? JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data) else {
                updateStatus("メニューデータを読み込めませんでした")
                return false
            }

            Task { @MainActor [weak self] in
                self?.apply(plans: [snapshot])
            }
            return true

        default:
            return false
        }
    }

    private nonisolated func updateStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.statusMessage = message
        }
    }

    private nonisolated func sendImmediately(
        message: [String: Any],
        title: String,
        session: WCSession
    ) {
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let acknowledged = reply[WatchWorkoutTransfer.acknowledgementKey] as? Bool ?? true
            self?.updateSendResult(
                acknowledged: acknowledged,
                successMessage: "\(title) をiPhone履歴へ保存しました"
            )
        }, errorHandler: { [weak self] error in
            session.transferUserInfo(message)
            self?.updateStatus("\(title) はiPhoneへ送信予約しました")
            NSLog("Watch workout result immediate send failed: \(error.localizedDescription)")
        })
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
                guard self?.pendingFinishedSession != nil else { return }
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

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let accepted = receive(userInfo: message)
        replyHandler([WatchWorkoutTransfer.acknowledgementKey: accepted])
    }
}
