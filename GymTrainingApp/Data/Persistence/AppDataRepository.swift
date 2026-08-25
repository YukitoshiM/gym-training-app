protocol ProfileSettingsRepository {
    func loadUserProfile() -> UserProfile
    func saveUserProfile(_ profile: UserProfile)
    func loadAISettings() -> AISettings
    func saveAISettings(_ settings: AISettings)
    func loadAIInsights() -> [AIInsight]
    func saveAIInsights(_ insights: [AIInsight])
    func loadSensorSettings() -> SensorSettings
    func saveSensorSettings(_ settings: SensorSettings)
    func loadAppearanceSettings() -> AppAppearanceSettings
    func saveAppearanceSettings(_ settings: AppAppearanceSettings)
    func loadAITransmissionHistory() -> [AITransmissionRecord]
    func saveAITransmissionHistory(_ records: [AITransmissionRecord])
    func loadCoachMemories() -> [CoachMemory]
    func saveCoachMemories(_ memories: [CoachMemory])
    func loadCoachChatMessages() -> [CoachChatMessage]
    func saveCoachChatMessages(_ messages: [CoachChatMessage])
}

protocol WorkoutRepository {
    func loadPlans() -> [TrainingPlan]
    func savePlans(_ plans: [TrainingPlan])
    func loadWorkoutHistory() -> [WorkoutSession]
    func saveWorkoutHistory(_ history: [WorkoutSession])
    func loadCustomExercises() -> [Exercise]
    func saveCustomExercises(_ exercises: [Exercise])
    func loadDailyWorkoutSelection() -> DailyWorkoutSelection?
    func saveDailyWorkoutSelection(_ selection: DailyWorkoutSelection?)
    func loadPlanRevisionProposals() -> [PlanRevisionProposal]
    func savePlanRevisionProposals(_ proposals: [PlanRevisionProposal])
    func loadActiveWorkoutSession() -> ActiveWorkoutSession?
    func saveActiveWorkoutSession(_ session: ActiveWorkoutSession?)
}

protocol BodyAndNutritionRepository {
    func loadBodyMetricEntries() -> [BodyMetricEntry]
    func saveBodyMetricEntries(_ entries: [BodyMetricEntry])
    func loadBodyMetricGoals() -> [BodyMetricGoal]
    func saveBodyMetricGoals(_ goals: [BodyMetricGoal])
    func loadMealEntries() -> [MealEntry]
    func saveMealEntries(_ entries: [MealEntry])
    func loadBodyPhotoEntries() -> [BodyPhotoEntry]
    func saveBodyPhotoEntries(_ entries: [BodyPhotoEntry])
}

protocol RecoveryRepository {
    func loadGymLocation() -> GymLocation?
    func saveGymLocation(_ location: GymLocation?)
    func loadGymVisits() -> [GymVisit]
    func saveGymVisits(_ visits: [GymVisit])
    func loadSubjectiveRecoveryEntries() -> [SubjectiveRecoveryEntry]
    func saveSubjectiveRecoveryEntries(_ entries: [SubjectiveRecoveryEntry])
}

protocol DailyRecommendationRepository {
    func loadDailyRecommendations() -> [DailyRecommendation]
    func saveDailyRecommendations(_ recommendations: [DailyRecommendation])
    func loadRecommendationRevisions() -> [RecommendationRevision]
    func saveRecommendationRevisions(_ revisions: [RecommendationRevision])
    func loadDailyReviews() -> [DailyReview]
    func saveDailyReviews(_ reviews: [DailyReview])
    func loadTargetAdjustmentProposals() -> [TargetAdjustmentProposal]
    func saveTargetAdjustmentProposals(_ proposals: [TargetAdjustmentProposal])
}

protocol AppDataRepository:
    ProfileSettingsRepository,
    WorkoutRepository,
    BodyAndNutritionRepository,
    RecoveryRepository,
    DailyRecommendationRepository {
    func loadDataImportReceipts() -> [DataImportReceipt]
    func saveDataImportReceipts(_ receipts: [DataImportReceipt])
    func loadDataImportUndoSnapshot() -> DataImportUndoSnapshot?
    func saveDataImportUndoSnapshot(_ snapshot: DataImportUndoSnapshot?)
    func loadDeletedRecords() -> [DeletedRecord]
    func saveDeletedRecords(_ records: [DeletedRecord])
    func reset()
}
