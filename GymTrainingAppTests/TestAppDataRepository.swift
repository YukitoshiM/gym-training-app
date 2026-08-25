import Foundation
@testable import GymTrainingApp

final class TestAppDataRepository: AppDataRepository {
    var userProfile: UserProfile = .default
    var plans: [TrainingPlan] = []
    var workoutHistory: [WorkoutSession] = []
    var bodyMetricEntries: [BodyMetricEntry] = []
    var bodyMetricGoals: [BodyMetricGoal] = []
    var mealEntries: [MealEntry] = []
    var bodyPhotoEntries: [BodyPhotoEntry] = []
    var customExercises: [Exercise] = []
    var aiSettings: AISettings = .default
    var aiInsights: [AIInsight] = []
    var sensorSettings: SensorSettings = .default
    var appearanceSettings: AppAppearanceSettings = .default
    var dailyWorkoutSelection: DailyWorkoutSelection?
    var gymLocation: GymLocation?
    var gymVisits: [GymVisit] = []
    var subjectiveRecoveryEntries: [SubjectiveRecoveryEntry] = []
    var aiTransmissionHistory: [AITransmissionRecord] = []
    var coachMemories: [CoachMemory] = []
    var coachChatMessages: [CoachChatMessage] = []
    var dailyRecommendations: [DailyRecommendation] = []
    var recommendationRevisions: [RecommendationRevision] = []
    var dailyReviews: [DailyReview] = []
    var targetAdjustmentProposals: [TargetAdjustmentProposal] = []
    var planRevisionProposals: [PlanRevisionProposal] = []
    var activeWorkoutSession: ActiveWorkoutSession?
    var deletedRecords: [DeletedRecord] = []
    var dataImportReceipts: [DataImportReceipt] = []
    var dataImportUndoSnapshot: DataImportUndoSnapshot?

