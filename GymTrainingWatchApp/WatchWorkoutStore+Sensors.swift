import Foundation
@preconcurrency import HealthKit
import WatchKit

extension WatchWorkoutStore {
    func updateLiveElapsed() {
        guard activeSession != nil else { return }

        if let builder = workoutBuilder {
            liveMetrics.elapsedSeconds = builder.elapsedTime
        } else if let startedAt = healthCollectionStartedAt ?? activeSession?.startedAt {
            liveMetrics.elapsedSeconds = max(0, Date().timeIntervalSince(startedAt))
        }

        if isUITestMode {
            let elapsedMinutes = max(1, liveMetrics.elapsedSeconds / 60)
            liveMetrics.activeEnergyKilocalories = 8 + elapsedMinutes * 4
        }
    }

    func adaptiveRestSeconds(base: Int, heartRate: Double?, rpe: Double?) -> Int {
        guard sensorPreferences.adaptiveRestEnabled else { return base }

        var adjusted = base
        if let rpe {
            if rpe >= 9 {
                adjusted += 30
            } else if rpe <= 6.5 {
                adjusted -= 15
            }
        }

        if let heartRate {
            if heartRate >= 150 {
                adjusted += 20
            } else if heartRate < 105 {
                adjusted -= 10
            }
        }

        return min(600, max(30, Int((Double(adjusted) / 5).rounded()) * 5))
    }

    func makeWorkoutSensorSummary(
        for session: WatchWorkoutSessionSnapshot
    ) -> WatchWorkoutSensorSummary {
        let setSummaries = session.exercises.flatMap(\.sets).compactMap(\.sensorSummary)
        let estimatedReps = setSummaries.compactMap(\.estimatedReps)
        let confidences = setSummaries.compactMap(\.confidence)
        let recoveries = setSummaries.compactMap(\.heartRateRecovery)

        return WatchWorkoutSensorSummary(
            durationSeconds: liveMetrics.elapsedSeconds > 0
                ? liveMetrics.elapsedSeconds
                : max(0, (session.endedAt ?? Date()).timeIntervalSince(session.startedAt)),
            activeEnergyKilocalories: liveMetrics.activeEnergyKilocalories,
            averageHeartRate: liveMetrics.averageHeartRate,
            maximumHeartRate: liveMetrics.maximumHeartRate,
            heartRateRecovery: recoveries.max(),
            completedSets: session.completedSetCount,
            estimatedReps: estimatedReps.isEmpty ? nil : estimatedReps.reduce(0, +),
            motionConfidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
            heartRateZoneDurations: liveMetrics.heartRateZoneDurations.isEmpty
                ? nil
                : liveMetrics.heartRateZoneDurations
        )
    }

    func processHealthData(
        from builder: HKLiveWorkoutBuilder,
        identifiers: Set<String>
    ) {
        if identifiers.contains(HKQuantityTypeIdentifier.heartRate.rawValue),
           let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let statistics = builder.statistics(for: heartRateType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let current = statistics.mostRecentQuantity()?.doubleValue(for: unit)
            let average = statistics.averageQuantity()?.doubleValue(for: unit)
            let maximum = statistics.maximumQuantity()?.doubleValue(for: unit)

            liveMetrics.currentHeartRate = current
            liveMetrics.averageHeartRate = average
            liveMetrics.maximumHeartRate = maximum
            let zone = current.flatMap(heartRateZone(for:))
            registerHeartRateZone(zone)
            liveMetrics.heartRateZone = zone

            if let current {
                workoutHeartRateSamples.append(current)
                if activeSensorSet != nil {
                    setHeartRateSamples.append(current)
                }
                updateHeartRateRecovery(current: current)
            }
        }

        if identifiers.contains(HKQuantityTypeIdentifier.activeEnergyBurned.rawValue),
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let energy = builder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            liveMetrics.activeEnergyKilocalories = energy
        }

