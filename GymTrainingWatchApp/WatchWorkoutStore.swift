import Foundation
@preconcurrency import HealthKit
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
    @Published private(set) var liveMetrics = WatchLiveWorkoutMetrics.empty
    @Published private(set) var motionEstimate = WatchMotionEstimate.empty
    @Published private(set) var healthStatusMessage = "手入力で記録できます"
    @Published private(set) var isHealthWorkoutActive = false
    @Published private(set) var isWorkoutPaused = false
    @Published private(set) var isSetCompletionSuggested = false
    @Published private(set) var restReadinessMessage: String?
    @Published private(set) var setStartSuggestion: WatchSetStartSuggestion?
    @Published private(set) var nextSetLoadSuggestion: WatchNextSetLoadSuggestion?
    @Published private(set) var sensorPowerModeMessage = "通常サンプリング"
    @Published private(set) var appearanceSettings: AppAppearanceSettings = .load()

    private let planStorageKey = "gym.training.watch.currentPlan"
    private let planLibraryStorageKey = "gym.training.watch.planLibrary"
    private let activeSessionStorageKey = "gym.training.watch.activeSession"
    private let pendingSessionStorageKey = "gym.training.watch.pendingFinishedSession"
    private let restTimerEndStorageKey = "gym.training.watch.restTimerEnd"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let healthStore = HKHealthStore()
    private let motionAnalyzer = WatchMotionAnalyzer()
    private var restEndsAt: Date?
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var sensorPreferences = WatchSensorPreferences.default
    private var userProfile: WatchUserProfileSnapshot?
    private var activeSensorSet: (exerciseID: UUID, setID: UUID)?
    private var setHeartRateSamples: [Double] = []
    private var setHeartRateAtStart: Double?
    private var recoveryTracking: (exerciseID: UUID, setID: UUID, peak: Double, completedAt: Date)?
    private var workoutHeartRateSamples: [Double] = []
    private var healthCollectionStartedAt: Date?
    private var targetHapticSetID: UUID?
    private var lastHeartRateZone: Int?
    private var lastHeartRateZoneUpdatedAt: Date?
    private var automaticallyReducedSampling = false
    private var confirmedExerciseCandidate: (name: String, confidence: Double)?
    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("--seed-watch-ui-test-plan")

    override init() {
        super.init()
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
        configureSession()
        recoverSensorWorkoutIfNeeded()
    }

    func startWorkout() {
        guard let selectedPlan else {
            statusMessage = "今日のメニューを選んでください"
            return
        }

        activeSession = WatchWorkoutSessionSnapshot(plan: selectedPlan)
        activeSession?.healthKitSaveStatus = sensorPreferences.healthWorkoutEnabled ? .collecting : .unavailable
        stopRestTimer()
        resetSensorState()
        statusMessage = "\(selectedPlan.name) を開始しました"
        saveActiveSession()
        beginSensorWorkout()
        startIdleMotionMonitoring()
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
        endSensorWorkout(discard: true)
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        statusMessage = plans.isEmpty ? "iPhoneからメニューを同期してください" : "ワークアウトを破棄しました"
    }

    func startSet(exerciseID: UUID, setID: UUID) {
        stopRestTimer()
        setStartSuggestion = nil
        nextSetLoadSuggestion = nil
        confirmedExerciseCandidate = nil
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard !set.isCompleted else { return }
            set.startedAt = set.startedAt ?? Date()
        }

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
    }

    func setWeight(exerciseID: UUID, setID: UUID, weight: Double) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
            set.actualWeight = Self.normalizedWeight(weight)
        }
    }

    func setReps(exerciseID: UUID, setID: UUID, reps: Int) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
            set.actualReps = max(0, min(999, reps))
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
        isWorkoutPaused = true
        healthStatusMessage = "一時停止中"
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
        healthStatusMessage = isHealthWorkoutActive ? "心拍・消費エネルギーを計測中" : "手入力で記録中"
    }

    func setWorkoutNote(_ note: String) {
        updateSession { session in
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = trimmed.isEmpty ? nil : trimmed
        }
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
        updateSet(exerciseID: suggestion.exerciseID, setID: suggestion.setID) { set in
            guard !set.isCompleted else { return }
            set.actualWeight = Self.normalizedWeight(suggestion.suggestedWeight)
            set.actualReps = max(0, min(999, suggestion.suggestedReps))
        }
        nextSetLoadSuggestion = nil
    }

    func updateRPE(exerciseID: UUID, setID: UUID, rpe: Double?) {
        updateSet(exerciseID: exerciseID, setID: setID) { set in
            guard set.startedAt != nil, !set.isCompleted else { return }
            set.rpe = rpe.map { min(10, max(1, ($0 * 2).rounded() / 2)) }
        }
    }

    private static func normalizedWeight(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(999, max(0, (value * 10).rounded() / 10))
    }

    func setCompletion(exerciseID: UUID, setID: UUID, isCompleted: Bool) {
        var restSeconds = 0
        var completedRPE: Double?
        let finalMotionEstimate = isCompleted ? motionAnalyzer.stop() : motionEstimate
        let heartRateAtEnd = liveMetrics.currentHeartRate
        let averageSetHeartRate = setHeartRateSamples.isEmpty
            ? nil
            : setHeartRateSamples.reduce(0, +) / Double(setHeartRateSamples.count)
        let maximumSetHeartRate = setHeartRateSamples.max()

        updateSession { session in
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
                return
            }

            restSeconds = session.exercises[exerciseIndex].restSeconds
            completedRPE = session.exercises[exerciseIndex].sets[setIndex].rpe
            if isCompleted {
                session.exercises[exerciseIndex].sets[setIndex].startedAt =
                    session.exercises[exerciseIndex].sets[setIndex].startedAt ?? Date()
            }
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = isCompleted
            session.exercises[exerciseIndex].sets[setIndex].completedAt = isCompleted ? Date() : nil
            if isCompleted {
                let hasMotionEstimate = finalMotionEstimate.estimatedReps > 0
                let hasHeartRate = setHeartRateAtStart != nil || heartRateAtEnd != nil || averageSetHeartRate != nil
                if hasMotionEstimate || hasHeartRate {
                    session.exercises[exerciseIndex].sets[setIndex].sensorSummary = WatchSetSensorSummary(
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
                }
            }
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
                recoveryTracking = (exerciseID, setID, peak, Date())
            }
            let adjustedRest = adaptiveRestSeconds(base: restSeconds, heartRate: averageSetHeartRate, rpe: completedRPE)
            startRestTimer(seconds: adjustedRest)
            if sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    func tickRestTimer() {
        updateLiveElapsed()
        accumulateHeartRateZoneDuration()
        refreshPowerPolicy()
        guard isRestTimerRunning else { return }
        guard refreshRestTimer() else { return }

        if restRemaining == 0 {
            if sensorPreferences.hapticCoachingEnabled {
                WKInterfaceDevice.current().play(.notification)
            }
            startIdleMotionMonitoring()
        }
    }

    func startRestTimer(seconds: Int? = nil) {
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
        restReadinessMessage = nil
        UserDefaults.standard.set(restEndsAt, forKey: restTimerEndStorageKey)
    }

    func setRestTimer(seconds: Int) {
        let normalized = min(600, max(5, Int((Double(seconds) / 5).rounded()) * 5))
        startRestTimer(seconds: normalized)
    }

    func stopRestTimer() {
        restEndsAt = nil
        restRemaining = 0
        isRestTimerRunning = false
        restReadinessMessage = nil
        UserDefaults.standard.removeObject(forKey: restTimerEndStorageKey)
        startIdleMotionMonitoring()
    }

    func finishWorkout() {
        guard var finished = activeSession else {
            statusMessage = "完了するワークアウトがありません"
            return
        }

        finished.endedAt = Date()
        finished.sensorSummary = makeWorkoutSensorSummary(for: finished)
        finished.healthKitSaveStatus = finished.healthKitSaveStatus
            ?? (sensorPreferences.healthWorkoutEnabled ? .collecting : .unavailable)
        pendingFinishedSession = finished
        activeSession = nil
        selectedPlan = nil
        stopRestTimer()
        savePendingSession()
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
        finishSensorWorkout(finished)
    }

    func resendPendingSession() {
        guard let pendingFinishedSession else {
            statusMessage = "未送信のWatch記録はありません"
            return
        }

        sendFinishedSession(pendingFinishedSession)
    }

    private func beginSensorWorkout() {
        guard sensorPreferences.healthWorkoutEnabled else {
            healthStatusMessage = "Health連携オフ・手入力で記録中"
            isHealthWorkoutActive = false
            return
        }

        if isUITestMode {
            healthCollectionStartedAt = activeSession?.startedAt ?? Date()
            liveMetrics = WatchLiveWorkoutMetrics(
                elapsedSeconds: 0,
                currentHeartRate: 118,
                averageHeartRate: 112,
                maximumHeartRate: 126,
                activeEnergyKilocalories: 8,
                heartRateZone: 2,
                heartRateZoneDurations: [1: 80, 2: 180]
            )
            healthStatusMessage = "センサー計測中"
            isHealthWorkoutActive = true
            return
        }

        Task { await startHealthWorkout() }
    }

    private func recoverSensorWorkoutIfNeeded() {
        guard activeSession != nil,
              sensorPreferences.healthWorkoutEnabled,
              !isUITestMode,
              HKHealthStore.isHealthDataAvailable() else {
            return
        }

        healthStore.recoverActiveWorkoutSession { [weak self] session, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let session else {
                    setHealthFallback(status: .failed, message: "Health計測は復元できません。手入力は継続できます")
                    if let error {
                        NSLog("Health workout recovery failed: \(error.localizedDescription)")
                    }
                    return
                }

                let builder = session.associatedWorkoutBuilder()
                session.delegate = self
                builder.delegate = self
                workoutSession = session
                workoutBuilder = builder
                healthCollectionStartedAt = activeSession?.startedAt
                isHealthWorkoutActive = session.state == .running
                isWorkoutPaused = session.state == .paused
                healthStatusMessage = isWorkoutPaused ? "一時停止中" : "Health計測を復元しました"
            }
        }
    }

    private func startHealthWorkout() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            setHealthFallback(status: .unavailable, message: "Healthを利用できないため手入力で記録中")
            return
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            setHealthFallback(status: .unavailable, message: "センサー項目を準備できないため手入力で記録中")
            return
        }

        do {
            var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
            if #available(watchOS 11.0, *),
               let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
                shareTypes.insert(effortType)
            }
            try await healthStore.requestAuthorization(
                toShare: shareTypes,
                read: [heartRateType, activeEnergyType]
            )

            guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) != .sharingDenied else {
                setHealthFallback(status: .permissionDenied, message: "Healthの許可なし・手入力で記録中")
                return
            }

            let startDate = activeSession?.startedAt ?? Date()
            if await hasOverlappingHealthWorkout(
                startDate: startDate,
                externalID: activeSession?.id.uuidString
            ) {
                setHealthFallback(
                    status: .unavailable,
                    message: "同時間帯のFitness記録があるためHealthへの二重保存を避けました"
                )
                return
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            healthCollectionStartedAt = startDate
            if let externalID = activeSession?.id.uuidString {
                try await builder.addMetadata([HKMetadataKeyExternalUUID: externalID])
            }
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            isHealthWorkoutActive = true
            healthStatusMessage = "心拍・消費エネルギーを計測中"
            activeSession?.healthKitSaveStatus = .collecting
            saveActiveSession()
        } catch {
            setHealthFallback(status: .permissionDenied, message: "Healthを開始できないため手入力で記録中")
            NSLog("Health workout start failed: \(error.localizedDescription)")
        }
    }

    private func hasOverlappingHealthWorkout(startDate: Date, externalID: String?) async -> Bool {
        let type = HKObjectType.workoutType()
        let recentStart = Calendar.current.date(byAdding: .hour, value: -12, to: startDate) ?? startDate
        let datePredicate = HKQuery.predicateForSamples(withStart: recentStart, end: Date())
        let activityPredicate = HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 20,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let duplicate = workouts.contains { workout in
                    if let externalID,
                       workout.metadata?[HKMetadataKeyExternalUUID] as? String == externalID {
                        return true
                    }
                    return workout.startDate <= Date()
                        && workout.endDate >= startDate.addingTimeInterval(-60)
                }
                continuation.resume(returning: duplicate)
            }
            healthStore.execute(query)
        }
    }

    private func setHealthFallback(status: WatchHealthKitSaveStatus, message: String) {
        activeSession?.healthKitSaveStatus = status
        healthStatusMessage = message
        isHealthWorkoutActive = false
        saveActiveSession()
    }

    private func finishSensorWorkout(_ finished: WatchWorkoutSessionSnapshot) {
        motionAnalyzer.reset()
        activeSensorSet = nil

        guard sensorPreferences.healthWorkoutEnabled else {
            completeFinishedSession(finished, healthStatus: .unavailable)
            return
        }

        guard !isUITestMode else {
            completeFinishedSession(finished, healthStatus: .saved)
            return
        }

        guard let session = workoutSession, let builder = workoutBuilder else {
            let status = finished.healthKitSaveStatus ?? .failed
            completeFinishedSession(finished, healthStatus: status == .collecting ? .failed : status)
            return
        }

        let endDate = finished.endedAt ?? Date()
        session.end()
        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard success else {
                Task { @MainActor [weak self] in
                    self?.completeFinishedSession(finished, healthStatus: .failed)
                    if let error {
                        NSLog("Health workout collection end failed: \(error.localizedDescription)")
                    }
                }
                return
            }

            builder.finishWorkout { [weak self] workout, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let workout, error == nil else {
                        completeFinishedSession(finished, healthStatus: .failed)
                        if let error {
                            NSLog("Health workout save failed: \(error.localizedDescription)")
                        }
                        return
                    }

                    saveEffortScoreIfAvailable(for: workout, session: finished) { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.completeFinishedSession(finished, healthStatus: .saved)
                        }
                    }
                    if let error {
                        NSLog("Health workout save failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func completeFinishedSession(
        _ session: WatchWorkoutSessionSnapshot,
        healthStatus: WatchHealthKitSaveStatus
    ) {
        var finished = session
        finished.healthKitSaveStatus = healthStatus
        pendingFinishedSession = finished
        savePendingSession()
        resetHealthObjects()

        switch healthStatus {
        case .saved:
            healthStatusMessage = "Apple Healthへ保存しました"
        case .permissionDenied:
            healthStatusMessage = "Health未保存・Watch記録は保存済み"
        case .failed:
            healthStatusMessage = "Health保存失敗・Watch記録は保存済み"
        case .unavailable:
            healthStatusMessage = "Watch記録を保存しました"
        case .collecting:
            healthStatusMessage = "Health保存を処理中"
        }

        sendFinishedSession(finished)
    }

    private func saveEffortScoreIfAvailable(
        for workout: HKWorkout,
        session: WatchWorkoutSessionSnapshot,
        completion: @escaping @Sendable () -> Void
    ) {
        guard #available(watchOS 11.0, *),
              let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            completion()
            return
        }

        let rpeValues = session.exercises.flatMap(\.sets).compactMap(\.rpe)
        guard !rpeValues.isEmpty,
              healthStore.authorizationStatus(for: effortType) == .sharingAuthorized else {
            completion()
            return
        }

        let averageRPE = min(10, max(1, rpeValues.reduce(0, +) / Double(rpeValues.count)))
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: averageRPE),
            start: session.startedAt,
            end: session.endedAt ?? Date()
        )

        healthStore.save(sample) { [weak self] success, error in
            guard success, let self else {
                if let error {
                    NSLog("Workout effort save failed: \(error.localizedDescription)")
                }
                completion()
                return
            }

            healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil) { _, error in
                if let error {
                    NSLog("Workout effort relationship failed: \(error.localizedDescription)")
                }
                completion()
            }
        }
    }

    private func endSensorWorkout(discard: Bool) {
        motionAnalyzer.reset()
        activeSensorSet = nil

        if discard {
            workoutSession?.end()
            workoutBuilder?.discardWorkout()
        }
        resetHealthObjects()
    }

    private func resetSensorState() {
        liveMetrics = .empty
        motionEstimate = .empty
        activeSensorSet = nil
        setHeartRateSamples = []
        setHeartRateAtStart = nil
        recoveryTracking = nil
        workoutHeartRateSamples = []
        healthCollectionStartedAt = nil
        isWorkoutPaused = false
        isSetCompletionSuggested = false
        targetHapticSetID = nil
        setStartSuggestion = nil
        nextSetLoadSuggestion = nil
        confirmedExerciseCandidate = nil
        lastHeartRateZone = nil
        lastHeartRateZoneUpdatedAt = nil
    }

    private func resetHealthObjects() {
        workoutSession = nil
        workoutBuilder = nil
        isHealthWorkoutActive = false
    }

    private func updateLiveElapsed() {
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

    private func adaptiveRestSeconds(base: Int, heartRate: Double?, rpe: Double?) -> Int {
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

    private func makeWorkoutSensorSummary(
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

    private func processHealthData(
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

    private func heartRateZone(for heartRate: Double) -> Int? {
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

    private var effectiveReducedSampling: Bool {
        sensorPreferences.reducedSensorSamplingEnabled || automaticallyReducedSampling
    }

    private func refreshPowerPolicy() {
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

    private func registerHeartRateZone(_ zone: Int?, now: Date = Date()) {
        accumulateHeartRateZoneDuration(now: now)
        lastHeartRateZone = zone
        lastHeartRateZoneUpdatedAt = zone == nil ? nil : now
    }

    private func accumulateHeartRateZoneDuration(now: Date = Date()) {
        guard let zone = lastHeartRateZone,
              let lastUpdate = lastHeartRateZoneUpdatedAt else {
            return
        }

        let elapsed = min(10, max(0, now.timeIntervalSince(lastUpdate)))
        liveMetrics.heartRateZoneDurations[zone, default: 0] += elapsed
        lastHeartRateZoneUpdatedAt = now
    }

    private func startIdleMotionMonitoring() {
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

    private func handleSetStartCandidate(_ estimate: WatchMotionEstimate) {
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

    private func makeNextSetLoadSuggestion(
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

    private func updateHeartRateRecovery(current: Double) {
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
            userProfile = library.userProfile
            sensorPreferences = library.sensorPreferences ?? .default
            appearanceSettings = library.appearanceSettings ?? .load()
            appearanceSettings.save()
            disableUnavailableSensors()
            selectedPlan = library.preferredPlanID.flatMap { preferredID in
                plans.first { $0.id == preferredID }
            }
            statusMessage = selectedPlan.map { "今日のメニュー: \($0.name)" } ?? "同期済みメニューから選べます"
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
            AppAppearanceSettings.reset(in: defaults)
            appearanceSettings = .default
        }

        guard arguments.contains("--seed-watch-ui-test-plan"),
              let libraryData = try? encoder.encode(
                WatchWorkoutPlanLibrarySnapshot(
                    plans: Self.uiTestPlans(),
                    appearanceSettings: .default
                )
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

    private func apply(library: WatchWorkoutPlanLibrarySnapshot, data: Data? = nil) {
        plans = library.plans
        userProfile = library.userProfile
        sensorPreferences = library.sensorPreferences ?? .default
        appearanceSettings = library.appearanceSettings ?? appearanceSettings
        appearanceSettings.save()
        disableUnavailableSensors()
        selectedPlan = library.preferredPlanID.flatMap { preferredID in
            plans.first { $0.id == preferredID }
        }
        statusMessage = selectedPlan.map { "今日のメニュー: \($0.name)" }
            ?? "\(library.plans.count)件のメニューを同期しました"

        if let data {
            UserDefaults.standard.set(data, forKey: planLibraryStorageKey)
        } else {
            savePlanLibrary()
        }

        UserDefaults.standard.removeObject(forKey: planStorageKey)
    }

    private func disableUnavailableSensors() {
        var unavailable: [String] = []
        if !HKHealthStore.isHealthDataAvailable() {
            sensorPreferences.healthWorkoutEnabled = false
            unavailable.append("Health")
        }
        if !motionAnalyzer.isMotionAvailable {
            sensorPreferences.motionRepDetectionEnabled = false
            unavailable.append("モーション")
        }
        if !unavailable.isEmpty {
            healthStatusMessage = "非対応: \(unavailable.joined(separator: "・"))。手入力は利用できます"
        }
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
        guard let data = try? encoder.encode(
            WatchWorkoutPlanLibrarySnapshot(
                plans: plans,
                preferredPlanID: selectedPlan?.id,
                userProfile: userProfile,
                sensorPreferences: sensorPreferences,
                appearanceSettings: appearanceSettings
            )
        ) else {
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
                self?.apply(library: library, data: data)
            }
            return true

        case WatchWorkoutTransfer.planPushType:
            guard let snapshot = try? JSONDecoder().decode(WatchWorkoutPlanSnapshot.self, from: data) else {
                updateStatus("メニューデータを読み込めませんでした")
                return false
            }

            Task { @MainActor [weak self] in
                self?.apply(library: WatchWorkoutPlanLibrarySnapshot(plans: [snapshot]))
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
                healthStatusMessage = "Healthワークアウト一時停止中"
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
            setHealthFallback(status: .failed, message: "Health計測停止・手入力は継続中")
            NSLog("Health workout session failed: \(error.localizedDescription)")
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