    func loadUserProfile() -> UserProfile { userProfile }
    func saveUserProfile(_ profile: UserProfile) { userProfile = profile }
    func loadPlans() -> [TrainingPlan] { plans }
    func savePlans(_ plans: [TrainingPlan]) { self.plans = plans }
    func loadWorkoutHistory() -> [WorkoutSession] { workoutHistory }
    func saveWorkoutHistory(_ history: [WorkoutSession]) { workoutHistory = history }
    func loadBodyMetricEntries() -> [BodyMetricEntry] { bodyMetricEntries }
    func saveBodyMetricEntries(_ entries: [BodyMetricEntry]) { bodyMetricEntries = entries }
    func loadBodyMetricGoals() -> [BodyMetricGoal] { bodyMetricGoals }
    func saveBodyMetricGoals(_ goals: [BodyMetricGoal]) { bodyMetricGoals = goals }
    func loadMealEntries() -> [MealEntry] { mealEntries }
    func saveMealEntries(_ entries: [MealEntry]) { mealEntries = entries }
    func loadBodyPhotoEntries() -> [BodyPhotoEntry] { bodyPhotoEntries }
    func saveBodyPhotoEntries(_ entries: [BodyPhotoEntry]) { bodyPhotoEntries = entries }
    func loadCustomExercises() -> [Exercise] { customExercises }
    func saveCustomExercises(_ exercises: [Exercise]) { customExercises = exercises }
    func loadAISettings() -> AISettings { aiSettings }
    func saveAISettings(_ settings: AISettings) { aiSettings = settings }
    func loadAIInsights() -> [AIInsight] { aiInsights }
    func saveAIInsights(_ insights: [AIInsight]) { aiInsights = insights }
    func loadSensorSettings() -> SensorSettings { sensorSettings }
    func saveSensorSettings(_ settings: SensorSettings) { sensorSettings = settings }
    func loadAppearanceSettings() -> AppAppearanceSettings { appearanceSettings }
    func saveAppearanceSettings(_ settings: AppAppearanceSettings) { appearanceSettings = settings }
    func loadDailyWorkoutSelection() -> DailyWorkoutSelection? { dailyWorkoutSelection }
    func saveDailyWorkoutSelection(_ selection: DailyWorkoutSelection?) { dailyWorkoutSelection = selection }
    func loadGymLocation() -> GymLocation? { gymLocation }
    func saveGymLocation(_ location: GymLocation?) { gymLocation = location }
    func loadGymVisits() -> [GymVisit] { gymVisits }
    func saveGymVisits(_ visits: [GymVisit]) { gymVisits = visits }
    func loadSubjectiveRecoveryEntries() -> [SubjectiveRecoveryEntry] { subjectiveRecoveryEntries }
    func saveSubjectiveRecoveryEntries(_ entries: [SubjectiveRecoveryEntry]) { subjectiveRecoveryEntries = entries }
    func loadAITransmissionHistory() -> [AITransmissionRecord] { aiTransmissionHistory }
    func saveAITransmissionHistory(_ records: [AITransmissionRecord]) { aiTransmissionHistory = records }
    func loadCoachMemories() -> [CoachMemory] { coachMemories }
    func saveCoachMemories(_ memories: [CoachMemory]) { coachMemories = memories }
    func loadCoachChatMessages() -> [CoachChatMessage] { coachChatMessages }
    func saveCoachChatMessages(_ messages: [CoachChatMessage]) { coachChatMessages = messages }
    func loadDailyRecommendations() -> [DailyRecommendation] { dailyRecommendations }
    func saveDailyRecommendations(_ recommendations: [DailyRecommendation]) { dailyRecommendations = recommendations }
    func loadRecommendationRevisions() -> [RecommendationRevision] { recommendationRevisions }
    func saveRecommendationRevisions(_ revisions: [RecommendationRevision]) { recommendationRevisions = revisions }
    func loadDailyReviews() -> [DailyReview] { dailyReviews }
    func saveDailyReviews(_ reviews: [DailyReview]) { dailyReviews = reviews }
    func loadTargetAdjustmentProposals() -> [TargetAdjustmentProposal] { targetAdjustmentProposals }
    func saveTargetAdjustmentProposals(_ proposals: [TargetAdjustmentProposal]) { targetAdjustmentProposals = proposals }
    func loadPlanRevisionProposals() -> [PlanRevisionProposal] { planRevisionProposals }
    func savePlanRevisionProposals(_ proposals: [PlanRevisionProposal]) { planRevisionProposals = proposals }
    func loadActiveWorkoutSession() -> ActiveWorkoutSession? { activeWorkoutSession }
    func saveActiveWorkoutSession(_ session: ActiveWorkoutSession?) { activeWorkoutSession = session }
    func loadDeletedRecords() -> [DeletedRecord] { deletedRecords }
    func saveDeletedRecords(_ records: [DeletedRecord]) { deletedRecords = records }
    func loadDataImportReceipts() -> [DataImportReceipt] { dataImportReceipts }
    func saveDataImportReceipts(_ receipts: [DataImportReceipt]) { dataImportReceipts = receipts }
    func loadDataImportUndoSnapshot() -> DataImportUndoSnapshot? { dataImportUndoSnapshot }
    func saveDataImportUndoSnapshot(_ snapshot: DataImportUndoSnapshot?) { dataImportUndoSnapshot = snapshot }

    func reset() {
        userProfile = .default
        plans = []
        workoutHistory = []
        bodyMetricEntries = []
        bodyMetricGoals = []
        mealEntries = []
        bodyPhotoEntries = []
        customExercises = []
        aiInsights = []
        dailyRecommendations = []
        recommendationRevisions = []
        dailyReviews = []
        targetAdjustmentProposals = []
        planRevisionProposals = []
        activeWorkoutSession = nil
        deletedRecords = []
        dataImportReceipts = []
        dataImportUndoSnapshot = nil
    }
}
