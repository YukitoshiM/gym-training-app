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
            return L10n.string("training.e99c824f7ff9", fallback: "{{value1}} {{value2}} → {{value3}}（{{value4}}セット）", values: [String(describing: exerciseName), String(describing: previousWeight), String(describing: proposedWeight), String(describing: exerciseChanges.count)])
        }
        return L10n.string("training.a55517b0b274", fallback: "{{value1}}の目標重量を更新します。\n{{value2}}", values: [planName, summaries.joined(separator: "\n")])
    }
}

enum WatchFinishedSessionPersistenceResult: Equatable {
    case saved
    case duplicate
    case failed

    var canAcknowledge: Bool {
        switch self {
        case .saved, .duplicate:
            true
        case .failed:
            false
        }
    }
}

struct PendingWorkoutSyncConflict: Identifiable, Equatable {
    var id: UUID { mergedSession.id }
    var mergedSession: WorkoutSession
    var watchSession: WorkoutSession
    var conflictingSetIDs: [UUID]
    var watchUpdatedAt: Date
    var restTimerEndAt: Date?
    var restExerciseID: UUID?
}

enum WatchFinishedSessionPersistenceVerifier {
    static func persist(
        _ session: WorkoutSession,
        loadPersistedSessions: () -> [WorkoutSession],
        save: () -> Void
    ) -> WatchFinishedSessionPersistenceResult {
        if loadPersistedSessions().contains(where: { $0.id == session.id }) {
            return .duplicate
        }

        save()
        return loadPersistedSessions().contains(where: { $0.id == session.id })
            ? .saved
            : .failed
    }
}

private struct WatchConnectivityReplyHandler: @unchecked Sendable {
    let value: ([String: Any]) -> Void

    func callAsFunction(_ reply: [String: Any]) {
        value(reply)
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
                L10n.string("training.89eea2d0eb23", fallback: "Apple Watchへメニューを同期できます")
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
    @Published private(set) var pendingWorkoutSyncConflict: PendingWorkoutSyncConflict?
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
        state = .received(L10n.string("training.7544024a8347", fallback: "{{value1}}の目標重量を更新しました", values: [String(describing: plan.name)]))
    }

    func declinePlanWeightUpdateSuggestion() {
        pendingPlanWeightUpdateSuggestion = nil
    }

    func resolveWorkoutSyncConflict(preferWatch: Bool) {
        guard let conflict = pendingWorkoutSyncConflict, let appStore else { return }
        var resolved = conflict.mergedSession
        if preferWatch {
            for exerciseIndex in resolved.exercises.indices {
                for setIndex in resolved.exercises[exerciseIndex].sets.indices {
                    let setID = resolved.exercises[exerciseIndex].sets[setIndex].id
                    guard conflict.conflictingSetIDs.contains(setID),
                          let watchSet = conflict.watchSession.exercises
                            .flatMap(\.sets)
                            .first(where: { $0.id == setID }) else { continue }
                    resolved.exercises[exerciseIndex].sets[setIndex] = watchSet
                }
            }
        }
        appStore.updateActiveWorkout(
            resolved,
            restTimerEndAt: conflict.restTimerEndAt,
            restExerciseID: conflict.restExerciseID
        )
        appStore.setActiveWorkoutState(.active)
        pendingWorkoutSyncConflict = nil
    }

