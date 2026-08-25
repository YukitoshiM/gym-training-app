import Foundation

@MainActor
extension AppStore {
    func prepareDataImport(
        data: Data,
        fileName: String,
        options: DataImportOptions = DataImportOptions()
    ) throws -> DataImportPreview {
        var preview = try DataImportParser.parse(
            data: data,
            fileName: fileName,
            options: options,
            knownExercises: allExercises
        )
        let receipts = storage.loadDataImportReceipts()
        if receipts.contains(where: { $0.fingerprint == preview.fingerprint && $0.state == .applied }) {
            preview.wasPreviouslyImported = true
            preview.warnings.append(.init(severity: .blocking, message: "同じファイルはすでに読み込み済みです。"))
            return preview
        }
        guard preview.format != .bodyModeJSON else { return preview }

        let existingWorkoutKeys = Set(workoutHistory.map(Self.workoutDuplicateKey))
        var seenWorkoutKeys = existingWorkoutKeys
        var duplicateCount = 0
        preview.payload.workouts = preview.payload.workouts.filter { workout in
            let key = Self.workoutDuplicateKey(workout)
            guard seenWorkoutKeys.insert(key).inserted else {
                duplicateCount += 1
                return false
            }
            return true
        }

        let existingMetricKeys = Set(bodyMetricEntries.map(Self.metricDuplicateKey))
        var seenMetricKeys = existingMetricKeys
        preview.payload.bodyMetrics = preview.payload.bodyMetrics.filter { entry in
            let key = Self.metricDuplicateKey(entry)
            guard seenMetricKeys.insert(key).inserted else {
                duplicateCount += 1
                return false
            }
            return true
        }
        preview.summary.duplicateCount = duplicateCount
        preview.summary.workoutCount = preview.payload.workouts.count
        preview.summary.exerciseCount = preview.payload.workouts.reduce(0) { $0 + $1.exercises.count }
        preview.summary.setCount = preview.payload.workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.sets.count }
        }
        preview.summary.bodyMetricCount = preview.payload.bodyMetrics.count
        if duplicateCount > 0 {
            preview.warnings.append(.init(
                severity: .information,
                message: "既存またはファイル内で重複する\(duplicateCount)件は追加しません。"
            ))
        }
        if preview.summary.totalRecordCount == 0 {
            preview.warnings.append(.init(severity: .blocking, message: "新しく追加できる記録がありません。"))
        }
        return preview
    }

    @discardableResult
    func applyDataImport(_ preview: DataImportPreview) throws -> DataImportReceipt {
        guard !preview.wasPreviouslyImported else { throw DataImportError.alreadyImported }
        guard preview.canImport else { throw DataImportError.nothingToImport }

        let receipt = DataImportReceipt(
            fileName: preview.fileName,
            fingerprint: preview.fingerprint,
            format: preview.format,
            summary: preview.summary
        )
        let undo = DataImportUndoSnapshot(
            receiptID: receipt.id,
            createdAt: Date(),
            previousData: makeDataImportSnapshot()
        )
        storage.saveDataImportUndoSnapshot(undo)

        if let restore = preview.payload.bodyModeRestore {
            try applyDataImportSnapshot(restore)
        } else {
            customExercises.append(contentsOf: preview.payload.customExercises.filter { candidate in
                !customExercises.contains(where: { Self.normalizedName($0.name) == Self.normalizedName(candidate.name) })
                    && !PresetExerciseStore.exercises.contains(where: { Self.normalizedName($0.name) == Self.normalizedName(candidate.name) })
            })
            customExercises.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            workoutHistory.append(contentsOf: preview.payload.workouts)
            workoutHistory.sort { $0.startedAt > $1.startedAt }
            bodyMetricEntries.append(contentsOf: preview.payload.bodyMetrics)
            bodyMetricEntries.sort { $0.recordedAt > $1.recordedAt }
            storage.saveCustomExercises(customExercises)
            storage.saveWorkoutHistory(workoutHistory)
            storage.saveBodyMetricEntries(bodyMetricEntries)
        }

        var receipts = storage.loadDataImportReceipts()
        receipts.append(receipt)
        if receipts.count > 100 { receipts.removeFirst(receipts.count - 100) }
        storage.saveDataImportReceipts(receipts)
        return receipt
    }

    func rollbackLatestDataImport() throws -> DataImportReceipt {
        guard let undo = storage.loadDataImportUndoSnapshot() else {
            throw DataImportError.noRollbackAvailable
        }
        try applyDataImportSnapshot(undo.previousData)
        var receipts = storage.loadDataImportReceipts()
        guard let index = receipts.firstIndex(where: { $0.id == undo.receiptID }) else {
            storage.saveDataImportUndoSnapshot(nil)
            throw DataImportError.noRollbackAvailable
        }
        receipts[index].state = .rolledBack
        let receipt = receipts[index]
        storage.saveDataImportReceipts(receipts)
        storage.saveDataImportUndoSnapshot(nil)
        return receipt
    }

    var latestUndoableDataImport: DataImportReceipt? {
        guard let undo = storage.loadDataImportUndoSnapshot() else { return nil }
        return storage.loadDataImportReceipts().first { $0.id == undo.receiptID && $0.state == .applied }
    }

    private func makeDataImportSnapshot() -> GymDataExport {
        GymDataExport(
            schemaVersion: DataImportParser.currentBodyModeSchema,
            generatedAt: Date(),
            userProfile: userProfile,
            plans: plans,
            workoutHistory: workoutHistory,
            bodyMetricEntries: bodyMetricEntries,
            bodyMetricGoals: bodyMetricGoals,
            mealEntries: mealEntries,
            bodyPhotoEntries: bodyPhotoEntries,
            customExercises: customExercises,
            aiInsights: aiInsights,
            sensorSettings: sensorSettings,
            appearanceSettings: appearanceSettings,
            gymLocation: gymLocation,
            gymVisits: gymVisits,
            subjectiveRecoveryEntries: subjectiveRecoveryEntries,
            aiTransmissionHistory: aiTransmissionHistory,
            coachMemories: coachMemories,
            coachChatMessages: coachChatMessages,
            dailyRecommendations: dailyRecommendations,
            recommendationRevisions: recommendationRevisions,
            dailyReviews: dailyReviews,
            targetAdjustmentProposals: targetAdjustmentProposals,
            planRevisionProposals: planRevisionProposals,
            barcodeFoodProducts: BarcodeFoodProductStore().products(),
            dailyWorkoutSelection: dailyWorkoutSelection,
            activeWorkoutSession: activeWorkoutSession,
            deletedRecords: deletedRecords
        )
    }

    private func applyDataImportSnapshot(_ snapshot: GymDataExport) throws {
        try BarcodeFoodProductStore().replaceAll(with: snapshot.barcodeFoodProducts)
        userProfile = snapshot.userProfile
        plans = snapshot.plans
        workoutHistory = snapshot.workoutHistory.sorted { $0.startedAt > $1.startedAt }
        bodyMetricEntries = snapshot.bodyMetricEntries.sorted { $0.recordedAt > $1.recordedAt }
        bodyMetricGoals = snapshot.bodyMetricGoals.isEmpty ? Self.defaultBodyMetricGoals() : snapshot.bodyMetricGoals
        mealEntries = snapshot.mealEntries.sorted { $0.recordedAt > $1.recordedAt }
        bodyPhotoEntries = snapshot.bodyPhotoEntries.sorted { $0.recordedAt > $1.recordedAt }
        customExercises = snapshot.customExercises.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        aiInsights = snapshot.aiInsights
        sensorSettings = snapshot.sensorSettings
        appearanceSettings = snapshot.appearanceSettings
        gymLocation = snapshot.gymLocation
        gymVisits = snapshot.gymVisits
        subjectiveRecoveryEntries = snapshot.subjectiveRecoveryEntries
        aiTransmissionHistory = snapshot.aiTransmissionHistory
        coachMemories = snapshot.coachMemories
        coachChatMessages = snapshot.coachChatMessages
        dailyRecommendations = snapshot.dailyRecommendations
        recommendationRevisions = snapshot.recommendationRevisions
        dailyReviews = snapshot.dailyReviews
        targetAdjustmentProposals = snapshot.targetAdjustmentProposals
        planRevisionProposals = snapshot.planRevisionProposals
        dailyWorkoutSelection = snapshot.dailyWorkoutSelection
        activeWorkoutSession = snapshot.activeWorkoutSession
        deletedRecords = snapshot.deletedRecords

        storage.saveUserProfile(userProfile)
        storage.savePlans(plans)
        storage.saveWorkoutHistory(workoutHistory)
        storage.saveBodyMetricEntries(bodyMetricEntries)
        storage.saveBodyMetricGoals(bodyMetricGoals)
        storage.saveMealEntries(mealEntries)
        storage.saveBodyPhotoEntries(bodyPhotoEntries)
        storage.saveCustomExercises(customExercises)
        storage.saveAIInsights(aiInsights)
        storage.saveSensorSettings(sensorSettings)
        storage.saveAppearanceSettings(appearanceSettings)
        storage.saveGymLocation(gymLocation)
        storage.saveGymVisits(gymVisits)
        storage.saveSubjectiveRecoveryEntries(subjectiveRecoveryEntries)
        storage.saveAITransmissionHistory(aiTransmissionHistory)
        storage.saveCoachMemories(coachMemories)
        storage.saveCoachChatMessages(coachChatMessages)
        storage.saveDailyRecommendations(dailyRecommendations)
        storage.saveRecommendationRevisions(recommendationRevisions)
        storage.saveDailyReviews(dailyReviews)
        storage.saveTargetAdjustmentProposals(targetAdjustmentProposals)
        storage.savePlanRevisionProposals(planRevisionProposals)
        storage.saveDailyWorkoutSelection(dailyWorkoutSelection)
        storage.saveActiveWorkoutSession(activeWorkoutSession)
        storage.saveDeletedRecords(deletedRecords)
        UserDefaults.standard.set(userProfile.weightUnit.rawValue, forKey: BodyUnitPreferences.weightKey)
    }

    private static func workoutDuplicateKey(_ workout: WorkoutSession) -> String {
        let exerciseSignature = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }.map { exercise in
            let sets = exercise.sets.sorted { $0.setOrder < $1.setOrder }.map {
                "\($0.setOrder):\(rounded($0.actualWeight, places: 3)):\($0.actualReps)"
            }.joined(separator: ",")
            return "\(normalizedName(exercise.exercise.name))[\(sets)]"
        }.joined(separator: "|")
        return "\(Int(workout.startedAt.timeIntervalSince1970))|\(normalizedName(workout.title))|\(exerciseSignature)"
    }

    private static func metricDuplicateKey(_ entry: BodyMetricEntry) -> String {
        "\(entry.kind.rawValue)|\(Int(entry.recordedAt.timeIntervalSince1970))|\(rounded(entry.value, places: 3))"
    }

    private static func normalizedName(_ value: String) -> String {
        String(
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        )
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}
