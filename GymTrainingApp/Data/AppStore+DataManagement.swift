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

    func makeExportData() throws -> Data {
        let export = GymDataExport(
            schemaVersion: 6,
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
            barcodeFoodProducts: BarcodeFoodProductStore().products(),
            dailyWorkoutSelection: dailyWorkoutSelection
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

}