        liveMetrics.elapsedSeconds = builder.elapsedTime
    }

    func heartRateZone(for heartRate: Double) -> Int? {
        guard let birthYear = userProfile?.birthYear else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        let age = max(10, min(100, currentYear - birthYear))
        let estimatedMaximum = Double(220 - age)
        let ratio = heartRate / estimatedMaximum

        switch ratio {
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    var effectiveReducedSampling: Bool {
        sensorPreferences.reducedSensorSamplingEnabled || automaticallyReducedSampling
    }

    func refreshPowerPolicy() {
        let device = WKInterfaceDevice.current()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let lowBattery = device.batteryLevel >= 0
            && device.batteryLevel <= 0.2
            && device.batteryState == .unplugged
        let shouldAutomaticallyReduce = lowPowerMode || lowBattery

        if sensorPreferences.reducedSensorSamplingEnabled {
            sensorPowerModeMessage = "省電力サンプリング（設定）"
        } else if lowPowerMode {
            sensorPowerModeMessage = "省電力サンプリング（低電力モード）"
        } else if lowBattery {
            sensorPowerModeMessage = "省電力サンプリング（バッテリー残量）"
        } else {
            sensorPowerModeMessage = "通常サンプリング"
        }

        guard automaticallyReducedSampling != shouldAutomaticallyReduce else { return }
        automaticallyReducedSampling = shouldAutomaticallyReduce
        motionAnalyzer.updateSampling(reduced: effectiveReducedSampling)
    }

    func registerHeartRateZone(_ zone: Int?, now: Date = Date()) {
        accumulateHeartRateZoneDuration(now: now)
        lastHeartRateZone = zone
        lastHeartRateZoneUpdatedAt = zone == nil ? nil : now
    }

    func accumulateHeartRateZoneDuration(now: Date = Date()) {
        guard let zone = lastHeartRateZone,
              let lastUpdate = lastHeartRateZoneUpdatedAt else {
            return
        }

        let elapsed = min(10, max(0, now.timeIntervalSince(lastUpdate)))
        liveMetrics.heartRateZoneDurations[zone, default: 0] += elapsed
        lastHeartRateZoneUpdatedAt = now
    }

    func startIdleMotionMonitoring() {
        guard activeSession != nil,
              activeSensorSet == nil,
              !isRestTimerRunning,
              !isWorkoutPaused,
              sensorPreferences.motionRepDetectionEnabled,
              motionAnalyzer.isMotionAvailable else {
            return
        }

        motionAnalyzer.startMonitoring(reducedSampling: effectiveReducedSampling)
    }

    func handleSetStartCandidate(_ estimate: WatchMotionEstimate) {
        guard let session = activeSession,
              activeSensorSet == nil,
              !isRestTimerRunning,
              !isWorkoutPaused else {
            return
        }

        let pending = session.exercises.compactMap { exercise -> (WatchWorkoutExerciseSnapshot, WatchWorkoutSetSnapshot)? in
            guard let set = exercise.sets.first(where: { !$0.isCompleted && $0.startedAt == nil }) else {
                return nil
            }
            return (exercise, set)
        }
        guard !pending.isEmpty else { return }

        let ranked = pending.enumerated().map { index, candidate -> (WatchWorkoutExerciseSnapshot, WatchWorkoutSetSnapshot, Double) in
            let exercise = candidate.0
            var score = max(0.15, 0.52 - Double(index) * 0.08)
            let muscle = exercise.primaryMuscleRawValue ?? ""

            switch estimate.dominantAxis {
            case "x" where ["chest", "biceps", "triceps", "arms"].contains(muscle):
                score += 0.12
            case "y" where ["shoulders", "quadriceps", "hamstrings", "glutes", "legs"].contains(muscle):
                score += 0.12
            case "z" where ["back", "core", "abs", "obliques"].contains(muscle):
                score += 0.12
            default:
                break
            }

            if (estimate.rotationalMovementRatio ?? 0) >= 0.45,
               ["dumbbell", "kettlebell", "cable"].contains(exercise.equipmentRawValue ?? "") {
                score += 0.08
            }
            return (exercise, candidate.1, min(0.85, score * max(0.75, estimate.confidence)))
        }

        guard let best = ranked.max(by: { $0.2 < $1.2 }) else { return }
        setStartSuggestion = WatchSetStartSuggestion(
            exerciseID: best.0.id,
            setID: best.1.id,
            exerciseName: best.0.name,
            confidence: best.2,
            reason: "手首の動きと未完了セットの順序から推定"
        )
        if sensorPreferences.hapticCoachingEnabled {
            WKInterfaceDevice.current().play(.click)
        }
    }

    func makeNextSetLoadSuggestion(
        completedExerciseID: UUID,
        completedSetID: UUID,
        motion: WatchMotionEstimate
    ) -> WatchNextSetLoadSuggestion? {
        guard let exercise = activeSession?.exercises.first(where: { $0.id == completedExerciseID }),
              let completedSet = exercise.sets.first(where: { $0.id == completedSetID }),
              let nextSet = exercise.sets.first(where: { !$0.isCompleted && $0.id != completedSetID }) else {
            return nil
        }

        let rpe = completedSet.rpe
        let velocityLoss = motion.velocityLossPercent
        let baseWeight = completedSet.actualWeight > 0 ? completedSet.actualWeight : nextSet.targetWeight
        let suggestedWeight: Double
        let reason: String

        if completedSet.actualReps < completedSet.targetReps
            || (rpe ?? 0) >= 9
            || (velocityLoss ?? 0) >= 20 {
            suggestedWeight = Self.normalizedWeight(baseWeight * 0.95)
            reason = "目標未達、RPE、動作速度低下のいずれかから5%軽く提案"
        } else if completedSet.actualReps >= completedSet.targetReps + 2
                    && (rpe ?? 7) <= 7.5
                    && (velocityLoss ?? 0) < 12 {
            suggestedWeight = Self.normalizedWeight(baseWeight * 1.025)
            reason = "余力と動作速度から2.5%重く提案"
        } else {
            suggestedWeight = Self.normalizedWeight(baseWeight)
            reason = "達成度、RPE、動作速度から同じ重量を提案"
        }

        return WatchNextSetLoadSuggestion(
            exerciseID: exercise.id,
            setID: nextSet.id,
            exerciseName: exercise.name,
            suggestedWeight: suggestedWeight,
            suggestedReps: nextSet.targetReps,
            reason: reason
        )
    }

    func updateHeartRateRecovery(current: Double) {
        guard let tracking = recoveryTracking,
              Date().timeIntervalSince(tracking.completedAt) >= 30 else {
            return
        }

        let recovery = max(0, tracking.peak - current)
        updateSet(exerciseID: tracking.exerciseID, setID: tracking.setID) { set in
            set.sensorSummary?.heartRateRecovery = recovery
        }
        if sensorPreferences.adaptiveRestEnabled, isRestTimerRunning {
            restReadinessMessage = recovery >= 25
                ? "心拍は回復傾向です。感覚が整えば次のセットへ"
                : "心拍を見ながら休憩を続けましょう"
            if recovery >= 25, sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.directionUp)
            }
        }
        recoveryTracking = nil
    }
}
