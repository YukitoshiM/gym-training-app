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
        case failed(String)

        var message: String {
            switch self {
            case .idle:
                "Apple Watchへ今日の計画を送れます"
            case .unavailable(let message),
                 .ready(let message),
                 .sending(let message),
                 .sent(let message),
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
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    @Published private(set) var state: SyncState = .idle

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    override init() {
        super.init()
        configureSession()
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
}
