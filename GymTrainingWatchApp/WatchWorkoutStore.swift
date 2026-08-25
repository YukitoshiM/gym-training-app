import Foundation
@preconcurrency import CoreLocation
@preconcurrency import HealthKit
@preconcurrency import UserNotifications
import WatchKit
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published var plans: [WatchWorkoutPlanSnapshot] = []
    @Published var selectedPlan: WatchWorkoutPlanSnapshot?
    @Published var activeSession: WatchWorkoutSessionSnapshot?
    @Published var pendingFinishedSession: WatchWorkoutSessionSnapshot?
    @Published var statusMessage = L10n.string("watch_widget.84664872f4c8", fallback: "iPhoneからメニューを同期してください")
    @Published var restRemaining = 0
    @Published var isRestTimerRunning = false
    @Published var restExerciseID: UUID?
    @Published var lastCompletedSession: WatchWorkoutSessionSnapshot?
    @Published var liveMetrics = WatchLiveWorkoutMetrics.empty
    @Published var motionEstimate = WatchMotionEstimate.empty
    @Published var healthStatusMessage = L10n.string("watch_widget.abe1f768e53b", fallback: "手入力で記録できます")
    @Published var isHealthWorkoutActive = false
    @Published var isWorkoutPaused = false
    @Published var isSetCompletionSuggested = false
    @Published var restReadinessMessage: String?
    @Published var setStartSuggestion: WatchSetStartSuggestion?
    @Published var nextSetLoadSuggestion: WatchNextSetLoadSuggestion?
    @Published var sensorPowerModeMessage = L10n.string("watch_widget.2f9be1574e74", fallback: "通常サンプリング")
    @Published var appearanceSettings: AppAppearanceSettings = .load()
    @Published var dailyRecommendation: WatchDailyRecommendationSnapshot?
    @Published var tempoCue: WatchTempoCue?
    @Published var isTempoGuidePaused = false
    @Published var isTempoGuideFinished = false

    let planStorageKey = "gym.training.watch.currentPlan"
    let planLibraryStorageKey = "gym.training.watch.planLibrary"
    let activeSessionStorageKey = "gym.training.watch.activeSession"
    let pendingSessionStorageKey = "gym.training.watch.pendingFinishedSession"
    let lastCompletedSessionStorageKey = "gym.training.watch.lastCompletedSession"
    let restTimerEndStorageKey = "gym.training.watch.restTimerEnd"
    let restTimerExerciseStorageKey = "gym.training.watch.restTimerExercise"
    let restNotificationIdentifier = "gym.training.watch.restComplete"
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let healthStore = HKHealthStore()
    let motionAnalyzer = WatchMotionAnalyzer()
    var restEndsAt: Date?
    var workoutSession: HKWorkoutSession?
    var workoutBuilder: HKLiveWorkoutBuilder?
    let workoutLocationManager = CLLocationManager()
    var workoutRouteBuilder: HKWorkoutRouteBuilder?
    var workoutRoutePointCount = 0
    var outdoorGoalHapticSent = false
    var sensorPreferences = WatchSensorPreferences.default
    var userProfile: WatchUserProfileSnapshot?
    var activeSensorSet: (exerciseID: UUID, setID: UUID)?
    var setHeartRateSamples: [Double] = []
    var setHeartRateAtStart: Double?
    var recoveryTracking: (exerciseID: UUID, setID: UUID, peak: Double, completedAt: Date)?
    var workoutHeartRateSamples: [Double] = []
    var healthCollectionStartedAt: Date?
    var targetHapticSetID: UUID?
    var lastHeartRateZone: Int?
    var lastHeartRateZoneUpdatedAt: Date?
    var automaticallyReducedSampling = false
    var confirmedExerciseCandidate: (name: String, confidence: Double)?
    var lastLiveUpdateSentAt: Date?
    var tempoGuideState: WatchTempoGuideState?
    var tempoGuideTask: Task<Void, Never>?
    var tempoHapticTask: Task<Void, Never>?
    let isUITestMode = ProcessInfo.processInfo.arguments.contains("--seed-watch-ui-test-plan")

    override init() {
        super.init()
        workoutLocationManager.delegate = self
        workoutLocationManager.activityType = .fitness
        workoutLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        workoutLocationManager.distanceFilter = 5
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        motionAnalyzer.onEstimateChanged = { [weak self] estimate in
            guard let self else { return }
            motionEstimate = estimate
            guard sensorPreferences.hapticCoachingEnabled,
                  let activeSensorSet,
                  targetHapticSetID != activeSensorSet.setID,
                  let targetReps = activeSession?
                    .exercises.first(where: { $0.id == activeSensorSet.exerciseID })?
                    .sets.first(where: { $0.id == activeSensorSet.setID })?
                    .targetReps,
                  estimate.estimatedReps >= targetReps else {
                return
            }
            targetHapticSetID = activeSensorSet.setID
            WKInterfaceDevice.current().play(.directionUp)
        }
        motionAnalyzer.onSetInactivityDetected = { [weak self] in
            guard let self else { return }
            isSetCompletionSuggested = true
            if sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.click)
            }
        }
        motionAnalyzer.onSetStartCandidateDetected = { [weak self] estimate in
            self?.handleSetStartCandidate(estimate)
        }
        motionAnalyzer.onTempoDeviationDetected = { [weak self] in
            guard let self, sensorPreferences.hapticCoachingEnabled else { return }
            WKInterfaceDevice.current().play(.retry)
        }
        refreshPowerPolicy()
        prepareUITestStateIfNeeded()
        loadSavedState()
        prepareSetSwitchUITestStateIfNeeded()
        configureSession()
        recoverSensorWorkoutIfNeeded()
        WatchDiagnostics.shared.record(
            category: "lifecycle",
            message: "Watch app store initialized",
            metadata: [
                "has_active_session": String(activeSession != nil),
                "plan_count": String(plans.count)
            ]
        )
    }

    func startWorkout() {
        guard let selectedPlan else {
            statusMessage = L10n.string("watch_widget.7624bd6c72ec", fallback: "今日のメニューを選んでください")
            return
        }

        activeSession = WatchWorkoutSessionSnapshot(plan: selectedPlan)
        activeSession?.healthKitSaveStatus = sensorPreferences.healthWorkoutEnabled ? .collecting : .unavailable
        stopRestTimer()
        resetSensorState()
        statusMessage = L10n.string("watch_widget.0bb63860cfdd", fallback: "{{value1}} を開始しました", values: [String(describing: selectedPlan.name)])
        saveActiveSession()
        beginSensorWorkout()
        startIdleMotionMonitoring()
        sendLiveSessionUpdate(force: true)
        WatchDiagnostics.shared.record(
            category: "workout.started",
            message: "Workout started",
            metadata: [
                "session_id": activeSession?.id.uuidString ?? "unknown",
                "plan_id": selectedPlan.id.uuidString,
                "exercise_count": String(selectedPlan.exercises.count),
                "health_enabled": String(sensorPreferences.healthWorkoutEnabled)
            ]
        )
        flushDiagnostics()
    }

    func startRecommendedWorkout() {
        guard let planID = dailyRecommendation?.preferredPlanID,
              let plan = plans.first(where: { $0.id == planID }) else {
            statusMessage = L10n.string("watch_widget.8bdf19ffeed6", fallback: "iPhoneで今日のメニューを確認してください")
            return
        }
        selectPlan(plan)
        startWorkout()
    }

    func selectPlan(_ plan: WatchWorkoutPlanSnapshot) {
        guard plans.contains(where: { $0.id == plan.id }) else { return }
        selectedPlan = plan
        statusMessage = L10n.string("watch_widget.8c241f2be831", fallback: "{{value1}} を選択しました", values: [String(describing: plan.name)])
        WatchDiagnostics.shared.record(
            category: "workout.plan_selected",
            message: "Workout plan selected",
            metadata: [
                "plan_id": plan.id.uuidString,
                "plan_name": plan.name,
                "exercise_count": String(plan.exercises.count)
            ]
        )
    }

    func startOutdoorWorkout(
        activity: OutdoorCardioActivity,
        target: OutdoorCardioTarget
    ) {
        guard activeSession == nil else { return }
        let title: String = switch activity {
        case .running: L10n.string("watch_widget.outdoor_running", fallback: "屋外ランニング")
        case .walking: L10n.string("watch_widget.outdoor_walking", fallback: "屋外ウォーキング")
        case .cycling: L10n.string("watch_widget.outdoor_cycling", fallback: "屋外サイクリング")
        }
        activeSession = WatchWorkoutSessionSnapshot(
            sourcePlanID: nil,
            title: title,
            weightUnit: .kg,
            exercises: [],
            outdoorCardio: OutdoorCardioSnapshot(activity: activity, target: target)
        )
        activeSession?.healthKitSaveStatus = sensorPreferences.healthWorkoutEnabled ? .collecting : .unavailable
        stopRestTimer()
        resetSensorState()
        statusMessage = L10n.string("watch_widget.outdoor_started", fallback: "{{value1}}を開始しました", values: [title])
        saveActiveSession()
        beginSensorWorkout()
        sendLiveSessionUpdate(force: true)
        WatchDiagnostics.shared.record(
            category: "outdoor.started",
            message: "Outdoor cardio workout started",
            metadata: [
                "session_id": activeSession?.id.uuidString ?? "unknown",
                "activity": activity.rawValue,
                "goal": target.kind.rawValue
            ]
        )
    }

    func clearPlanSelection() {
        selectedPlan = nil
        statusMessage = L10n.string("watch_widget.7624bd6c72ec", fallback: "今日のメニューを選んでください")
    }

    func cancelWorkout() {
        let cancelledSessionID = activeSession?.id.uuidString
        let completedSets = activeSession?.completedSetCount ?? 0
        sendLiveSessionEnded()
        endSensorWorkout(discard: true)
        stopTempoGuide()
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        statusMessage = plans.isEmpty ? L10n.string("watch_widget.84664872f4c8", fallback: "iPhoneからメニューを同期してください") : L10n.string("watch_widget.66f5e3987c92", fallback: "ワークアウトを破棄しました")
        WatchDiagnostics.shared.record(
            category: "workout.cancelled",
            message: "Workout cancelled",
            metadata: [
                "session_id": cancelledSessionID ?? "unknown",
                "completed_sets": String(completedSets)
            ]
        )
        flushDiagnostics()
    }

    func startSet(exerciseID: UUID, setID: UUID) {
        guard let selectedSet = activeSession?
            .exercises.first(where: { $0.id == exerciseID })?
            .sets.first(where: { $0.id == setID }),
              !selectedSet.isCompleted else {
            return
        }

        let previousSetID = activeSensorSet?.setID
        stopTempoGuide()
        stopRestTimer()
        setStartSuggestion = nil
        nextSetLoadSuggestion = nil
        confirmedExerciseCandidate = nil
        _ = motionAnalyzer.stop()
        guard dispatch(.startSet(exerciseID: exerciseID, setID: setID, startedAt: Date())) else { return }

        activeSensorSet = (exerciseID, setID)
        setHeartRateSamples = []
        setHeartRateAtStart = liveMetrics.currentHeartRate
        motionEstimate = .empty
        isSetCompletionSuggested = false
        targetHapticSetID = nil

        if sensorPreferences.motionRepDetectionEnabled {
            motionAnalyzer.start(reducedSampling: effectiveReducedSampling)
        }

        if sensorPreferences.hapticCoachingEnabled {
            WKInterfaceDevice.current().play(.start)
        }

        if let startedSet = activeSession?
            .exercises.first(where: { $0.id == exerciseID })?
            .sets.first(where: { $0.id == setID }) {
            startTempoGuide(for: startedSet)
        }
        sendLiveSessionUpdate(force: true)
        WatchDiagnostics.shared.record(
            category: "set.started",
            message: previousSetID == nil ? "Set started" : "Active set changed",
            metadata: [
                "exercise_id": exerciseID.uuidString,
                "set_id": setID.uuidString,
                "set_order": String(selectedSet.setOrder),
                "exercise_name": activeSession?.exercises.first(where: { $0.id == exerciseID })?.name ?? "unknown",
                "previous_set_id": previousSetID?.uuidString ?? "none"
            ]
        )
    }

    func cancelSet(exerciseID: UUID, setID: UUID) {
        guard activeSensorSet?.exerciseID == exerciseID,
              activeSensorSet?.setID == setID else {
            return
        }
        _ = motionAnalyzer.stop()
        stopTempoGuide()
        guard dispatch(.cancelSet(exerciseID: exerciseID, setID: setID)) else { return }
        activeSensorSet = nil
        motionEstimate = .empty
        isSetCompletionSuggested = false
        startIdleMotionMonitoring()
        if sensorPreferences.hapticCoachingEnabled {
            WKInterfaceDevice.current().play(.stop)
        }
        sendLiveSessionUpdate(force: true)
        WatchDiagnostics.shared.record(
            category: "set.cancelled",
            message: "Set returned to pending",
            metadata: [
                "exercise_id": exerciseID.uuidString,
                "set_id": setID.uuidString
            ]
        )
    }

    func setWeight(exerciseID: UUID, setID: UUID, weight: Double) {
        guard let exercise = activeSession?.exercises.first(where: { $0.id == exerciseID }) else { return }
        let minimumWeight = exercise.supportsAssistedLoad
            ? AssistedLoadSupport.kilogramRange.lowerBound
            : 0
        let normalizedWeight = Self.normalizedWeight(weight, minimum: minimumWeight)
        dispatch(.updateExerciseWeight(
            exerciseID: exerciseID,
            activeSetID: setID,
            weight: normalizedWeight
        ))
    }

    func setReps(exerciseID: UUID, setID: UUID, reps: Int) {
        dispatch(.updateReps(exerciseID: exerciseID, setID: setID, reps: reps))
    }

    func setPlannedTempo(
        exerciseID: UUID,
        setID: UUID,
        concentricSeconds: Int,
        eccentricSeconds: Int,
        beatSpeed: Int
    ) {
        let normalizedConcentric = min(10, max(1, concentricSeconds))
        let normalizedEccentric = min(10, max(1, eccentricSeconds))
        let normalizedBeatSpeed = min(3, max(1, beatSpeed))

        dispatch(.updatePlannedTempo(
            exerciseID: exerciseID,
            setID: setID,
            concentricSeconds: normalizedConcentric,
            eccentricSeconds: normalizedEccentric,
            beatSpeed: normalizedBeatSpeed
        ))

        if activeSensorSet?.exerciseID == exerciseID, activeSensorSet?.setID == setID {
            if let set = activeSession?.exercises
                .first(where: { $0.id == exerciseID })?
                .sets
                .first(where: { $0.id == setID }) {
                startTempoGuide(for: set)
            }
        }
    }

    func applyEstimatedReps(exerciseID: UUID, setID: UUID) {
        guard let summary = activeSession?
            .exercises.first(where: { $0.id == exerciseID })?
            .sets.first(where: { $0.id == setID })?
            .sensorSummary,
              let estimatedReps = summary.estimatedReps else {
            return
        }

        updateSet(exerciseID: exerciseID, setID: setID) { set in
            set.actualReps = max(0, min(999, estimatedReps))
        }
    }

    func motionEstimate(exerciseID: UUID, setID: UUID) -> WatchMotionEstimate? {
        guard activeSensorSet?.exerciseID == exerciseID,
              activeSensorSet?.setID == setID,
              motionEstimate.estimatedReps > 0 else {
            return nil
        }
        return motionEstimate
    }

    func pauseWorkout() {
        guard activeSession != nil, !isWorkoutPaused else { return }
        workoutSession?.pause()
        _ = motionAnalyzer.stop()
        pauseTempoGuide()
        isWorkoutPaused = true
        healthStatusMessage = L10n.string("watch_widget.114f06b70d1a", fallback: "一時停止中")
        WatchDiagnostics.shared.record(category: "workout.paused", message: "Workout paused")
    }

    func resumeWorkout() {
        guard activeSession != nil, isWorkoutPaused else { return }
        workoutSession?.resume()
        if activeSensorSet != nil, sensorPreferences.motionRepDetectionEnabled {
            motionAnalyzer.start(reducedSampling: effectiveReducedSampling)
        } else {
            startIdleMotionMonitoring()
        }
        isWorkoutPaused = false
        resumeTempoGuide()
        healthStatusMessage = isHealthWorkoutActive ? L10n.string("watch_widget.fdc98ee0d134", fallback: "心拍・消費エネルギーを計測中") : L10n.string("watch_widget.85d6ce62e862", fallback: "手入力で記録中")
        WatchDiagnostics.shared.record(category: "workout.resumed", message: "Workout resumed")
    }

    func setWorkoutNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        dispatch(.updateNote(trimmed.isEmpty ? nil : trimmed))
    }

    func acceptSetStartSuggestion() {
        guard let suggestion = setStartSuggestion else { return }
        startSet(exerciseID: suggestion.exerciseID, setID: suggestion.setID)
        confirmedExerciseCandidate = (suggestion.exerciseName, suggestion.confidence)
    }

    func dismissSetStartSuggestion() {
        setStartSuggestion = nil
        startIdleMotionMonitoring()
    }

    func applyNextSetLoadSuggestion() {
        guard let suggestion = nextSetLoadSuggestion else { return }
        setWeight(
            exerciseID: suggestion.exerciseID,
            setID: suggestion.setID,
            weight: suggestion.suggestedWeight
        )
        updateSet(exerciseID: suggestion.exerciseID, setID: suggestion.setID) { set in
            guard !set.isCompleted else { return }
            set.actualReps = max(0, min(999, suggestion.suggestedReps))
        }
        nextSetLoadSuggestion = nil
    }

    func updateRPE(exerciseID: UUID, setID: UUID, rpe: Double?) {
        dispatch(.updateRPE(exerciseID: exerciseID, setID: setID, rpe: rpe))
    }

    static func normalizedWeight(_ value: Double, minimum: Double = 0) -> Double {
        guard value.isFinite else { return 0 }
        return min(999, max(minimum, (value * 10).rounded() / 10))
    }

    func setCompletion(exerciseID: UUID, setID: UUID, isCompleted: Bool) {
        guard let exercise = activeSession?.exercises.first(where: { $0.id == exerciseID }),
              let set = exercise.sets.first(where: { $0.id == setID }) else {
            return
        }
        let restSeconds = exercise.restSeconds
        let completedRPE = set.rpe
        let completedAt = Date()
        if isCompleted {
            stopTempoGuide()
        }
        let finalMotionEstimate = isCompleted ? motionAnalyzer.stop() : motionEstimate
        let heartRateAtEnd = liveMetrics.currentHeartRate
        let averageSetHeartRate = setHeartRateSamples.isEmpty
            ? nil
            : setHeartRateSamples.reduce(0, +) / Double(setHeartRateSamples.count)
        let maximumSetHeartRate = setHeartRateSamples.max()
        let hasMotionEstimate = finalMotionEstimate.estimatedReps > 0
        let hasHeartRate = setHeartRateAtStart != nil || heartRateAtEnd != nil || averageSetHeartRate != nil
        let sensorSummary: WatchSetSensorSummary? = isCompleted && (hasMotionEstimate || hasHeartRate)
            ? WatchSetSensorSummary(
                heartRateAtStart: setHeartRateAtStart,
                heartRateAtEnd: heartRateAtEnd,
                averageHeartRate: averageSetHeartRate,
                maximumHeartRate: maximumSetHeartRate,
                heartRateRecovery: nil,
                estimatedReps: hasMotionEstimate ? finalMotionEstimate.estimatedReps : nil,
                averageRepDuration: finalMotionEstimate.averageRepDuration,
                movementConsistency: finalMotionEstimate.movementConsistency,
                confidence: hasMotionEstimate ? finalMotionEstimate.confidence : nil,
                averageConcentricDuration: finalMotionEstimate.averageConcentricDuration,
                averageEccentricDuration: finalMotionEstimate.averageEccentricDuration,
                averagePauseDuration: finalMotionEstimate.averagePauseDuration,
                relativeRangeOfMotion: finalMotionEstimate.relativeRangeOfMotion,
                rangeOfMotionConsistency: finalMotionEstimate.rangeOfMotionConsistency,
                velocityLossPercent: finalMotionEstimate.velocityLossPercent,
                exerciseCandidateName: confirmedExerciseCandidate?.name,
                exerciseCandidateConfidence: confirmedExerciseCandidate?.confidence
            )
            : nil

        guard dispatch(.completeSet(
            exerciseID: exerciseID,
            setID: setID,
            isCompleted: isCompleted,
            completedAt: completedAt,
            sensorSummary: sensorSummary
        )) else {
            return
        }

        if isCompleted {
            nextSetLoadSuggestion = makeNextSetLoadSuggestion(
                completedExerciseID: exerciseID,
                completedSetID: setID,
                motion: finalMotionEstimate
            )
            activeSensorSet = nil
            confirmedExerciseCandidate = nil
            isSetCompletionSuggested = false
            if let peak = maximumSetHeartRate ?? heartRateAtEnd {
                recoveryTracking = (exerciseID, setID, peak, completedAt)
            }
            let adjustedRest = adaptiveRestSeconds(base: restSeconds, heartRate: averageSetHeartRate, rpe: completedRPE)
            startRestTimer(seconds: adjustedRest, exerciseID: exerciseID)
            if sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.success)
            }
            WatchDiagnostics.shared.record(
                category: "set.completed",
                message: "Set completed",
                metadata: [
                    "exercise_id": exerciseID.uuidString,
                    "exercise_name": exercise.name,
                    "set_id": setID.uuidString,
                    "set_order": String(set.setOrder),
                    "weight": String(set.actualWeight),
                    "reps": String(set.actualReps),
                    "rpe": set.rpe.map { String($0) } ?? "none",
                    "motion_estimated_reps": hasMotionEstimate ? "\(finalMotionEstimate.estimatedReps)" : "none"
                ]
            )
        }
    }

    func tickRestTimer() {
        updateLiveElapsed()
        accumulateHeartRateZoneDuration()
        refreshPowerPolicy()
        sendLiveSessionUpdate(force: false)
        guard isRestTimerRunning else { return }
        guard refreshRestTimer() else { return }

        if restRemaining == 0 {
            if sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.notification)
            }
            startIdleMotionMonitoring()
            WatchDiagnostics.shared.record(
                category: "rest.completed",
                message: "Rest timer completed"
            )
            flushDiagnostics()
        }
    }

    func startRestTimer(seconds: Int? = nil, exerciseID: UUID? = nil) {
        let fallbackRest = activeSession?.exercises.first?.restSeconds ?? 90
        let nextRest = seconds ?? fallbackRest
        guard nextRest > 0 else {
            return
        }

        _ = motionAnalyzer.stop()
        setStartSuggestion = nil
        restEndsAt = Date().addingTimeInterval(TimeInterval(nextRest))
        restRemaining = nextRest
        isRestTimerRunning = true
        restExerciseID = exerciseID ?? restExerciseID
        restReadinessMessage = nil
        UserDefaults.standard.set(restEndsAt, forKey: restTimerEndStorageKey)
        if let restExerciseID {
            UserDefaults.standard.set(restExerciseID.uuidString, forKey: restTimerExerciseStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: restTimerExerciseStorageKey)
        }
        scheduleRestCompletionNotification(after: nextRest)
        sendLiveSessionUpdate(force: true)
        WatchDiagnostics.shared.record(
            category: "rest.started",
            message: "Rest timer started",
            metadata: [
                "seconds": String(nextRest),
                "exercise_id": restExerciseID?.uuidString ?? "none"
            ]
        )
    }

    func setRestTimer(seconds: Int) {
        let normalized = min(600, max(5, Int((Double(seconds) / 5).rounded()) * 5))
        startRestTimer(seconds: normalized)
    }

    func stopRestTimer() {
        let wasRunning = isRestTimerRunning
        let remaining = restRemaining
        restEndsAt = nil
        restRemaining = 0
        isRestTimerRunning = false
        restExerciseID = nil
        restReadinessMessage = nil
        UserDefaults.standard.removeObject(forKey: restTimerEndStorageKey)
        UserDefaults.standard.removeObject(forKey: restTimerExerciseStorageKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restNotificationIdentifier]
        )
        startIdleMotionMonitoring()
        sendLiveSessionUpdate(force: true)
        if wasRunning {
            WatchDiagnostics.shared.record(
                category: "rest.stopped",
                message: "Rest timer stopped",
                metadata: ["remaining_seconds": String(remaining)]
            )
        }
    }

    func finishWorkout() {
        guard var finished = activeSession else {
            statusMessage = L10n.string("watch_widget.4fe891ea4590", fallback: "完了するワークアウトがありません")
            return
        }
        stopTempoGuide()

        finished.endedAt = Date()
        if let distance = liveMetrics.distanceKilometers,
           let cardio = finished.outdoorCardio {
            finished.outdoorCardio = cardio.updating(
                distanceKilometers: distance,
                elapsedSeconds: liveMetrics.elapsedSeconds
            )
        }
        finished.sensorSummary = makeWorkoutSensorSummary(for: finished)
        finished.healthKitSaveStatus = finished.healthKitSaveStatus
            ?? (sensorPreferences.healthWorkoutEnabled ? .collecting : .unavailable)
        pendingFinishedSession = finished
        lastCompletedSession = finished
        saveLastCompletedSession()
        sendLiveSessionEnded()
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
        savePendingSession()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        WatchDiagnostics.shared.record(
            category: "workout.finished",
            message: "Workout finished",
            metadata: [
                "session_id": finished.id.uuidString,
                "duration_seconds": String(Int((finished.endedAt ?? Date()).timeIntervalSince(finished.startedAt))),
                "completed_sets": String(finished.completedSetCount),
                "completed_reps": String(finished.completedRepCount)
            ]
        )
        flushDiagnostics()
        finishSensorWorkout(finished)
    }

    func pauseTempoGuide() {
        guard var state = tempoGuideState, !state.isFinished else { return }
        state.pause()
        tempoGuideState = state
        tempoGuideTask?.cancel()
        tempoGuideTask = nil
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        isTempoGuidePaused = state.isPaused
    }

    func resumeTempoGuide() {
        guard var state = tempoGuideState, state.isPaused, !state.isFinished else { return }
        state.resume()
        tempoGuideState = state
        isTempoGuidePaused = state.isPaused
        runTempoGuide()
    }

    func setTempoGuideEnabled(_ enabled: Bool) {
        guard var state = tempoGuideState, !state.isFinished else { return }
        state.setEnabled(enabled)
        tempoGuideState = state
        tempoGuideTask?.cancel()
        tempoGuideTask = nil
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        tempoCue = nil
        isTempoGuidePaused = state.isPaused
        if enabled {
            runTempoGuide()
        }
    }

    func skipTempoPhase() {
        guard var state = tempoGuideState, !state.isFinished else { return }
        state.skipCurrentPhase()
        tempoGuideState = state
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        tempoCue = nil
        if state.isFinished {
            finishTempoGuideNaturally()
        }
    }

    private func startTempoGuide(for set: WatchWorkoutSetSnapshot) {
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        guard sensorPreferences.hapticCoachingEnabled,
              let target = WatchTempoTarget(
                concentricSeconds: set.plannedConcentricSeconds,
                eccentricSeconds: set.plannedEccentricSeconds,
                repetitions: set.targetReps,
                beatSpeed: set.resolvedTempoBeatSpeed
              ) else {
            return
        }
        tempoGuideState = WatchTempoGuideState(target: target)
        tempoCue = nil
        isTempoGuidePaused = false
        isTempoGuideFinished = false
        runTempoGuide()
    }

    private func runTempoGuide() {
        tempoGuideTask?.cancel()
        tempoGuideTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                guard self.sensorPreferences.hapticCoachingEnabled else {
                    self.setTempoGuideEnabled(false)
                    return
                }
                guard var state = self.tempoGuideState else { return }
                guard let cue = state.advance() else {
                    self.finishTempoGuideNaturally()
                    return
                }
                self.tempoGuideState = state
                self.tempoCue = cue
                if state.isFinished {
                    self.finishTempoGuideNaturally(finalCue: cue)
                    return
                }
                self.playTempoHaptic(cue)
            }
        }
    }

    private func playTempoHaptic(_ cue: WatchTempoCue, playsSuccessAfterward: Bool = false) {
        guard cue.shouldEmitBeat || cue.hapticCue != .beat else {
            return
        }

        tempoHapticTask?.cancel()
        tempoHapticTask = Task {
            for (index, pulse) in cue.hapticPattern.enumerated() {
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(hapticType(for: pulse))
                guard index < cue.hapticPattern.count - 1 else { continue }
                try? await Task.sleep(nanoseconds: cue.hapticIntervalNanoseconds)
            }
            guard !Task.isCancelled, playsSuccessAfterward else { return }
            try? await Task.sleep(nanoseconds: cue.hapticIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.success)
        }
    }

    private func hapticType(for pulse: WatchTempoHapticPulse) -> WKHapticType {
        switch pulse {
        case .directionUp: .directionUp
        case .directionDown: .directionDown
        case .click: .click
        }
    }

    private func finishTempoGuideNaturally(finalCue: WatchTempoCue? = nil) {
        tempoGuideTask?.cancel()
        tempoGuideTask = nil
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        tempoCue = nil
        isTempoGuidePaused = false
        isTempoGuideFinished = true
        if let finalCue {
            playTempoHaptic(finalCue, playsSuccessAfterward: true)
        } else {
            WKInterfaceDevice.current().play(.success)
        }
    }

    func stopTempoGuide() {
        tempoGuideTask?.cancel()
        tempoGuideTask = nil
        tempoHapticTask?.cancel()
        tempoHapticTask = nil
        tempoGuideState = nil
        tempoCue = nil
        isTempoGuidePaused = false
        isTempoGuideFinished = false
    }

    func resendPendingSession() {
        guard let pendingFinishedSession else {
            statusMessage = L10n.string("watch_widget.dd99ab962c51", fallback: "未送信のWatch記録はありません")
            return
        }

        sendFinishedSession(pendingFinishedSession)
    }

}
