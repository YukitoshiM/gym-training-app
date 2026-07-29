import Foundation
@preconcurrency import WatchConnectivity

struct PlanWeightUpdateSuggestion: Identifiable, Equatable {
    struct Change: Identifiable, Equatable {
        let planExerciseID: UUID
        let exerciseName: String
        let setOrder: Int
        let previousWeight: Double
        let proposedWeight: Double

        var id: String {
            "\(planExerciseID.uuidString)-\(setOrder)"
        }
    }

    let id = UUID()
    let planID: UUID
    let planName: String
    let unit: WeightUnit
    let changes: [Change]

    var message: String {
        let groupedChanges = Dictionary(grouping: changes, by: \.exerciseName)
        let summaries = groupedChanges.keys.sorted().compactMap { exerciseName -> String? in
            guard let exerciseChanges = groupedChanges[exerciseName],
                  let latestChange = exerciseChanges.max(by: { $0.setOrder < $1.setOrder }) else {
                return nil
            }
            let previousWeight = AppFormatters.weight(
                latestChange.previousWeight,
                unit: unit
            )
            let proposedWeight = AppFormatters.weight(
                latestChange.proposedWeight,
                unit: unit
            )
            return "\(exerciseName) \(previousWeight) → \(proposedWeight)（\(exerciseChanges.count)セット）"
        }
        return "\(planName)の目標重量を更新します。\n\(summaries.joined(separator: "\n"))"
    }
}

@MainActor
final class WatchPlanSyncService: NSObject, ObservableObject {
    enum SyncState: Equatable, Sendable {
        case idle
        case unavailable(String)
        case ready(String)
        case sending(String)
        case sent(String)
        case received(String)
        case failed(String)

        var message: String {
            switch self {
            case .idle:
                "Apple Watchへメニューを同期できます"
            case .unavailable(let message),
                 .ready(let message),
                 .sending(let message),
                 .sent(let message),
                 .received(let message),
                 .failed(let message):
                message
            }
        }

        var systemImage: String {
            switch self {
            case .idle: "applewatch"
            case .unavailable: "applewatch.slash"
            case .ready: "checkmark.circle"
            case .sending: "arrow.triangle.2.circlepath"
            case .sent: "checkmark.circle.fill"
            case .received: "tray.and.arrow.down.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var liveWatchWorkout: WatchLiveWorkoutSnapshot?
    @Published private(set) var pendingPlanWeightUpdateSuggestion: PlanWeightUpdateSuggestion?
    private weak var appStore: AppStore?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    override init() {
        super.init()
        configureSession()
    }

    func bind(appStore: AppStore) {
        self.appStore = appStore

        guard ProcessInfo.processInfo.arguments.contains("--seed-watch-plan-weight-suggestion"),
              pendingPlanWeightUpdateSuggestion == nil,
              let plan = appStore.plans.first else {
            return
        }
        let watchPlan = WatchWorkoutPlanSnapshot(
            plan: plan,
            weightUnit: appStore.userProfile.weightUnit
        )
        var watchSession = WatchWorkoutSessionSnapshot(plan: watchPlan)
        if !watchSession.exercises.isEmpty, !watchSession.exercises[0].sets.isEmpty {
            watchSession.exercises[0].sets[0].actualWeight += 2.5
            watchSession.exercises[0].sets[0].actualReps =
                watchSession.exercises[0].sets[0].targetReps
            watchSession.exercises[0].sets[0].isCompleted = true
            pendingPlanWeightUpdateSuggestion = makePlanWeightUpdateSuggestion(
                for: watchSession,
                appStore: appStore
            )
        }
    }

    func acceptPlanWeightUpdateSuggestion() {
        guard let suggestion = pendingPlanWeightUpdateSuggestion,
              let appStore,
              var plan = appStore.plans.first(where: { $0.id == suggestion.planID }) else {
            pendingPlanWeightUpdateSuggestion = nil
            return
        }

        for change in suggestion.changes {
            guard let exerciseIndex = plan.exercises.firstIndex(where: {
                $0.id == change.planExerciseID
            }),
                  let setIndex = plan.exercises[exerciseIndex].sets.firstIndex(where: {
                      $0.setOrder == change.setOrder
                  }) else {
                continue
            }
            plan.exercises[exerciseIndex].sets[setIndex].targetWeight = change.proposedWeight
        }

        appStore.savePlan(plan)
        pendingPlanWeightUpdateSuggestion = nil
        state = .received("\(plan.name)の目標重量を更新しました")
    }

    func declinePlanWeightUpdateSuggestion() {
        pendingPlanWeightUpdateSuggestion = nil
    }

    func send(
        plans: [TrainingPlan],
        profile: UserProfile,
        sensorSettings: SensorSettings,
        appearanceSettings: AppAppearanceSettings,
        preferredPlanID: UUID?
    ) {
        guard let session else {
            state = .unavailable("この端末ではApple Watch連携を利用できません")
            return
        }

        guard !plans.isEmpty else {
            state = .failed("Apple Watchへ同期するメニューがありません")
            return
        }

        guard session.activationState == .activated else {
            state = .failed("Apple Watch接続を準備中です。少し待ってからもう一度送信してください")
            session.activate()
            return
        }

        guard session.isPaired else {
            state = .unavailable("ペアリングされたApple Watchが見つかりません")
            return
        }

        guard session.isWatchAppInstalled else {
            state = .unavailable("Apple Watch側にBodyModeをインストールしてください")
            return
        }

        let library = WatchWorkoutPlanLibrarySnapshot(
            plans: plans.map { plan in
                WatchWorkoutPlanSnapshot(plan: plan, weightUnit: profile.weightUnit) { exercise in
                    self.appStore?.latestCompletedExercise(for: exercise)
                }
            },
            preferredPlanID: preferredPlanID,
            userProfile: WatchUserProfileSnapshot(
                birthYear: profile.birthYear,
                goalTypeRawValue: profile.goalType.rawValue
            ),
            sensorPreferences: WatchSensorPreferences(
                healthWorkoutEnabled: sensorSettings.healthIntegrationEnabled,
                motionRepDetectionEnabled: sensorSettings.motionRepDetectionEnabled,
                adaptiveRestEnabled: sensorSettings.adaptiveRestEnabled,
                hapticCoachingEnabled: sensorSettings.hapticCoachingEnabled,
                reducedSensorSamplingEnabled: sensorSettings.reducedSensorSamplingEnabled
            ),
            appearanceSettings: appearanceSettings
        )

        do {
            let payload = try JSONEncoder().encode(library)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.planLibraryPushType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ]

            state = .sending("\(plans.count)件のメニューをApple Watchへ同期中")

            if session.isReachable {
                sendImmediately(message: message, menuCount: plans.count, session: session)
            } else {
                session.transferUserInfo(message)
                state = .sent("Apple Watchが近くにないため、次回起動時に届くよう予約しました")
            }
        } catch {
            state = .failed("Apple Watch用のメニューデータを作れませんでした")
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.plan.encode",
                message: "Failed to encode Watch plan library"
            )
        }
    }

