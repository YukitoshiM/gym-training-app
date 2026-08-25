import SwiftUI

protocol AITrainerBackgroundResetting: AnyObject {
    @MainActor
    func reset()
}

@MainActor
extension AppStore {
    func resetAllData(
        backgroundAIService: any AITrainerBackgroundResetting = AITrainerBackgroundService.shared
    ) {
        backgroundAIService.reset()
        AIAuthenticationStore.shared.reset()
        SecureSettingsStore.resetAIIdentity()
        storage.reset()
        UsageAnalytics.shared.reset()
        UserDefaults.standard.removeObject(forKey: DailyRecommendationPersonalizationStore.enabledKey)
        UserDefaults.standard.removeObject(forKey: DailyRecommendationPersonalizationStore.resetDateKey)
        UserDefaults.standard.removeObject(forKey: DailyRecommendationAICreditPolicy.automaticUseKey)
        DailyRecommendationNotificationManager.resetOptimization()
        LegalConsentStore.reset()
        userProfile = .default
        plans = []
        workoutHistory = []
        bodyMetricEntries = []
        bodyMetricGoals = Self.defaultBodyMetricGoals()
        mealEntries = []
        bodyPhotoEntries = []
        customExercises = []
        aiSettings = .default
        aiInsights = []
        sensorSettings = .default
        dailyWorkoutSelection = nil
        dailyRecommendations = []
        recommendationRevisions = []
        dailyReviews = []
        targetAdjustmentProposals = []
        planRevisionProposals = []
        activeWorkoutSession = nil
        deletedRecords = []
        gymLocation = nil
        gymVisits = []
        subjectiveRecoveryEntries = []
        aiTransmissionHistory = []
        coachMemories = []
        coachChatMessages = []
        appearanceSettings = .default
        storage.saveBodyMetricGoals(bodyMetricGoals)
        storage.saveUserProfile(userProfile)
        storage.saveAISettings(aiSettings)
        storage.saveAIInsights(aiInsights)
        storage.saveSensorSettings(sensorSettings)
        storage.saveAppearanceSettings(appearanceSettings)
    }

    func moveToTrash(title: String, payload: DeletedRecordPayload) {
        deletedRecords.insert(DeletedRecord(title: title, payload: payload), at: 0)
        deletedRecords = Array(deletedRecords.prefix(200))
        storage.saveDeletedRecords(deletedRecords)
    }

    @discardableResult
    func restoreDeletedRecord(_ id: UUID) -> Bool {
        guard let index = deletedRecords.firstIndex(where: { $0.id == id }) else { return false }
        let record = deletedRecords[index]
        if case .activeWorkout = record.payload, activeWorkoutSession != nil {
            return false
        }
        switch record.payload {
        case .trainingPlan(let value):
            upsert(value, in: &plans)
            plans.sort { $0.updatedAt > $1.updatedAt }
            storage.savePlans(plans)
        case .activeWorkout(var value):
            value.state = .paused
            value.updatedAt = Date()
            value.revision += 1
            activeWorkoutSession = value
            storage.saveActiveWorkoutSession(value)
        case .workout(let value):
            upsert(value, in: &workoutHistory)
            workoutHistory.sort { $0.startedAt > $1.startedAt }
            storage.saveWorkoutHistory(workoutHistory)
        case .meal(let value):
            upsert(value, in: &mealEntries)
            mealEntries.sort { $0.recordedAt > $1.recordedAt }
            storage.saveMealEntries(mealEntries)
        case .bodyPhotos(let values):
            for value in values { upsert(value, in: &bodyPhotoEntries) }
            bodyPhotoEntries.sort { $0.recordedAt > $1.recordedAt }
            storage.saveBodyPhotoEntries(bodyPhotoEntries)
        case .bodyMetric(let value):
            upsert(value, in: &bodyMetricEntries)
            bodyMetricEntries.sort { $0.recordedAt > $1.recordedAt }
            storage.saveBodyMetricEntries(bodyMetricEntries)
        case .customExercise(let value):
            upsert(value, in: &customExercises)
            customExercises.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            storage.saveCustomExercises(customExercises)
        case .gymVisit(let value):
            upsert(value, in: &gymVisits)
            gymVisits.sort { $0.arrivedAt > $1.arrivedAt }
            storage.saveGymVisits(gymVisits)
        case .subjectiveRecovery(let value):
            upsert(value, in: &subjectiveRecoveryEntries)
            subjectiveRecoveryEntries.sort { $0.recordedAt > $1.recordedAt }
            storage.saveSubjectiveRecoveryEntries(subjectiveRecoveryEntries)
        case .coachMemory(let value):
            upsert(value, in: &coachMemories)
            storage.saveCoachMemories(coachMemories)
        case .coachChatMessage(let value):
            upsert(value, in: &coachChatMessages)
            coachChatMessages.sort { $0.createdAt < $1.createdAt }
            storage.saveCoachChatMessages(coachChatMessages)
        case .aiInsight(let value):
            upsert(value, in: &aiInsights)
            aiInsights.sort { $0.date > $1.date }
            storage.saveAIInsights(aiInsights)
        case .aiTransmission(let value):
            upsert(value, in: &aiTransmissionHistory)
            aiTransmissionHistory.sort { $0.sentAt > $1.sentAt }
            storage.saveAITransmissionHistory(aiTransmissionHistory)
        }
        deletedRecords.remove(at: index)
        storage.saveDeletedRecords(deletedRecords)
        return true
    }

    @discardableResult
    func restoreLastDeletedRecord() -> Bool {
        guard let id = deletedRecords.first?.id else { return false }
        return restoreDeletedRecord(id)
    }

    func permanentlyDeleteRecord(_ id: UUID) {
        deletedRecords.removeAll { $0.id == id }
        storage.saveDeletedRecords(deletedRecords)
    }

    func emptyTrash() {
        deletedRecords = []
        storage.saveDeletedRecords([])
    }

    private func upsert<T: Identifiable>(_ value: T, in values: inout [T]) where T.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }

    func makeExportData() throws -> Data {
        let export = GymDataExport(
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

}
