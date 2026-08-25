import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct GymDataExport: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var userProfile: UserProfile
    var plans: [TrainingPlan]
    var workoutHistory: [WorkoutSession]
    var bodyMetricEntries: [BodyMetricEntry]
    var bodyMetricGoals: [BodyMetricGoal]
    var mealEntries: [MealEntry]
    var bodyPhotoEntries: [BodyPhotoEntry]
    var customExercises: [Exercise]
    var aiInsights: [AIInsight]
    var sensorSettings: SensorSettings
    var appearanceSettings: AppAppearanceSettings
    var gymLocation: GymLocation?
    var gymVisits: [GymVisit]
    var subjectiveRecoveryEntries: [SubjectiveRecoveryEntry]
    var aiTransmissionHistory: [AITransmissionRecord]
    var coachMemories: [CoachMemory]
    var coachChatMessages: [CoachChatMessage]
    var dailyRecommendations: [DailyRecommendation]
    var recommendationRevisions: [RecommendationRevision]
    var dailyReviews: [DailyReview]
    var targetAdjustmentProposals: [TargetAdjustmentProposal]
    var planRevisionProposals: [PlanRevisionProposal]
    var barcodeFoodProducts: [BarcodeFoodProduct]
    var dailyWorkoutSelection: DailyWorkoutSelection?
    var activeWorkoutSession: ActiveWorkoutSession?
    var deletedRecords: [DeletedRecord]

    init(
        schemaVersion: Int,
        generatedAt: Date,
        userProfile: UserProfile,
        plans: [TrainingPlan],
        workoutHistory: [WorkoutSession],
        bodyMetricEntries: [BodyMetricEntry],
        bodyMetricGoals: [BodyMetricGoal],
        mealEntries: [MealEntry],
        bodyPhotoEntries: [BodyPhotoEntry],
        customExercises: [Exercise],
        aiInsights: [AIInsight],
        sensorSettings: SensorSettings,
        appearanceSettings: AppAppearanceSettings,
        gymLocation: GymLocation?,
        gymVisits: [GymVisit],
        subjectiveRecoveryEntries: [SubjectiveRecoveryEntry],
        aiTransmissionHistory: [AITransmissionRecord],
        coachMemories: [CoachMemory],
        coachChatMessages: [CoachChatMessage],
        dailyRecommendations: [DailyRecommendation],
        recommendationRevisions: [RecommendationRevision],
        dailyReviews: [DailyReview],
        targetAdjustmentProposals: [TargetAdjustmentProposal],
        planRevisionProposals: [PlanRevisionProposal],
        barcodeFoodProducts: [BarcodeFoodProduct],
        dailyWorkoutSelection: DailyWorkoutSelection?,
        activeWorkoutSession: ActiveWorkoutSession?,
        deletedRecords: [DeletedRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.userProfile = userProfile
        self.plans = plans
        self.workoutHistory = workoutHistory
        self.bodyMetricEntries = bodyMetricEntries
        self.bodyMetricGoals = bodyMetricGoals
        self.mealEntries = mealEntries
        self.bodyPhotoEntries = bodyPhotoEntries
        self.customExercises = customExercises
        self.aiInsights = aiInsights
        self.sensorSettings = sensorSettings
        self.appearanceSettings = appearanceSettings
        self.gymLocation = gymLocation
        self.gymVisits = gymVisits
        self.subjectiveRecoveryEntries = subjectiveRecoveryEntries
        self.aiTransmissionHistory = aiTransmissionHistory
        self.coachMemories = coachMemories
        self.coachChatMessages = coachChatMessages
        self.dailyRecommendations = dailyRecommendations
        self.recommendationRevisions = recommendationRevisions
        self.dailyReviews = dailyReviews
        self.targetAdjustmentProposals = targetAdjustmentProposals
        self.planRevisionProposals = planRevisionProposals
        self.barcodeFoodProducts = barcodeFoodProducts
        self.dailyWorkoutSelection = dailyWorkoutSelection
        self.activeWorkoutSession = activeWorkoutSession
        self.deletedRecords = deletedRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        userProfile = try container.decodeIfPresent(UserProfile.self, forKey: .userProfile) ?? .default
        plans = try container.decodeIfPresent([TrainingPlan].self, forKey: .plans) ?? []
        workoutHistory = try container.decodeIfPresent([WorkoutSession].self, forKey: .workoutHistory) ?? []
        bodyMetricEntries = try container.decodeIfPresent([BodyMetricEntry].self, forKey: .bodyMetricEntries) ?? []
        bodyMetricGoals = try container.decodeIfPresent([BodyMetricGoal].self, forKey: .bodyMetricGoals) ?? []
        mealEntries = try container.decodeIfPresent([MealEntry].self, forKey: .mealEntries) ?? []
        bodyPhotoEntries = try container.decodeIfPresent([BodyPhotoEntry].self, forKey: .bodyPhotoEntries) ?? []
        customExercises = try container.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
        aiInsights = try container.decodeIfPresent([AIInsight].self, forKey: .aiInsights) ?? []
        sensorSettings = try container.decodeIfPresent(SensorSettings.self, forKey: .sensorSettings) ?? .default
        appearanceSettings = try container.decodeIfPresent(AppAppearanceSettings.self, forKey: .appearanceSettings) ?? .default
        gymLocation = try container.decodeIfPresent(GymLocation.self, forKey: .gymLocation)
        gymVisits = try container.decodeIfPresent([GymVisit].self, forKey: .gymVisits) ?? []
        subjectiveRecoveryEntries = try container.decodeIfPresent([SubjectiveRecoveryEntry].self, forKey: .subjectiveRecoveryEntries) ?? []
        aiTransmissionHistory = try container.decodeIfPresent([AITransmissionRecord].self, forKey: .aiTransmissionHistory) ?? []
        coachMemories = try container.decodeIfPresent([CoachMemory].self, forKey: .coachMemories) ?? []
        coachChatMessages = try container.decodeIfPresent([CoachChatMessage].self, forKey: .coachChatMessages) ?? []
        dailyRecommendations = try container.decodeIfPresent([DailyRecommendation].self, forKey: .dailyRecommendations) ?? []
        recommendationRevisions = try container.decodeIfPresent([RecommendationRevision].self, forKey: .recommendationRevisions) ?? []
        dailyReviews = try container.decodeIfPresent([DailyReview].self, forKey: .dailyReviews) ?? []
        targetAdjustmentProposals = try container.decodeIfPresent([TargetAdjustmentProposal].self, forKey: .targetAdjustmentProposals) ?? []
        planRevisionProposals = try container.decodeIfPresent([PlanRevisionProposal].self, forKey: .planRevisionProposals) ?? []
        barcodeFoodProducts = try container.decodeIfPresent([BarcodeFoodProduct].self, forKey: .barcodeFoodProducts) ?? []
        dailyWorkoutSelection = try container.decodeIfPresent(DailyWorkoutSelection.self, forKey: .dailyWorkoutSelection)
        activeWorkoutSession = try container.decodeIfPresent(ActiveWorkoutSession.self, forKey: .activeWorkoutSession)
        deletedRecords = try container.decodeIfPresent([DeletedRecord].self, forKey: .deletedRecords) ?? []
    }
}

struct GymDataExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data("{}".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