    func send(
        plans: [TrainingPlan],
        profile: UserProfile,
        sensorSettings: SensorSettings,
        appearanceSettings: AppAppearanceSettings,
        preferredPlanID: UUID?,
        dailyRecommendation: DailyRecommendation? = nil
    ) {
        guard let session else {
            state = .unavailable(L10n.string("training.5201136a12ab", fallback: "この端末ではApple Watch連携を利用できません"))
            return
        }

        guard !plans.isEmpty || dailyRecommendation != nil else {
            state = .failed(L10n.string("training.47e7e8577809", fallback: "Apple Watchへ同期する今日の内容がありません"))
            return
        }

        guard session.activationState == .activated else {
            state = .failed(L10n.string("training.6c7e2e66ae07", fallback: "Apple Watch接続を準備中です。少し待ってからもう一度送信してください"))
            session.activate()
            return
        }

        guard session.isPaired else {
            state = .unavailable(L10n.string("training.0c4f0b55fb09", fallback: "ペアリングされたApple Watchが見つかりません"))
            return
        }

        guard session.isWatchAppInstalled else {
            state = .unavailable(L10n.string("training.ffff1775646c", fallback: "Apple Watch側にBodyModeをインストールしてください"))
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
            appearanceSettings: appearanceSettings,
            dailyRecommendation: dailyRecommendation.map(WatchDailyRecommendationSnapshot.init)
        )

        do {
            let payload = try JSONEncoder().encode(library)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.planLibraryPushType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ]

            state = .sending(L10n.string("training.ee48ec2b9299", fallback: "今日の内容をApple Watchへ同期中"))

            if session.isReachable {
                sendImmediately(
                    message: message,
                    menuCount: plans.count,
                    includesDailyRecommendation: dailyRecommendation != nil,
                    session: session
                )
            } else {
                session.transferUserInfo(message)
                state = .sent(L10n.string("training.2592d4be6d03", fallback: "Apple Watchが近くにないため、次回起動時に届くよう予約しました"))
            }
        } catch {
            state = .failed(L10n.string("training.937ac541fc5f", fallback: "Apple Watch用のメニューデータを作れませんでした"))
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.plan.encode",
                message: "Failed to encode Watch plan library"
            )
        }
    }

    func syncDailyRecommendationIfPossible(
        plans: [TrainingPlan],
        profile: UserProfile,
        sensorSettings: SensorSettings,
        appearanceSettings: AppAppearanceSettings,
        recommendation: DailyRecommendation
    ) {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return
        }
        send(
            plans: plans,
            profile: profile,
            sensorSettings: sensorSettings,
            appearanceSettings: appearanceSettings,
            preferredPlanID: recommendation.activeActions.compactMap { action -> UUID? in
                if case .workout(let planID) = action.destination { return planID }
                return nil
            }.first ?? appStore?.todayPlan?.id,
            dailyRecommendation: recommendation
        )
    }

    func send(command: WatchWorkoutCommand) {
        guard let session else {
            state = .unavailable(L10n.string("training.5201136a12ab", fallback: "この端末ではApple Watch連携を利用できません"))
            return
        }
        guard session.activationState == .activated, session.isReachable else {
            state = .failed(L10n.string("training.031d2e49c1b3", fallback: "Apple Watchを開いてから、もう一度操作してください"))
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
            state = .failed(L10n.string("training.63cb88f01990", fallback: "Apple Watchへ送る操作データを作れませんでした"))
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.command.encode",
                message: "Failed to encode Watch workout command"
            )
        }
    }

    private func configureSession() {
        guard let session else {
            state = .unavailable(L10n.string("training.5201136a12ab", fallback: "この端末ではApple Watch連携を利用できません"))
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
        includesDailyRecommendation: Bool,
        session: WCSession
    ) {
        session.sendMessage(message, replyHandler: { [weak self] _ in
            let message = if menuCount == 0, includesDailyRecommendation {
                L10n.string("training.fb1b356d17a5", fallback: "今日の内容をApple Watchへ同期しました")
            } else {
                L10n.string("training.81ce6b4b29d6", fallback: "{{value1}}件のメニューをApple Watchへ同期しました", values: [String(describing: menuCount)])
            }
            self?.updateState(.sent(message))
        }, errorHandler: { [weak self] error in
            session.transferUserInfo(message)
            self?.updateState(.sent(L10n.string("training.2592d4be6d03", fallback: "Apple Watchが近くにないため、次回起動時に届くよう予約しました")))
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
                self?.updateState(.failed(L10n.string("training.6fb962f9cfaa", fallback: "Apple Watchで操作を実行できませんでした")))
            }
        }, errorHandler: { [weak self] error in
            self?.updateState(.failed(L10n.string("training.3ae842776ce3", fallback: "Apple Watchへ操作を送れませんでした")))
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.command.send",
                message: "Failed to send Watch workout command: \(action.rawValue)"
            )
        })
    }

    @discardableResult
    private func saveFinishedWatchSession(
        _ watchSession: WatchWorkoutSessionSnapshot
    ) -> WatchFinishedSessionPersistenceResult {
        guard let appStore else {
            state = .failed(L10n.string("training.e5c5dcd8769a", fallback: "Apple Watchの記録を保存する準備ができていません"))
            return .failed
        }

        var workoutSession = WorkoutSession(watchSession: watchSession)
        workoutSession.endedAt = workoutSession.endedAt ?? Date()
        workoutSession.watchSyncState = .received
        let result = WatchFinishedSessionPersistenceVerifier.persist(
            workoutSession,
            loadPersistedSessions: { appStore.storage.loadWorkoutHistory() },
            save: { appStore.saveWorkoutHistorySession(workoutSession) }
        )

        switch result {
        case .saved:
            pendingPlanWeightUpdateSuggestion = makePlanWeightUpdateSuggestion(
                for: watchSession,
                appStore: appStore
            )
            liveWatchWorkout = nil
            state = .received(L10n.string("training.2501e04e6ece", fallback: "{{value1}} をApple Watchから履歴に保存しました", values: [String(describing: workoutSession.title)]))
        case .duplicate:
            appStore.workoutHistory = appStore.storage.loadWorkoutHistory()
            liveWatchWorkout = nil
            state = .received(L10n.string("training.c16d54ec55fa", fallback: "{{value1}} はiPhone履歴に保存済みです", values: [String(describing: workoutSession.title)]))
            AppDiagnostics.shared.record(
                level: "info",
                category: "watch.session.duplicate",
                message: "Confirmed duplicate Watch workout in durable storage",
                metadata: ["session_id": workoutSession.id.uuidString]
            )
        case .failed:
            appStore.workoutHistory = appStore.storage.loadWorkoutHistory()
            state = .failed(L10n.string("training.bd776f26c0ae", fallback: "Apple Watchの記録をiPhoneへ保存できませんでした"))
            AppDiagnostics.shared.record(
                level: "error",
                category: "watch.session.persist",
                message: "Finished Watch workout was not present after persistence",
                metadata: ["session_id": workoutSession.id.uuidString]
            )
        }
        return result
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
            guard let payload = userInfo[WatchWorkoutTransfer.payloadKey] as? Data,
                  let watchSession = try? JSONDecoder().decode(
                    WatchWorkoutSessionSnapshot.self,
                    from: payload
                  ) else {
                updateState(.failed(L10n.string("training.315ad87fb453", fallback: "Apple Watchの記録を読み込めませんでした")))
                return
            }
            Task { @MainActor [weak self] in
                self?.saveFinishedWatchSession(watchSession)
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
                    mergeLiveWatchWorkout(snapshot)
                }
            }
        case WatchWorkoutTransfer.sessionLiveEndedType:
            Task { @MainActor [weak self] in
                self?.liveWatchWorkout = nil
            }
        case WatchWorkoutTransfer.diagnosticsBatchType:
            guard let payload = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else { return }
            do {
                let events = try JSONDecoder().decode([WatchDiagnosticEvent].self, from: payload)
                AppDiagnostics.shared.importWatchEvents(events)
                AppDiagnostics.shared.record(
                    level: "info",
                    category: "watch.diagnostics.import",
                    message: "Imported Apple Watch diagnostic events",
                    metadata: ["event_count": String(events.count)]
                )
            } catch {
                AppDiagnostics.shared.record(
                    error: error,
                    category: "watch.diagnostics.decode",
                    message: "Failed to decode Apple Watch diagnostic events"
                )
            }
        default:
            break
        }
    }

    private func mergeLiveWatchWorkout(_ snapshot: WatchLiveWorkoutSnapshot) {
        guard let appStore else { return }
        let incoming = WorkoutSession(watchSession: snapshot.session)
        let restEndAt = snapshot.isRestTimerRunning
            ? snapshot.updatedAt.addingTimeInterval(TimeInterval(max(0, snapshot.restRemaining)))
            : nil
        guard let local = appStore.activeWorkoutSession else {
            _ = appStore.beginOrResumeWorkout(incoming)
            appStore.updateActiveWorkout(
                incoming,
                restTimerEndAt: restEndAt,
                restExerciseID: snapshot.restExerciseID
            )
            appStore.setActiveWorkoutState(.active)
            return
        }
        let result = WorkoutSessionConflictResolver.merge(
            local: local,
            incoming: incoming,
            incomingUpdatedAt: snapshot.updatedAt
        )
        switch result.disposition {
        case .separateSession:
            return
        case .merged:
            appStore.updateActiveWorkout(
                result.session,
                restTimerEndAt: restEndAt,
                restExerciseID: snapshot.restExerciseID
            )
            appStore.setActiveWorkoutState(.active)
        case .conflict:
            pendingWorkoutSyncConflict = PendingWorkoutSyncConflict(
                mergedSession: result.session,
                watchSession: incoming,
                conflictingSetIDs: result.conflictingSetIDs,
                watchUpdatedAt: snapshot.updatedAt,
                restTimerEndAt: restEndAt,
                restExerciseID: snapshot.restExerciseID
            )
        }
    }

    private nonisolated func receive(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = WatchConnectivityReplyHandler(value: replyHandler)
        guard let messageType = message[WatchWorkoutTransfer.messageTypeKey] as? String else {
            reply([WatchWorkoutTransfer.acknowledgementKey: false])
            return
        }

        if messageType == WatchWorkoutTransfer.sessionFinishedType {
            guard let payload = message[WatchWorkoutTransfer.payloadKey] as? Data,
                  let watchSession = try? JSONDecoder().decode(
                    WatchWorkoutSessionSnapshot.self,
                    from: payload
                  ) else {
                reply(WatchWorkoutTransfer.acknowledgement(accepted: false))
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    reply(WatchWorkoutTransfer.acknowledgement(
                        accepted: false,
                        sessionID: watchSession.id
                    ))
                    return
                }
                let result = saveFinishedWatchSession(watchSession)
                reply(WatchWorkoutTransfer.acknowledgement(
                    accepted: result.canAcknowledge,
                    sessionID: watchSession.id
                ))
            }
            return
        } else if messageType == WatchWorkoutTransfer.diagnosticsBatchType {
            guard let payload = message[WatchWorkoutTransfer.payloadKey] as? Data,
                  (try? JSONDecoder().decode([WatchDiagnosticEvent].self, from: payload)) != nil else {
                reply([WatchWorkoutTransfer.acknowledgementKey: false])
                return
            }
        }
        receive(userInfo: message)
        reply([WatchWorkoutTransfer.acknowledgementKey: true])
    }
}

