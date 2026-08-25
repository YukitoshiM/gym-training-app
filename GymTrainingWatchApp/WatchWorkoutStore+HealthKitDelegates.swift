import Foundation
@preconcurrency import HealthKit

extension WatchWorkoutStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                isHealthWorkoutActive = true
            case .paused:
                healthStatusMessage = L10n.string("watch_widget.152f186dda7a", fallback: "Healthワークアウト一時停止中")
            case .ended, .stopped:
                isHealthWorkoutActive = false
            case .notStarted, .prepared:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            setHealthFallback(status: .failed, message: L10n.string("watch_widget.eeccc1fae145", fallback: "Health計測停止・手入力は継続中"))
            WatchDiagnostics.shared.record(
                level: "error",
                category: "health.session",
                message: "Health workout session failed",
                metadata: ["error": error.localizedDescription]
            )
            flushDiagnostics()
        }
    }
}

extension WatchWorkoutStore: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor [weak self] in
            self?.liveMetrics.elapsedSeconds = workoutBuilder.elapsedTime
        }
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let identifiers = Set(collectedTypes.compactMap { ($0 as? HKQuantityType)?.identifier })
        Task { @MainActor [weak self] in
            self?.processHealthData(from: workoutBuilder, identifiers: identifiers)
        }
    }
}
