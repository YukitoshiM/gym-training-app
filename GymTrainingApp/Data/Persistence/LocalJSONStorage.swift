import Foundation

struct LocalJSONStorage: AppDataRepository {
    private let userProfileKey = "gym.training.alpha.userProfile"
    private let plansKey = "gym.training.alpha.plans"
    private let historyKey = "gym.training.alpha.history"
    private let bodyMetricEntriesKey = "gym.training.alpha.bodyMetricEntries"
    private let bodyMetricGoalsKey = "gym.training.alpha.bodyMetricGoals"
    private let mealEntriesKey = "gym.training.alpha.mealEntries"
    private let bodyPhotoEntriesKey = "gym.training.alpha.bodyPhotoEntries"
    private let customExercisesKey = "gym.training.alpha.customExercises"
    private let aiSettingsKey = "gym.training.alpha.aiSettings"
    private let aiInsightsKey = "gym.training.alpha.aiInsights"
    private let sensorSettingsKey = "gym.training.alpha.sensorSettings"
    private let dailyWorkoutSelectionKey = "gym.training.alpha.dailyWorkoutSelection"
    private let gymLocationKey = "gym.training.alpha.gymLocation"
    private let gymVisitsKey = "gym.training.alpha.gymVisits"
    private let subjectiveRecoveryEntriesKey = "gym.training.alpha.subjectiveRecoveryEntries"
    private let aiTransmissionHistoryKey = "gym.training.alpha.aiTransmissionHistory"
    private let coachMemoriesKey = "gym.training.ai.coachMemories"
    private let coachChatMessagesKey = "gym.training.ai.coachChatMessages"
    private let healthRecoveryHistoryKey = "gym.training.health.recoveryHistory"
    private let dailyRecommendationsKey = "gym.training.omakase.dailyRecommendations"
    private let recommendationRevisionsKey = "gym.training.omakase.recommendationRevisions"
    private let dailyReviewsKey = "gym.training.omakase.dailyReviews"
    private let targetAdjustmentProposalsKey = "gym.training.omakase.targetAdjustmentProposals"
    private let planRevisionProposalsKey = "gym.training.plans.revisionProposals"
    private let activeWorkoutSessionKey = "gym.training.workout.activeSession"
    private let dataImportReceiptsKey = "gym.training.import.receipts"
    private let dataImportUndoSnapshotKey = "gym.training.import.undoSnapshot"
    private let deletedRecordsKey = "gym.training.deletedRecords"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let protectedStore = ProtectedDataStore.shared

    private var protectedKeys: [String] {
        [
            userProfileKey,
            plansKey,
            historyKey,
            bodyMetricEntriesKey,
            bodyMetricGoalsKey,
            mealEntriesKey,
            bodyPhotoEntriesKey,
            customExercisesKey,
            aiSettingsKey,
            aiInsightsKey,
            sensorSettingsKey,
            dailyWorkoutSelectionKey,
            gymLocationKey,
            gymVisitsKey,
            subjectiveRecoveryEntriesKey,
            aiTransmissionHistoryKey,
            coachMemoriesKey,
            coachChatMessagesKey,
            healthRecoveryHistoryKey,
            dailyRecommendationsKey,
            recommendationRevisionsKey,
            dailyReviewsKey,
            targetAdjustmentProposalsKey,
            planRevisionProposalsKey,
            activeWorkoutSessionKey,
            dataImportReceiptsKey,
            dataImportUndoSnapshotKey,
            deletedRecordsKey,
            BarcodeFoodProductStore.storageKey
        ]
    }

    func loadUserProfile() -> UserProfile {
        load(UserProfile.self, key: userProfileKey) ?? .default
    }

    func saveUserProfile(_ profile: UserProfile) {
        save(profile, key: userProfileKey)
    }

    func loadPlans() -> [TrainingPlan] {
        load([TrainingPlan].self, key: plansKey)
    }

    func savePlans(_ plans: [TrainingPlan]) {
        save(plans, key: plansKey)
    }

    func loadWorkoutHistory() -> [WorkoutSession] {
        load([WorkoutSession].self, key: historyKey)
    }

    func saveWorkoutHistory(_ history: [WorkoutSession]) {
        save(history, key: historyKey)
    }

    func loadBodyMetricEntries() -> [BodyMetricEntry] {
        load([BodyMetricEntry].self, key: bodyMetricEntriesKey)
    }

