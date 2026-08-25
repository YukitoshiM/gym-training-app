import Foundation
@preconcurrency import HealthKit
import WatchKit

extension WatchWorkoutStore {
    func beginSensorWorkout() {
        guard sensorPreferences.healthWorkoutEnabled else {
            healthStatusMessage = L10n.string("watch_widget.c7c0bd2400ae", fallback: "Health連携オフ・手入力で記録中")
            isHealthWorkoutActive = false
            WatchDiagnostics.shared.record(
                category: "health.disabled",
                message: "Health workout collection is disabled"
            )
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
            healthStatusMessage = L10n.string("watch_widget.2e0ad9fc3b1a", fallback: "センサー計測中")
            isHealthWorkoutActive = true
            return
        }

        Task { await startHealthWorkout() }
    }

    func recoverSensorWorkoutIfNeeded() {
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
                    setHealthFallback(status: .failed, message: L10n.string("watch_widget.875a5d223149", fallback: "Health計測は復元できません。手入力は継続できます"))
                    if let error {
                        WatchDiagnostics.shared.record(
                            level: "error",
                            category: "health.recovery",
                            message: "Health workout recovery failed",
                            metadata: ["error": error.localizedDescription]
                        )
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
                healthStatusMessage = isWorkoutPaused ? L10n.string("watch_widget.114f06b70d1a", fallback: "一時停止中") : L10n.string("watch_widget.b1bb5fa8c916", fallback: "Health計測を復元しました")
                WatchDiagnostics.shared.record(
                    category: "health.recovery",
                    message: "Health workout recovered",
                    metadata: ["state": String(session.state.rawValue)]
                )
            }
        }
    }

    func startHealthWorkout() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            setHealthFallback(status: .unavailable, message: L10n.string("watch_widget.6c39297531fa", fallback: "Healthを利用できないため手入力で記録中"))
            return
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            setHealthFallback(status: .unavailable, message: L10n.string("watch_widget.2315bef407c9", fallback: "センサー項目を準備できないため手入力で記録中"))
            return
        }

        do {
            var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
            var readTypes: Set<HKObjectType> = [heartRateType, activeEnergyType]
            if let distanceType = activeDistanceType {
                readTypes.insert(distanceType)
            }
            if activeSession?.isOutdoorCardio == true {
                shareTypes.insert(HKSeriesType.workoutRoute())
            }
            if #available(watchOS 11.0, *),
               let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
                shareTypes.insert(effortType)
            }
            try await healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            )

            guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) != .sharingDenied else {
                setHealthFallback(status: .permissionDenied, message: L10n.string("watch_widget.919f5d735c32", fallback: "Healthの許可なし・手入力で記録中"))
                return
            }

            let startDate = activeSession?.startedAt ?? Date()
            if await hasOverlappingHealthWorkout(
                startDate: startDate,
                externalID: activeSession?.id.uuidString,
                activityType: activeHealthActivityType
            ) {
                setHealthFallback(
                    status: .unavailable,
                    message: L10n.string("watch_widget.56dc053a7297", fallback: "同時間帯のFitness記録があるためHealthへの二重保存を避けました")
                )
                WatchDiagnostics.shared.record(
                    category: "health.duplicate_prevented",
                    message: "Overlapping Health workout detected; duplicate save prevented"
                )
                return
            }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activeHealthActivityType
            configuration.locationType = activeSession?.isOutdoorCardio == true ? .outdoor : .indoor

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
            if activeSession?.isOutdoorCardio == true {
                startOutdoorRouteCollection()
            }
            isHealthWorkoutActive = true
            healthStatusMessage = L10n.string("watch_widget.fdc98ee0d134", fallback: "心拍・消費エネルギーを計測中")
            activeSession?.healthKitSaveStatus = .collecting
            saveActiveSession()
            WatchDiagnostics.shared.record(
                category: "health.started",
                message: "Health workout collection started",
                metadata: ["session_id": activeSession?.id.uuidString ?? "unknown"]
            )
        } catch {
            setHealthFallback(status: .permissionDenied, message: L10n.string("watch_widget.41e43dbbf218", fallback: "Healthを開始できないため手入力で記録中"))
            WatchDiagnostics.shared.record(
                level: "error",
                category: "health.start",
                message: "Health workout start failed",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func hasOverlappingHealthWorkout(
        startDate: Date,
        externalID: String?,
        activityType: HKWorkoutActivityType
    ) async -> Bool {
        let type = HKObjectType.workoutType()
        let recentStart = Calendar.current.date(byAdding: .hour, value: -12, to: startDate) ?? startDate
        let datePredicate = HKQuery.predicateForSamples(withStart: recentStart, end: Date())
        let activityPredicate = HKQuery.predicateForWorkouts(with: activityType)
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

    func setHealthFallback(status: WatchHealthKitSaveStatus, message: String) {
        activeSession?.healthKitSaveStatus = status
        healthStatusMessage = message
        isHealthWorkoutActive = false
        saveActiveSession()
        WatchDiagnostics.shared.record(
            level: status == .failed || status == .permissionDenied ? "error" : "info",
            category: "health.fallback",
            message: message,
            metadata: ["status": status.rawValue]
        )
    }

    func finishSensorWorkout(_ finished: WatchWorkoutSessionSnapshot) {
        motionAnalyzer.reset()
        stopTempoGuide()
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
                        WatchDiagnostics.shared.record(
                            level: "error",
                            category: "health.collection_end",
                            message: "Health workout collection end failed",
                            metadata: ["error": error.localizedDescription]
                        )
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
                            WatchDiagnostics.shared.record(
                                level: "error",
                                category: "health.save",
                                message: "Health workout save failed",
                                metadata: ["error": error.localizedDescription]
                            )
                        }
                        return
                    }

                    saveEffortScoreIfAvailable(for: workout, session: finished) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            finishOutdoorRoute(with: workout, session: finished) { [weak self] routedSession in
                                Task { @MainActor [weak self] in
                                    self?.completeFinishedSession(routedSession, healthStatus: .saved)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func completeFinishedSession(
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
            healthStatusMessage = L10n.string("watch_widget.a0272546c24a", fallback: "Apple Healthへ保存しました")
        case .permissionDenied:
            healthStatusMessage = L10n.string("watch_widget.775a658d59cf", fallback: "Health未保存・Watch記録は保存済み")
        case .failed:
            healthStatusMessage = L10n.string("watch_widget.e29bbf1b3ab8", fallback: "Health保存失敗・Watch記録は保存済み")
        case .unavailable:
            healthStatusMessage = L10n.string("watch_widget.2e494aa6c8a6", fallback: "Watch記録を保存しました")
        case .collecting:
            healthStatusMessage = L10n.string("watch_widget.b9b1cb7b9197", fallback: "Health保存を処理中")
        }

        WatchDiagnostics.shared.record(
            level: healthStatus == .failed ? "error" : "info",
            category: "health.finished",
            message: "Health workout processing finished",
            metadata: [
                "session_id": finished.id.uuidString,
                "status": healthStatus.rawValue
            ]
        )
        flushDiagnostics()
        sendFinishedSession(finished)
    }

    func saveEffortScoreIfAvailable(
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
                    WatchDiagnostics.shared.record(
                        level: "error",
                        category: "health.effort_save",
                        message: "Workout effort save failed",
                        metadata: ["error": error.localizedDescription]
                    )
                }
                completion()
                return
            }

            healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil) { _, error in
                if let error {
                    WatchDiagnostics.shared.record(
                        level: "error",
                        category: "health.effort_relation",
                        message: "Workout effort relationship failed",
                        metadata: ["error": error.localizedDescription]
                    )
                }
                completion()
            }
        }
    }

    func endSensorWorkout(discard: Bool) {
        motionAnalyzer.reset()
        stopTempoGuide()
        activeSensorSet = nil

        if discard {
            workoutSession?.end()
            workoutBuilder?.discardWorkout()
            stopOutdoorRouteCollection(discard: true)
        }
        resetHealthObjects()
    }

    func resetSensorState() {
        stopTempoGuide()
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
        outdoorGoalHapticSent = false
    }

    func resetHealthObjects() {
        workoutLocationManager.stopUpdatingLocation()
        workoutSession = nil
        workoutBuilder = nil
        isHealthWorkoutActive = false
    }

    var activeHealthActivityType: HKWorkoutActivityType {
        switch activeSession?.outdoorCardio?.activity {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case nil: .traditionalStrengthTraining
        }
    }

    var activeDistanceType: HKQuantityType? {
        switch activeSession?.outdoorCardio?.activity {
        case .running, .walking:
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .cycling:
            HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        case nil:
            nil
        }
    }

}
