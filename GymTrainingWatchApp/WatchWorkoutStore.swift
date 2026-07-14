import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published private(set) var plan: WatchWorkoutPlanSnapshot?
    @Published private(set) var statusMessage = "iPhoneから今日の計画を送信してください"

    private let planStorageKey = "gym.training.watch.currentPlan"

    override init() {
        super.init()
        loadSavedPlan()
        configureSession()
    }

    private func configureSession() {
        guard WCSession.isSupported() else {
            statusMessage = "このWatchでは連携を利用できません"
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func loadSavedPlan() {
        guard let data = UserDefaults.standard.data(forKey: planStorageKey),
              let savedPlan = try? JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data) else {
            return
        }

        plan = savedPlan
        statusMessage = "前回受信した計画を表示しています"
    }

    private func apply(snapshot: WatchWorkoutPlanSnapshot, data: Data) {
        plan = snapshot
        statusMessage = "\(snapshot.name) を受信しました"
        UserDefaults.standard.set(data, forKey: planStorageKey)
    }

    private nonisolated func receive(userInfo: [String: Any]) {
        guard userInfo[WatchWorkoutTransfer.messageTypeKey] as? String == WatchWorkoutTransfer.planPushType,
              let data = userInfo[WatchWorkoutTransfer.payloadKey] as? Data else {
            return
        }

        do {
            let snapshot = try JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data)
            Task { @MainActor [weak self] in
                self?.apply(snapshot: snapshot, data: data)
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

    private nonisolated func updateActivationStatus(
        activationState: WCSessionActivationState,
        errorDescription: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let errorDescription {
                statusMessage = "接続失敗: \(errorDescription)"
            } else if activationState == .activated {
                statusMessage = plan == nil ? "iPhoneから今日の計画を送信してください" : "iPhoneと接続しました"
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

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(userInfo: message)
    }
}