    func saveBodyMetricEntries(_ entries: [BodyMetricEntry]) {
        save(entries, key: bodyMetricEntriesKey)
    }

    func loadBodyMetricGoals() -> [BodyMetricGoal] {
        load([BodyMetricGoal].self, key: bodyMetricGoalsKey)
    }

    func saveBodyMetricGoals(_ goals: [BodyMetricGoal]) {
        save(goals, key: bodyMetricGoalsKey)
    }

    func loadMealEntries() -> [MealEntry] {
        load([MealEntry].self, key: mealEntriesKey)
    }

    func saveMealEntries(_ entries: [MealEntry]) {
        save(entries, key: mealEntriesKey)
    }

    func loadBodyPhotoEntries() -> [BodyPhotoEntry] {
        load([BodyPhotoEntry].self, key: bodyPhotoEntriesKey)
    }

    func saveBodyPhotoEntries(_ entries: [BodyPhotoEntry]) {
        save(entries, key: bodyPhotoEntriesKey)
    }

    func loadCustomExercises() -> [Exercise] {
        load([Exercise].self, key: customExercisesKey)
    }

    func saveCustomExercises(_ exercises: [Exercise]) {
        save(exercises, key: customExercisesKey)
    }

    func loadAISettings() -> AISettings {
        var settings = load(AISettings.self, key: aiSettingsKey) ?? .default

        if !settings.apiKey.isEmpty {
            if SecureSettingsStore.saveAPIKey(settings.apiKey) {
                var sanitized = settings
                sanitized.apiKey = ""
                save(sanitized, key: aiSettingsKey)
            }
        }

        settings.apiKey = SecureSettingsStore.loadAPIKey() ?? settings.apiKey
        let migrated = settings.migratingManagedConfiguration(to: AISettings.bundledConfiguration)
        if migrated != settings {
            saveAISettings(migrated)
        }
        return migrated
    }

    func saveAISettings(_ settings: AISettings) {
        var persisted = settings.normalizedForPersistence(relativeTo: AISettings.bundledConfiguration)
        if SecureSettingsStore.saveAPIKey(persisted.apiKey) {
            persisted.apiKey = ""
        }
        save(persisted, key: aiSettingsKey)
    }

    func loadAIInsights() -> [AIInsight] {
        load([AIInsight].self, key: aiInsightsKey)
    }

    func saveAIInsights(_ insights: [AIInsight]) {
        save(insights, key: aiInsightsKey)
    }

    func loadSensorSettings() -> SensorSettings {
        load(SensorSettings.self, key: sensorSettingsKey) ?? .default
    }

    func saveSensorSettings(_ settings: SensorSettings) {
        save(settings, key: sensorSettingsKey)
    }

    func loadDailyWorkoutSelection() -> DailyWorkoutSelection? {
        load(DailyWorkoutSelection.self, key: dailyWorkoutSelectionKey)
    }

    func saveDailyWorkoutSelection(_ selection: DailyWorkoutSelection?) {
        saveOptional(selection, key: dailyWorkoutSelectionKey)
    }

    func loadPlanRevisionProposals() -> [PlanRevisionProposal] {
        load([PlanRevisionProposal].self, key: planRevisionProposalsKey)
    }

    func savePlanRevisionProposals(_ proposals: [PlanRevisionProposal]) {
        save(proposals, key: planRevisionProposalsKey)
    }

    func loadActiveWorkoutSession() -> ActiveWorkoutSession? {
        load(ActiveWorkoutSession.self, key: activeWorkoutSessionKey)
    }

    func saveActiveWorkoutSession(_ session: ActiveWorkoutSession?) {
        saveOptional(session, key: activeWorkoutSessionKey)
    }

    func loadDataImportReceipts() -> [DataImportReceipt] {
        load([DataImportReceipt].self, key: dataImportReceiptsKey)
    }

    func saveDataImportReceipts(_ receipts: [DataImportReceipt]) {
        save(receipts, key: dataImportReceiptsKey)
    }

    func loadDataImportUndoSnapshot() -> DataImportUndoSnapshot? {
        load(DataImportUndoSnapshot.self, key: dataImportUndoSnapshotKey)
    }

    func saveDataImportUndoSnapshot(_ snapshot: DataImportUndoSnapshot?) {
        saveOptional(snapshot, key: dataImportUndoSnapshotKey)
    }

