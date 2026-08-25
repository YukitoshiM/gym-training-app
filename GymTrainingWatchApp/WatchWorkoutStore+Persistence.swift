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
            statusMessage = selectedPlan.map { L10n.string("watch_widget.7a379d574423", fallback: "今日のメニュー: {{value1}}", values: [$0.name]) } ?? L10n.string("watch_widget.184f5906186f", fallback: "同期済みメニューから選べます")
        } else if let data = UserDefaults.standard.data(forKey: planStorageKey),
                  let savedPlan = try? decoder.decode(WatchWorkoutPlanSnapshot.self, from: data) {
            plans = [savedPlan]
            savePlanLibrary()
            statusMessage = L10n.string("watch_widget.184f5906186f", fallback: "同期済みメニューから選べます")
        }

        if let data = UserDefaults.standard.data(forKey: activeSessionStorageKey),
           let savedSession = try? decoder.decode(WatchWorkoutSessionSnapshot.self, from: data) {
            activeSession = savedSession
            statusMessage = L10n.string("watch_widget.7f66dfd79322", fallback: "{{value1}} を再開できます", values: [String(describing: savedSession.title)])
        }

        if let data = UserDefaults.standard.data(forKey: pendingSessionStorageKey),
           let pendingSession = try? decoder.decode(WatchWorkoutSessionSnapshot.self, from: data) {
            pendingFinishedSession = pendingSession
            statusMessage = L10n.string("watch_widget.3f81f9df08a8", fallback: "{{value1}} はiPhoneへ再送できます", values: [String(describing: pendingSession.title)])
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
                name: L10n.string("watch_widget.349df198921f", fallback: "胸の日"),
                weightUnit: .kg,
                exercises: [
                    WatchPlanExerciseSnapshot(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                        exerciseID: exerciseID,
                        name: L10n.string("watch_widget.40e95ebae744", fallback: "ベンチプレス"),
                        primaryMuscleName: L10n.string("watch_widget.f4f93e827213", fallback: "胸"),
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
                name: L10n.string("watch_widget.52e036cf79ae", fallback: "背中の日"),
                weightUnit: .kg,
                exercises: [
                    WatchPlanExerciseSnapshot(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                        exerciseID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                        name: L10n.string("watch_widget.e031879b0b11", fallback: "ラットプルダウン"),
                        primaryMuscleName: L10n.string("watch_widget.8361420226c3", fallback: "背中"),
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
        statusMessage = selectedPlan.map { L10n.string("watch_widget.7a379d574423", fallback: "今日のメニュー: {{value1}}", values: [$0.name]) }
            ?? L10n.string("watch_widget.e28d7cc26f9a", fallback: "{{value1}}件のメニューを同期しました", values: [String(describing: library.plans.count)])

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
            unavailable.append(L10n.string("watch_widget.8dffc87acbb9", fallback: "モーション"))
        }
        if !unavailable.isEmpty {
            healthStatusMessage = L10n.string("watch_widget.2501cba5bc6d", fallback: "非対応: {{value1}}。手入力は利用できます", values: [String(describing: unavailable.joined(separator: "・"))])
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
        content.title = L10n.string("watch_widget.8ada25b32266", fallback: "休憩終了")
        content.body = L10n.string("watch_widget.45268b5fcf2c", fallback: "次のセットを始められます")
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
