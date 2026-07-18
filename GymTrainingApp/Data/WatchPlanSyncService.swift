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
                "Apple Watchへ今日の計画を送れます"
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

    func send(plan: TrainingPlan, weightUnit: WeightUnit) {
        guard let session else {
            state = .unavailable("この端末ではApple Watch連携を利用できません")
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
            state = .unavailable("Apple Watch側にGym Trainingをインストールしてください")
            return
        }

        let snapshot = WatchWorkoutPlanSnapshot(plan: plan, weightUnit: weightUnit)

        do {
            let payload = try JSONEncoder().encode(snapshot)
            let message: [String: Any] = [
                WatchWorkoutTransfer.messageTypeKey: WatchWorkoutTransfer.planPushType,
                WatchWorkoutTransfer.payloadKey: payload,
                WatchWorkoutTransfer.eventIDKey: UUID().uuidString,
                WatchWorkoutTransfer.sentAtKey: Date()
            ]

            state = .sending("\(plan.name) をApple Watchへ送信中")

            if session.isReachable {
                session.sendMessage(message, replyHandler: { [weak self] _ in
                    self?.updateState(.sent("\(plan.name) をApple Watchへ送信しました"))
                }, errorHandler: { [weak self] error in
                    session.transferUserInfo(message)
                    self?.updateState(.sent("Apple Watchが近くにないため、次回起動時に届くよう予約しました"))
                    NSLog("Watch immediate send failed: \(error.localizedDescription)")
                })
            } else {
                session.transferUserInfo(message)
                state = .sent("Apple Watchが近くにないため、次回起動時に届くよう予約しました")
            }
        } catch {
            state = .failed("Apple Watch用の計画データを作れませんでした")
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
            state = .received("\(workoutSession.title) をApple Watchから履歴に保存しました")
            return true
        } catch {
            state = .failed("Apple Watchの記録を読み込めませんでした")
            NSLog("Watch session decode failed: \(error.localizedDescription)")
            return false
        }
    }

    private nonisolated func receive(userInfo: [String: Any]) {
        guard userInfo[WatchWorkoutTransfer.messageTypeKey] as? String == WatchWorkoutTransfer.sessionFinishedType,
              let payload = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else {
            return
        }

        Task { @MainActor [weak self] in
            self?.saveFinishedWatchSession(payload: payload)
        }
    }

    private nonisolated func receive(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchWorkoutTransfer.messageTypeKey] as? String == WatchWorkoutTransfer.sessionFinishedType,
              let payload = message[WatchWorkoutTransfer.payloadKey] as? Data else {
            replyHandler([WatchWorkoutTransfer.acknowledgementKey: false])
            return
        }

        guard (try? JSONDecoder().decode(WatchWorkoutSessionSnapshot.self, from: payload)) != nil else {
            replyHandler([WatchWorkoutTransfer.acknowledgementKey: false])
            return
        }

        Task { @MainActor [weak self] in
            self?.saveFinishedWatchSession(payload: payload)
        }
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
                updateState(.ready("Apple Watchへ計画を送信できます"))
            } else if session.isPaired {
                updateState(.unavailable("Apple Watch側にGym Trainingをインストールしてください"))
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