extension WatchPlanSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            AppDiagnostics.shared.record(
                error: error,
                category: "watch.connectivity.activation",
                message: "Apple Watch connectivity activation failed"
            )
            updateState(.failed(L10n.string("training.0ed25fb12cc9", fallback: "Apple Watch接続に失敗しました: {{value1}}", values: [String(describing: error.localizedDescription)])))
            return
        }

        switch activationState {
        case .activated:
            AppDiagnostics.shared.record(
                level: "info",
                category: "watch.connectivity.activation",
                message: "Apple Watch connectivity activated",
                metadata: [
                    "paired": String(session.isPaired),
                    "watch_app_installed": String(session.isWatchAppInstalled)
                ]
            )
            if session.isPaired && session.isWatchAppInstalled {
                updateState(.ready(L10n.string("training.89eea2d0eb23", fallback: "Apple Watchへメニューを同期できます")))
            } else if session.isPaired {
                updateState(.unavailable(L10n.string("training.ffff1775646c", fallback: "Apple Watch側にBodyModeをインストールしてください")))
            } else {
                updateState(.unavailable(L10n.string("training.0c4f0b55fb09", fallback: "ペアリングされたApple Watchが見つかりません")))
            }
        case .inactive:
            updateState(.unavailable(L10n.string("training.e55f47a9e83d", fallback: "Apple Watch接続が一時停止しています")))
        case .notActivated:
            updateState(.unavailable(L10n.string("training.ccbfd895aa76", fallback: "Apple Watch接続が未準備です")))
        @unknown default:
            updateState(.unavailable(L10n.string("training.9d376a20015f", fallback: "Apple Watch接続状態を確認できません")))
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
