import Foundation
@preconcurrency import WatchConnectivity

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