    func send(command: WatchWorkoutCommand) {
        guard let session else {
            state = .unavailable("この端末ではApple Watch連携を利用できません")
            return
        }
        guard session.activationState == .activated, session.isReachable else {
            state = .failed("Apple Watchを開いてから、もう一度操作してください")
            return
        }

        do {
            let payload = try JSONEncoder().encode(command)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.workoutCommandType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ]
            sendCommandImmediately(message: message, action: command.action, session: session)
        } catch {
            state = .failed("Apple Watchへ送る操作データを作れませんでした")
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.command.encode",
                message: "Failed to encode Watch workout command"
            )
        }
    }

    private func configureSession() {
        guard let session else {
            state = .unavailable("この端末ではApple Watch連携を利用できません")
            return
        }

        session.delegate = self
        session.activate()
    }

    private nonisolated func updateState(_ state: SyncState) {
        Task { @MainActor [weak self] in
            self?.state = state
        }
    }

    private nonisolated func sendImmediately(
        message: [String: Any],
        menuCount: Int,
        session: WCSession
    ) {
        session.sendMessage(message, replyHandler: { [weak self] _ in
            self?.updateState(.sent("\(menuCount)件のメニューをApple Watchへ同期しました"))
        }, errorHandler: { [weak self] error in
            session.transferUserInfo(message)
            self?.updateState(.sent("Apple Watchが近くにないため、次回起動時に届くよう予約しました"))
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.plan.send",
                message: "Immediate Watch plan transfer failed; queued user info"
            )
        })
    }

    private nonisolated func sendCommandImmediately(
        message: [String: Any],
        action: WatchWorkoutCommandAction,
        session: WCSession
    ) {
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let acknowledged = reply[WatchWorkoutTransfer.acknowledgementKey] as? Bool ?? true
            if !acknowledged {
                self?.updateState(.failed("Apple Watchで操作を実行できませんでした"))
            }
        }, errorHandler: { [weak self] error in
            self?.updateState(.failed("Apple Watchへ操作を送れませんでした"))
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.command.send",
                message: "Failed to send Watch workout command: \(action.rawValue)"
            )
        })
    }

    @discardableResult
    private func saveFinishedWatchSession(payload: Data) -> Bool {
        guard let appStore else {
            state = .failed("Apple Watchの記録を保存する準備ができていません")
            return false
        }

        do {
            let watchSession = try JSONDecoder().decode(WatchWorkoutSessionSnapshot.self, from: payload)
            var workoutSession = WorkoutSession(watchSession: watchSession)
            workoutSession.endedAt = workoutSession.endedAt ?? Date()
            workoutSession.watchSyncState = .received
            appStore.saveWorkoutHistorySession(workoutSession)
            pendingPlanWeightUpdateSuggestion = makePlanWeightUpdateSuggestion(
                for: watchSession,
                appStore: appStore
            )
            liveWatchWorkout = nil
            state = .received("\(workoutSession.title) をApple Watchから履歴に保存しました")
            return true
        } catch {
            state = .failed("Apple Watchの記録を読み込めませんでした")
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.session.decode",
                message: "Failed to decode finished Watch workout"
            )
            return false
        }
    }

    private func makePlanWeightUpdateSuggestion(
        for watchSession: WatchWorkoutSessionSnapshot,
        appStore: AppStore
    ) -> PlanWeightUpdateSuggestion? {
        guard let sourcePlanID = watchSession.sourcePlanID,
              let plan = appStore.plans.first(where: { $0.id == sourcePlanID }) else {
            return nil
        }

        var changes: [PlanWeightUpdateSuggestion.Change] = []

        for watchExercise in watchSession.exercises {
            guard let planExercise = plan.exercises.first(where: {
                $0.id == watchExercise.planExerciseID
                    || ($0.exercise.id == watchExercise.exerciseID && watchExercise.exerciseID != nil)
            }) else {
                continue
            }

            for watchSet in watchExercise.sets
            where watchSet.isCompleted
                && watchSet.actualReps >= watchSet.targetReps
                && abs(watchSet.actualWeight - watchSet.targetWeight) >= 0.05 {
                guard let planSet = planExercise.sets.first(where: {
                    $0.setOrder == watchSet.setOrder
                }),
                      abs(planSet.targetWeight - watchSet.actualWeight) >= 0.05 else {
                    continue
                }
                changes.append(
                    PlanWeightUpdateSuggestion.Change(
                        planExerciseID: planExercise.id,
                        exerciseName: planExercise.exercise.name,
                        setOrder: planSet.setOrder,
                        previousWeight: planSet.targetWeight,
                        proposedWeight: watchSet.actualWeight
                    )
                )
            }
        }

        guard !changes.isEmpty else { return nil }
        return PlanWeightUpdateSuggestion(
            planID: plan.id,
            planName: plan.name,
            unit: appStore.userProfile.weightUnit,
            changes: changes
        )
    }

    private nonisolated func receive(userInfo: [String: Any]) {
        guard let messageType = userInfo[WatchWorkoutTransfer.messageTypeKey] as? String else {
            return
        }

        switch messageType {
        case WatchWorkoutTransfer.sessionFinishedType:
            guard let payload = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else { return }
            Task { @MainActor [weak self] in
                self?.saveFinishedWatchSession(payload: payload)
            }
        case WatchWorkoutTransfer.sessionLiveUpdateType:
            guard let payload = userInfo[WatchWorkoutTransfer.payloadKey] as? Data,
                  let snapshot = try? JSONDecoder().decode(WatchLiveWorkoutSnapshot.self, from: payload) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if liveWatchWorkout?.updatedAt ?? .distantPast <= snapshot.updatedAt {
                    liveWatchWorkout = snapshot
                }
            }
        case WatchWorkoutTransfer.sessionLiveEndedType:
            Task { @MainActor [weak self] in
                self?.liveWatchWorkout = nil
            }
        default:
            break
        }
    }

    private nonisolated func receive(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let messageType = message[WatchWorkoutTransfer.messageTypeKey] as? String else {
            replyHandler([WatchWorkoutTransfer.acknowledgementKey: false])
            return
        }

        if messageType == WatchWorkoutTransfer.sessionFinishedType {
            guard let payload = message[WatchWorkoutTransfer.payloadKey] as? Data,
                  (try? JSONDecoder().decode(WatchWorkoutSessionSnapshot.self, from: payload)) != nil else {
                replyHandler([WatchWorkoutTransfer.acknowledgementKey: false])
                return
            }
        }
        receive(userInfo: message)
        replyHandler([WatchWorkoutTransfer.acknowledgementKey: true])
    }
}

extension WatchPlanSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            updateState(.failed("Apple Watch接続に失敗しました: \(error.localizedDescription)"))
            return
        }

        switch activationState {
        case .activated:
            if session.isPaired && session.isWatchAppInstalled {
                updateState(.ready("Apple Watchへメニューを同期できます"))
            } else if session.isPaired {
                updateState(.unavailable("Apple Watch側にBodyModeをインストールしてください"))
            } else {
                updateState(.unavailable("ペアリングされたApple Watchが見つかりません"))
            }
        case .inactive:
            updateState(.unavailable("Apple Watch接続が一時停止しています"))
        case .notActivated:
            updateState(.unavailable("Apple Watch接続が未準備です"))
        @unknown default:
            updateState(.unavailable("Apple Watch接続状態を確認できません"))
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
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
        receive(message: message, replyHandler: replyHandler)
    }
}
