import Foundation
@preconcurrency import HealthKit
@preconcurrency import UserNotifications

extension WatchWorkoutStore {
    func loadSavedState() {
        if let data = UserDefaults.standard.data(forKey: planLibraryStorageKey),
           let library = try? decoder.decode(WatchWorkoutPlanLibrarySnapshot.self, from: data) {
            plans = library.plans
            userProfile = library.userProfile
            sensorPreferences = library.sensorPreferences ?? .default
            appearanceSettings = library.appearanceSettings ?? .load()
            dailyRecommendation = library.dailyRecommendation
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

        if let data = UserDefaults.standard.data(forKey: lastCompletedSessionStorageKey),
           let completedSession = try? decoder.decode(WatchWorkoutSessionSnapshot.self, from: data) {
            lastCompletedSession = completedSession
        }

        restoreRestTimer()
    }

    func prepareUITestStateIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard

        if arguments.contains("--reset-watch-ui-test-data") {
            defaults.removeObject(forKey: planStorageKey)
            defaults.removeObject(forKey: planLibraryStorageKey)
            defaults.removeObject(forKey: activeSessionStorageKey)
            defaults.removeObject(forKey: pendingSessionStorageKey)
            defaults.removeObject(forKey: lastCompletedSessionStorageKey)
            defaults.removeObject(forKey: restTimerEndStorageKey)
            defaults.removeObject(forKey: restTimerExerciseStorageKey)
            defaults.removeObject(forKey: WatchTutorialView.completedVersionKey)
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

    func prepareSetSwitchUITestStateIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--seed-watch-set-switch-state"),
              let plan = plans.first,
              let exercise = plan.exercises.first,
              exercise.sets.count >= 2 else {
            return
        }

        selectPlan(plan)
        startWorkout()
        guard let activeExercise = activeSession?.exercises.first,
              activeExercise.sets.count >= 2 else {
            return
        }

        startSet(exerciseID: activeExercise.id, setID: activeExercise.sets[0].id)
        setWeight(
            exerciseID: activeExercise.id,
            setID: activeExercise.sets[0].id,
            weight: 52.5
        )
        startSet(exerciseID: activeExercise.id, setID: activeExercise.sets[1].id)
    }

    static func uiTestPlans() -> [WatchWorkoutPlanSnapshot] {
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
                                targetWeight: 50,
                                targetReps: 10,
                                plannedConcentricSeconds: setOrder == 1 ? 2 : nil,
                                plannedEccentricSeconds: setOrder == 1 ? 3 : nil,
                                plannedTempoBeatSpeed: setOrder == 1 ? 1 : nil
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

    func apply(library: WatchWorkoutPlanLibrarySnapshot, data: Data? = nil) {
        plans = library.plans
        userProfile = library.userProfile
        sensorPreferences = library.sensorPreferences ?? .default
        appearanceSettings = library.appearanceSettings ?? appearanceSettings
        dailyRecommendation = library.dailyRecommendation
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

    func disableUnavailableSensors() {
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

    func updateSession(_ body: (inout WatchWorkoutSessionSnapshot) -> Void) {
        guard var session = activeSession else {
            return
        }

        body(&session)
        activeSession = session
        saveActiveSession()
        sendLiveSessionUpdate(force: true)
    }

    @discardableResult
    func dispatch(_ action: WatchWorkoutSessionAction) -> Bool {
        guard var session = activeSession,
              WatchWorkoutSessionReducer.reduce(session: &session, action: action) else {
            return false
        }

        activeSession = session
        saveActiveSession()
        sendLiveSessionUpdate(force: true)
        return true
    }

    func updateSet(
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

    func saveActiveSession() {
        guard let activeSession,
              let data = try? encoder.encode(activeSession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: activeSessionStorageKey)
    }

    func saveLastCompletedSession() {
        guard let lastCompletedSession,
              let data = try? encoder.encode(lastCompletedSession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: lastCompletedSessionStorageKey)
    }

    func savePlanLibrary() {
        guard let data = try? encoder.encode(
            WatchWorkoutPlanLibrarySnapshot(
                plans: plans,
                preferredPlanID: selectedPlan?.id,
                userProfile: userProfile,
                sensorPreferences: sensorPreferences,
                appearanceSettings: appearanceSettings,
                dailyRecommendation: dailyRecommendation
            )
        ) else {
            return
        }

        UserDefaults.standard.set(data, forKey: planLibraryStorageKey)
    }

    @discardableResult
    func refreshRestTimer(now: Date = Date()) -> Bool {
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

    func restoreRestTimer() {
        guard activeSession != nil,
              let savedEnd = UserDefaults.standard.object(forKey: restTimerEndStorageKey) as? Date,
              savedEnd > Date() else {
            UserDefaults.standard.removeObject(forKey: restTimerEndStorageKey)
            return
        }

        restEndsAt = savedEnd
        restExerciseID = UserDefaults.standard
            .string(forKey: restTimerExerciseStorageKey)
            .flatMap(UUID.init(uuidString:))
        refreshRestTimer()
    }

    func scheduleRestCompletionNotification(after seconds: Int) {
        guard !isUITestMode else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "休憩終了"
        content.body = "次のセットを始められます"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, seconds)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: restNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        let identifier = restNotificationIdentifier
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                return
            }
            center.removePendingNotificationRequests(
                withIdentifiers: [identifier]
            )
            center.add(request)
        }
    }
}
