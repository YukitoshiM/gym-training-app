import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var userProfile: UserProfile = .default
    @Published var plans: [TrainingPlan] = []
    @Published var workoutHistory: [WorkoutSession] = []
    @Published var bodyMetricEntries: [BodyMetricEntry] = []
    @Published var bodyMetricGoals: [BodyMetricGoal] = []
    @Published var mealEntries: [MealEntry] = []
    @Published var bodyPhotoEntries: [BodyPhotoEntry] = []
    @Published var customExercises: [Exercise] = []
    @Published var aiSettings: AISettings = .default
    @Published var aiInsights: [AIInsight] = []
    @Published var sensorSettings: SensorSettings = .default
    @Published var dailyWorkoutSelection: DailyWorkoutSelection?
    @Published var gymLocation: GymLocation?
    @Published var gymVisits: [GymVisit] = []
    @Published var subjectiveRecoveryEntries: [SubjectiveRecoveryEntry] = []
    @Published var pendingMissedGymPlan: DailyWorkoutSelection?
    @Published var aiTransmissionHistory: [AITransmissionRecord] = []
    @Published var appearanceSettings: AppAppearanceSettings = .default
    @Published var coachMemories: [CoachMemory] = []
    @Published var coachChatMessages: [CoachChatMessage] = []
    @Published var dailyRecommendations: [DailyRecommendation] = []
    @Published var recommendationRevisions: [RecommendationRevision] = []
    @Published var dailyReviews: [DailyReview] = []
    @Published var targetAdjustmentProposals: [TargetAdjustmentProposal] = []

    let storage: any AppDataRepository

    init(storage: any AppDataRepository = LocalJSONStorage()) {
        self.storage = storage
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--reset-ui-test-data") {
            storage.reset()
            UsageAnalytics.shared.reset()
            AppTourStateStore.markCompleted()
            UserDefaults.standard.removeObject(forKey: DailyRecommendationPersonalizationStore.enabledKey)
            UserDefaults.standard.removeObject(forKey: DailyRecommendationPersonalizationStore.resetDateKey)
            DailyRecommendationNotificationManager.resetOptimization()
            UserDefaults.standard.removeObject(forKey: "bodymode.home.detailsExpanded")
        }
        if arguments.contains("--expand-home-details") {
            UserDefaults.standard.set(true, forKey: "bodymode.home.detailsExpanded")
        }

        if arguments.contains("--seed-theme-black-champagne") {
            storage.saveAppearanceSettings(.init(colorTheme: .blackChampagne, mode: .system))
        } else if arguments.contains("--seed-theme-royal-cobalt") {
            storage.saveAppearanceSettings(.init(colorTheme: .royalCobalt, mode: .system))
        }
        if arguments.contains("--force-light-appearance") {
            var settings = storage.loadAppearanceSettings()
            settings.mode = .light
            storage.saveAppearanceSettings(settings)
        } else if arguments.contains("--force-dark-appearance") {
            var settings = storage.loadAppearanceSettings()
            settings.mode = .dark
            storage.saveAppearanceSettings(settings)
        }

        if arguments.contains("--seed-alpha-ui-test-plan") {
            storage.savePlans([Self.alphaUITestPlan()])
            storage.saveWorkoutHistory([])
            storage.saveBodyMetricEntries([])
            storage.saveBodyMetricGoals(Self.defaultBodyMetricGoals())
            storage.saveMealEntries([])
            storage.saveBodyPhotoEntries([])
            storage.saveCustomExercises([])
            storage.saveAISettings(arguments.contains("--seed-ai-unreachable-settings") ? Self.unreachableAISettings() : .default)
            storage.saveAIInsights([])
            storage.saveCoachMemories([])
            storage.saveCoachChatMessages([])
            storage.saveDailyRecommendations([])
            storage.saveRecommendationRevisions([])
            storage.saveDailyReviews([])
            storage.saveTargetAdjustmentProposals([])
            storage.saveUserProfile(.default)
        }

        if arguments.contains("--seed-beginner-onboarding") {
            storage.savePlans([])
            storage.saveWorkoutHistory([])
            storage.saveBodyMetricEntries([])
            storage.saveBodyMetricGoals(Self.defaultBodyMetricGoals())
            storage.saveMealEntries([])
            storage.saveBodyPhotoEntries([])
            storage.saveUserProfile(.default)
        }

        if arguments.contains("--seed-beginner-level-three") {
            let seed = Self.beginnerLevelThreeSeed()
            storage.savePlans([seed.plan])
            storage.saveWorkoutHistory(seed.history)
            storage.saveBodyMetricEntries([])
            storage.saveBodyMetricGoals(Self.defaultBodyMetricGoals())
            storage.saveMealEntries([])
            storage.saveBodyPhotoEntries([])
            storage.saveUserProfile(seed.profile)
        }

        if arguments.contains("--seed-retired-ai-settings") {
            storage.saveAISettings(Self.retiredAISettings())
        }

        if arguments.contains("--seed-assisted-ui-test-plan") {
            storage.savePlans([Self.assistedUITestPlan()])
            storage.saveWorkoutHistory([])
            storage.saveBodyMetricEntries([
                BodyMetricEntry(kind: .bodyWeight, value: 70, recordedAt: Date())
            ])
            storage.saveUserProfile(.default)
        }

        if arguments.contains("--seed-structured-weekly-report") {
            storage.saveAIInsights([
                AIInsight(
                    insightType: .weekly,
                    inputSummary: "身体KPI 3件、食事 8件、筋トレ 3件を確認しました。",
                    outputComment: "トレーニングを継続できています。回復記録を増やすと次週の調整精度が上がります。",
                    actionSuggestion: "睡眠を3日記録し、週3回の運動を続けてください。",
                    goodPoints: ["週3回のトレーニングを完了しました"],
                    challenges: ["睡眠の記録が不足しています"],
                    rationales: ["直近7日の運動履歴3件と食事記録8件を確認しました"],
                    nextActions: ["睡眠を3日記録する", "週3回の運動を続ける"]
                )
            ])
        }

        userProfile = storage.loadUserProfile()
        plans = storage.loadPlans()
        workoutHistory = storage.loadWorkoutHistory()
        bodyMetricEntries = storage.loadBodyMetricEntries()
        bodyMetricGoals = storage.loadBodyMetricGoals()
        mealEntries = storage.loadMealEntries()
        bodyPhotoEntries = storage.loadBodyPhotoEntries()
        customExercises = storage.loadCustomExercises()
        aiSettings = storage.loadAISettings()
        AppDiagnostics.shared.record(
            level: "info",
            category: "ai.configuration",
            message: "AI settings loaded",
            metadata: [
                "host": URL(string: aiSettings.baseURLString)?.host ?? "invalid",
                "managed_configuration_version": aiSettings.managedConfigurationVersion.map(String.init) ?? "custom",
                "enabled": String(aiSettings.isEnabled)
            ]
        )
        aiInsights = storage.loadAIInsights()
        sensorSettings = storage.loadSensorSettings()
        dailyWorkoutSelection = storage.loadDailyWorkoutSelection()
        gymLocation = storage.loadGymLocation()
        gymVisits = storage.loadGymVisits()
        subjectiveRecoveryEntries = storage.loadSubjectiveRecoveryEntries()
        aiTransmissionHistory = storage.loadAITransmissionHistory()
        appearanceSettings = storage.loadAppearanceSettings()
        coachMemories = storage.loadCoachMemories()
        coachChatMessages = storage.loadCoachChatMessages()
        dailyRecommendations = storage.loadDailyRecommendations()
        recommendationRevisions = storage.loadRecommendationRevisions()
        dailyReviews = storage.loadDailyReviews()
        targetAdjustmentProposals = storage.loadTargetAdjustmentProposals()

        if let selection = dailyWorkoutSelection,
           !Calendar.current.isDateInToday(selection.date) {
            let planStillExists = plans.contains(where: { $0.id == selection.planID })
            let visitedGym = !gymVisits(on: selection.date).isEmpty
            let completedWorkout = !workoutSessions(on: selection.date).isEmpty
            if planStillExists, !visitedGym, !completedWorkout {
                pendingMissedGymPlan = selection
            }
            dailyWorkoutSelection = nil
            storage.saveDailyWorkoutSelection(nil)
        } else if let selection = dailyWorkoutSelection,
                  !plans.contains(where: { $0.id == selection.planID }) {
            dailyWorkoutSelection = nil
            storage.saveDailyWorkoutSelection(nil)
        }

        if bodyMetricGoals.isEmpty {
            bodyMetricGoals = Self.defaultBodyMetricGoals()
            storage.saveBodyMetricGoals(bodyMetricGoals)
        }
    }

    private static func alphaUITestPlan() -> TrainingPlan {
        TrainingPlan(
            name: "胸の日",
            exercises: [
                PlanExercise(
                    exercise: PresetExerciseStore.exercises[0],
                    sortOrder: 0,
                    sets: (1...3).map {
                        PlanSetTarget(setOrder: $0, targetWeight: 20, targetReps: 10)
                    }
                )
            ]
        )
    }

    private static func assistedUITestPlan() -> TrainingPlan {
        let dips = PresetExerciseStore.exercises.first {
            $0.name == "ディップス"
        } ?? PresetExerciseStore.exercises[0]

        return TrainingPlan(
            name: "アシスト種目",
            exercises: [
                PlanExercise(
                    exercise: dips,
                    sortOrder: 0,
                    sets: (1...3).map {
                        PlanSetTarget(setOrder: $0, targetWeight: -20, targetReps: 10)
                    }
                )
            ]
        )
    }

    private static func beginnerLevelThreeSeed() -> (
        profile: UserProfile,
        plan: TrainingPlan,
        history: [WorkoutSession]
    ) {
        let exercise = PresetExerciseStore.exercises.first {
            $0.name == "ダンベルベンチプレス"
        } ?? PresetExerciseStore.exercises[0]
        let plan = TrainingPlan(
            name: "初心者 全身スタート",
            exercises: [
                PlanExercise(
                    exercise: exercise,
                    sortOrder: 0,
                    sets: (1...3).map {
                        PlanSetTarget(setOrder: $0, targetWeight: 8, targetReps: 10)
                    }
                )
            ]
        )
        let history = (0..<3).map { dayOffset in
            let startedAt = Calendar.current.date(
                byAdding: .day,
                value: -dayOffset,
                to: Date()
            ) ?? Date()
            return WorkoutSession(
                title: plan.name,
                sourcePlanID: plan.id,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(30 * 60),
                exercises: [
                    WorkoutExercise(
                        exercise: exercise,
                        sortOrder: 0,
                        restSeconds: 90,
                        sets: (1...3).map {
                            WorkoutSet(
                                setOrder: $0,
                                targetWeight: 8,
                                targetReps: 10,
                                actualWeight: 8,
                                actualReps: 10,
                                isCompleted: true
                            )
                        }
                    )
                ]
            )
        }
        let profile = UserProfile(
            goalType: .muscleGain,
            outcomeStyle: .leanMuscular,
            focusMuscles: [.chest, .back],
            weeklyTrainingDays: 3,
            preferredSessionMinutes: 45,
            availableEquipment: [.dumbbell, .bodyweight],
            heightCm: nil,
            birthYear: nil,
            sex: .unspecified,
            experienceLevel: .beginner,
            weightUnit: .kg
        )
        return (profile, plan, history)
    }

    static func defaultBodyMetricGoals() -> [BodyMetricGoal] {
        BodyMetricKind.allCases.map {
            BodyMetricGoal(kind: $0)
        }
    }

    private static func unreachableAISettings() -> AISettings {
        AISettings(
            isEnabled: true,
            baseURLString: "http://127.0.0.1:1",
            apiKey: AISettings.default.apiKey
        )
    }

    private static func retiredAISettings() -> AISettings {
        AISettings(
            isEnabled: true,
            baseURLString: "https://christopher-using-organisations-hull.trycloudflare.com",
            apiKey: AISettings.default.apiKey,
            managedConfigurationVersion: 2
        )
    }
}