    func loadDeletedRecords() -> [DeletedRecord] {
        load([DeletedRecord].self, key: deletedRecordsKey)
    }

    func saveDeletedRecords(_ records: [DeletedRecord]) {
        save(records, key: deletedRecordsKey)
    }

    func loadGymLocation() -> GymLocation? {
        load(GymLocation.self, key: gymLocationKey)
    }

    func saveGymLocation(_ location: GymLocation?) {
        saveOptional(location, key: gymLocationKey)
    }

    func loadGymVisits() -> [GymVisit] {
        load([GymVisit].self, key: gymVisitsKey)
    }

    func saveGymVisits(_ visits: [GymVisit]) {
        save(visits, key: gymVisitsKey)
    }

    func loadSubjectiveRecoveryEntries() -> [SubjectiveRecoveryEntry] {
        load([SubjectiveRecoveryEntry].self, key: subjectiveRecoveryEntriesKey)
    }

    func saveSubjectiveRecoveryEntries(_ entries: [SubjectiveRecoveryEntry]) {
        save(entries, key: subjectiveRecoveryEntriesKey)
    }

    func loadAITransmissionHistory() -> [AITransmissionRecord] {
        load([AITransmissionRecord].self, key: aiTransmissionHistoryKey)
    }

    func saveAITransmissionHistory(_ records: [AITransmissionRecord]) {
        save(records, key: aiTransmissionHistoryKey)
    }

    func loadCoachMemories() -> [CoachMemory] {
        load([CoachMemory].self, key: coachMemoriesKey)
    }

    func saveCoachMemories(_ memories: [CoachMemory]) {
        save(memories, key: coachMemoriesKey)
    }

    func loadCoachChatMessages() -> [CoachChatMessage] {
        load([CoachChatMessage].self, key: coachChatMessagesKey)
    }

    func saveCoachChatMessages(_ messages: [CoachChatMessage]) {
        save(messages, key: coachChatMessagesKey)
    }

    func loadDailyRecommendations() -> [DailyRecommendation] {
        load([DailyRecommendation].self, key: dailyRecommendationsKey)
    }

    func saveDailyRecommendations(_ recommendations: [DailyRecommendation]) {
        save(recommendations, key: dailyRecommendationsKey)
    }

    func loadRecommendationRevisions() -> [RecommendationRevision] {
        load([RecommendationRevision].self, key: recommendationRevisionsKey)
    }

    func saveRecommendationRevisions(_ revisions: [RecommendationRevision]) {
        save(revisions, key: recommendationRevisionsKey)
    }

    func loadDailyReviews() -> [DailyReview] {
        load([DailyReview].self, key: dailyReviewsKey)
    }

    func saveDailyReviews(_ reviews: [DailyReview]) {
        save(reviews, key: dailyReviewsKey)
    }

    func loadTargetAdjustmentProposals() -> [TargetAdjustmentProposal] {
        load([TargetAdjustmentProposal].self, key: targetAdjustmentProposalsKey)
    }

    func saveTargetAdjustmentProposals(_ proposals: [TargetAdjustmentProposal]) {
        save(proposals, key: targetAdjustmentProposalsKey)
    }

    func loadAppearanceSettings() -> AppAppearanceSettings {
        .load()
    }

    func saveAppearanceSettings(_ settings: AppAppearanceSettings) {
        settings.save()
    }

    func reset() {
        protectedStore.removeAll(keys: protectedKeys)
        AIAuthenticationStore.shared.reset()
        SecureSettingsStore.resetAIIdentity()
        AppAppearanceSettings.reset()
    }

    private func load<T: Decodable>(_ type: [T].Type, key: String) -> [T] {
        guard let data = protectedStore.data(forKey: key) else {
            return []
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            AppDiagnostics.shared.record(
                error: error,
                category: "storage.decode",
                message: "Failed to decode array for \(key)"
            )
            return []
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = protectedStore.data(forKey: key) else {
            return nil
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            AppDiagnostics.shared.record(
                error: error,
                category: "storage.decode",
                message: "Failed to decode value for \(key)"
            )
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        do {
            try protectedStore.set(encoder.encode(value), forKey: key)
        } catch {
            AppDiagnostics.shared.record(
                error: error,
                category: "storage.encode",
                message: "Failed to encode value for \(key)"
            )
        }
    }

    private func saveOptional<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            protectedStore.removeValue(forKey: key)
            return
        }

        save(value, key: key)
    }
}
