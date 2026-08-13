import SwiftUI

struct HomeView: View {
    static let detailsExpandedKey = "bodymode.home.detailsExpanded"

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var watchSyncService: WatchPlanSyncService
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var aiTrainerBackgroundService: AITrainerBackgroundService
    @AppStorage(DailyRecommendationNotificationManager.enabledKey) private var notificationsEnabled = false
    @AppStorage(DailyRecommendationPersonalizationStore.enabledKey) private var behaviorLearningEnabled = true
    @State private var personalizationResetNotice = false
    @State private var activeSession: WorkoutSession?
    @State private var isShowingGoalPicker = false
    @State private var isShowingSettings = false
    @AppStorage(Self.detailsExpandedKey) private var isShowingDetails = false
    @State private var omakaseSheet: OmakaseHomeSheet?
    @State private var isPreparingRecommendation = false

    let onCreatePlan: () -> Void
    let onOpenPlans: () -> Void
    let onOpenRecord: () -> Void

    init(
        onCreatePlan: @escaping () -> Void = {},
        onOpenPlans: @escaping () -> Void = {},
        onOpenRecord: @escaping () -> Void = {}
    ) {
        self.onCreatePlan = onCreatePlan
        self.onOpenPlans = onOpenPlans
        self.onOpenRecord = onOpenRecord
    }

    private var nextPlan: TrainingPlan? {
        appStore.todayPlan
    }

    private var beginnerJourney: BeginnerJourneyProgress {
        BeginnerJourneyProgress(
            hasPlan: !appStore.plans.isEmpty,
            completedWorkoutCount: appStore.workoutHistory.filter(\.isCompleted).count
        )
    }

    var body: some View {
        recommendationObservedContent
    }

    private var navigationContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let recommendation = appStore.dailyRecommendation() {
                        OmakaseHomeDashboard(
                            recommendation: recommendation,
                            progress: progress(for:),
                            isAIRefreshing: aiTrainerBackgroundService.isSending
                                && recommendation.aiEvaluatedAt == nil,
                            isAIEnabled: appStore.aiSettings.isEnabled,
                            coachName: appStore.userProfile.coachPersona.displayName,
                            coachRole: appStore.userProfile.coachType.displayName,
                            coachAvatarName: appStore.userProfile.coachPersona.assetName,
                            review: appStore.dailyReview(),
                            latestRevision: appStore.latestRecommendationRevision(),
                            targetAdjustment: appStore.pendingTargetAdjustmentProposal,
                            onOpen: openDailyAction,
                            onToggleManual: { appStore.toggleManualDailyAction($0.id) },
                            onWhy: { omakaseSheet = .why($0) },
                            onReplace: replaceDailyAction,
                            onQuickMeal: { omakaseSheet = .meal },
                            onQuickWeight: { omakaseSheet = .bodyMetric(.bodyWeight) },
                            onQuickPhoto: { omakaseSheet = .bodyPhoto },
                            onOpenAICoach: { openAICoach(for: recommendation) },
                            onAcceptTargetAdjustment: { appStore.acceptTargetAdjustmentProposal($0.id) },
                            onDeclineTargetAdjustment: { appStore.declineTargetAdjustmentProposal($0.id) }
                        )
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("今日の3つを準備しています")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("omakaseLoading")
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingDetails.toggle()
                        }
                    } label: {
                        HStack {
                            Label("詳しく見る", systemImage: "slider.horizontal.3")
                                .font(.headline)
                            Spacer()
                            Image(systemName: isShowingDetails ? "chevron.up" : "chevron.down")
                        }
                        .foregroundStyle(AppTheme.ink)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("omakaseDetailsButton")
                    .accessibilityValue(isShowingDetails ? "展開中" : "閉じています")

                    if isShowingDetails {
                        Toggle("行動通知", isOn: $notificationsEnabled)
                            .font(.headline)
                            .onChange(of: notificationsEnabled) { _, enabled in
                                Task {
                                    await DailyRecommendationNotificationManager.setEnabled(
                                        enabled,
                                        recommendation: appStore.dailyRecommendation()
                                    )
                                }
                            }

                        if notificationsEnabled {
                            Text(DailyRecommendationNotificationManager.optimizationSummary)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }

                        Toggle("行動パターンを学習", isOn: $behaviorLearningEnabled)
                            .font(.headline)
                            .onChange(of: behaviorLearningEnabled) { _, enabled in
                                DailyRecommendationPersonalizationStore.setEnabled(enabled)
                            }
                            .accessibilityIdentifier("behaviorLearningToggle")

                        Text(
                            behaviorLearningEnabled
                                ? DailyRecommendationPersonalizationStore.summary(from: appStore.dailyRecommendations)
                                : "学習は停止中です。過去の記録自体は削除されません。"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                        if behaviorLearningEnabled {
                            let evaluation = DailyRecommendationPersonalizationStore.evaluation(
                                recommendations: appStore.dailyRecommendations,
                                revisions: appStore.recommendationRevisions
                            )
                            Text(
                                "完了 \(evaluation.completionRate.formatted(.percent.precision(.fractionLength(0))))  "
                                    + "着手 \(evaluation.adoptionRate.formatted(.percent.precision(.fractionLength(0))))  "
                                    + "AI変更 \(evaluation.aiChangeRate.formatted(.percent.precision(.fractionLength(0))))"
                            )
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppTheme.mutedInk)
                            .accessibilityIdentifier("dailyRecommendationEvaluation")
                        }

                        Button {
                            DailyRecommendationPersonalizationStore.reset()
                            personalizationResetNotice = true
                            refreshDailyRecommendation(force: true)
                        } label: {
                            Label("提案学習だけリセット", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(!behaviorLearningEnabled)
                        .accessibilityIdentifier("resetBehaviorLearningButton")

                        if personalizationResetNotice {
                            Label("今日から学び直します", systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.positive)
                        }

                    if let liveWorkout = watchSyncService.liveWatchWorkout {
                        HomeSectionHeader(
                            title: "進行中"
                        )
                        WatchLiveWorkoutCard(snapshot: liveWorkout)
                    }

                    TodayTrainingCard(
                        plan: nextPlan,
                        completedSessions: appStore.workoutSessions(),
                        onStart: {
                        if let nextPlan {
                            activeSession = appStore.makeWorkoutSession(from: nextPlan)
                        }
                        },
                        onCreatePlan: onCreatePlan
                    )

                    if appStore.userProfile.experienceLevel == .beginner {
                        if beginnerJourney.isFoundationComplete {
                            BeginnerNextStageCard(
                                profile: appStore.userProfile,
                                completedWorkoutCount: beginnerJourney.completedWorkoutCount,
                                onAction: onOpenPlans
                            )
                        } else {
                            BeginnerJourneyCard(
                                progress: beginnerJourney,
                                onAction: performBeginnerJourneyAction
                            )
                        }
                    }

                    HomeSectionHeader(
                        title: "今日の状態"
                    )

                    NavigationLink {
                        ConditionDashboardView()
                    } label: {
                        ConditionSummaryCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("conditionSummaryCard")

                    DailyRecordChecklistCard(
                        bodyWeightRecorded: appStore.hasBodyMetricEntry(for: .bodyWeight),
                        waistRecorded: appStore.hasBodyMetricEntry(for: .waist),
                        nutritionProgress: DailyNutritionProgress(
                            meals: appStore.mealEntries(),
                            goals: appStore.userProfile.nutritionGoals
                        ),
                        bodyPhotoCount: appStore.bodyPhotoSet() == nil ? 0 : 1,
                        workoutCount: appStore.workoutSessions().count,
                        showsQuickActions: true
                    )

                    BodyKPIDashboard(
                        kinds: BodyMetricKind.allCases,
                        latestEntry: { appStore.latestBodyMetricEntry(for: $0) },
                        goal: { appStore.bodyMetricGoal(for: $0) },
                        tint: metricTint(for:)
                    )

                    AIInsightStatusCard(
                        insight: appStore.aiInsights.first { $0.insightType == .weekly },
                        persona: appStore.userProfile.coachPersona,
                        coachRole: appStore.userProfile.coachType.displayName
                    )

                    HomeSectionHeader(
                        title: "目標と実績"
                    )

                    GoalActionCard(profile: appStore.userProfile) {
                        isShowingGoalPicker = true
                    }

                    HStack(spacing: 10) {
                        CompactStat(title: "計画", value: "\(appStore.plans.count)", suffix: "件", tint: AppTheme.blue)
                        CompactStat(title: "履歴", value: "\(appStore.workoutHistory.count)", suffix: "件", tint: AppTheme.orange)
                        CompactStat(title: "直近", value: latestAchievementText, suffix: "", tint: AppTheme.accent)
                    }
                    }

                }
                .padding(16)
                .padding(.bottom, 96)
            }
            .background(TrainingBackground())
            .navigationTitle("BodyMode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("設定")
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                WorkoutSessionView(session: session)
            }
            .sheet(isPresented: $isShowingGoalPicker) {
                GoalPickerView(selectedGoal: appStore.userProfile.goalType) { goalType in
                    var profile = appStore.userProfile
                    let usedRecommendedCoach = profile.coachType == CoachType.recommended(for: profile.goalType)
                    profile.goalType = goalType
                    if usedRecommendedCoach {
                        profile.coachType = CoachType.recommended(for: goalType)
                    }
                    if !OutcomeStyle.available(for: goalType).contains(profile.outcomeStyle) {
                        profile.outcomeStyle = OutcomeStyle.recommended(for: goalType)
                    }
                    if !goalType.supportsFocusMuscles {
                        profile.focusMuscles = []
                    }
                    appStore.saveUserProfile(profile)
                    isShowingGoalPicker = false
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                ProfileSettingsView(
                    profile: appStore.userProfile,
                    aiSettings: appStore.aiSettings,
                    sensorSettings: appStore.sensorSettings,
                    appearanceSettings: appStore.appearanceSettings
                )
            }
            .sheet(item: $omakaseSheet) { sheet in
                switch sheet {
                case .meal:
                    MealListView(startsWithEditor: true)
                case .bodyMetric(let kind):
                    BodyMetricEntryEditorView(kind: kind)
                case .bodyPhoto:
                    BodyPhotoListView(startsWithEditor: true)
                case .condition:
                    ConditionDashboardView()
                case .why(let action):
                    if let recommendation = appStore.dailyRecommendation() {
                        DailyActionWhyView(
                            action: action,
                            recommendation: recommendation,
                            latestRevision: appStore.latestRecommendationRevision(),
                            coachPersona: appStore.userProfile.coachPersona
                        )
                    }
                }
            }
        }
    }

    private var recommendationObservedContent: some View {
        navigationContent
            .task {
                await prepareDailyRecommendation()
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onChange(of: recommendationProgressToken) {
                guard !isPreparingRecommendation else { return }
                refreshDailyRecommendation()
            }
            .onChange(of: recommendationRuleToken) {
                refreshDailyRecommendation(force: true)
            }
            .onChange(of: appStore.dailyRecommendations) {
                reconcileRecommendationOutput()
            }
    }

    private var recommendationProgressToken: RecommendationProgressToken {
        RecommendationProgressToken(
            health: healthDataManager.snapshot,
            workouts: appStore.workoutHistory,
            meals: appStore.mealEntries,
            bodyMetrics: appStore.bodyMetricEntries,
            bodyPhotos: appStore.bodyPhotoEntries,
            recovery: appStore.subjectiveRecoveryEntries
        )
    }

    private var recommendationRuleToken: RecommendationRuleToken {
        RecommendationRuleToken(
            plans: appStore.plans,
            selection: appStore.dailyWorkoutSelection,
            profile: appStore.userProfile
        )
    }

    private var readinessAssessment: ReadinessAssessment {
        healthDataManager.readinessAssessment(
            recentWorkouts: appStore.workoutHistory,
            subjectiveRecovery: appStore.todaySubjectiveRecovery
        )
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        Task {
            await prepareDailyRecommendation()
        }
    }

    private func progress(for action: DailyAction) -> DailyActionProgress {
        appStore.progress(
            for: action,
            healthSnapshot: healthDataManager.snapshot,
            readinessAssessment: readinessAssessment
        )
    }

    private func prepareDailyRecommendation() async {
        guard !isPreparingRecommendation else { return }
        isPreparingRecommendation = true
        defer { isPreparingRecommendation = false }
        let immediate = appStore.refreshDailyRecommendation(
            healthSnapshot: healthDataManager.snapshot,
            readinessAssessment: readinessAssessment
        )
        DailyRecommendationNotificationManager.schedule(recommendation: immediate)
        syncRecommendationToWatch(immediate)
        if appStore.sensorSettings.healthIntegrationEnabled {
            await healthDataManager.refresh()
        }
        refreshDailyRecommendation()
    }

    private func refreshDailyRecommendation(force: Bool = false) {
        let recommendation = appStore.refreshDailyRecommendation(
            healthSnapshot: healthDataManager.snapshot,
            readinessAssessment: readinessAssessment,
            force: force
        )
        DailyRecommendationNotificationManager.schedule(recommendation: recommendation)
        syncRecommendationToWatch(recommendation)
        requestDailyAIAnalysisIfNeeded(recommendation)
    }

    private func reconcileRecommendationOutput() {
        guard !isPreparingRecommendation,
              appStore.dailyRecommendation() != nil else { return }
        let recommendation = appStore.refreshDailyRecommendation(
            healthSnapshot: healthDataManager.snapshot,
            readinessAssessment: readinessAssessment
        )
        DailyRecommendationNotificationManager.schedule(recommendation: recommendation)
        syncRecommendationToWatch(recommendation)
    }

    private func syncRecommendationToWatch(_ recommendation: DailyRecommendation) {
        watchSyncService.syncDailyRecommendationIfPossible(
            plans: appStore.plans,
            profile: appStore.userProfile,
            sensorSettings: appStore.sensorSettings,
            appearanceSettings: appStore.appearanceSettings,
            recommendation: recommendation
        )
    }

    private func requestDailyAIAnalysisIfNeeded(_ recommendation: DailyRecommendation) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           !ProcessInfo.processInfo.arguments.contains("--stub-ai-trainer") {
            return
        }
        #endif
        guard appStore.shouldRequestDailyAIAnalysis(), !aiTrainerBackgroundService.isSending else { return }
        let context = CoachContextBuilder().build(
            profile: appStore.userProfile,
            sharing: appStore.aiSettings.dataSharing,
            bodyMetrics: appStore.bodyMetricEntries,
            bodyMetricGoals: appStore.bodyMetricGoals,
            meals: appStore.mealEntries,
            bodyPhotos: appStore.bodyPhotoEntries,
            workouts: appStore.workoutHistory,
            gymVisits: appStore.gymVisits,
            subjectiveRecovery: appStore.subjectiveRecoveryEntries,
            healthSnapshot: healthDataManager.snapshot,
            recoveryHistory: healthDataManager.recoveryHistory,
            memories: appStore.coachMemories,
            insights: appStore.aiInsights
        )
        let request = CoachChatRequest(
            coachID: appStore.userProfile.coachType.rawValue,
            message: appStore.dailyRecommendationPrompt(for: recommendation),
            context: context,
            recentMessages: []
        )
        let transmission = AITransmissionRecord(
            purpose: "日次提案の点検",
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames,
            itemCount: context.itemCount
        )
        appStore.saveAITransmission(transmission)
        Task { @MainActor in
            do {
                try await aiTrainerBackgroundService.submitDailyRecommendation(
                    payload: request,
                    transmissionID: transmission.id,
                    settings: appStore.aiSettings,
                    date: recommendation.date
                )
                appStore.markDailyRecommendationAIRequested(at: recommendation.date)
            } catch {
                appStore.updateAITransmission(id: transmission.id, status: .failed)
                AppDiagnostics.shared.record(
                    error: error,
                    category: "daily_recommendation.ai",
                    message: "Failed to queue daily recommendation analysis"
                )
            }
        }
    }

    private func openDailyAction(_ action: DailyAction) {
        appStore.markDailyActionAdopted(action.id)
        switch action.destination {
        case .workout(let planID):
            let plan = planID.flatMap { id in appStore.plans.first { $0.id == id } } ?? appStore.todayPlan
            if let plan {
                activeSession = appStore.makeWorkoutSession(from: plan)
            } else {
                onCreatePlan()
            }
        case .steps, .condition:
            omakaseSheet = .condition
        case .meal:
            omakaseSheet = .meal
        case .bodyMetric(let kind):
            omakaseSheet = .bodyMetric(kind)
        case .bodyPhoto:
            omakaseSheet = .bodyPhoto
        case .none:
            appStore.toggleManualDailyAction(action.id)
        }
    }

    private func replaceDailyAction(_ action: DailyAction) {
        appStore.replaceDailyAction(
            action.id,
            healthSnapshot: healthDataManager.snapshot,
            readinessAssessment: readinessAssessment
        )
    }

    private func openAICoach(for recommendation: DailyRecommendation) {
        guard let action = recommendation.activeActions.first(where: {
            $0.status != .completed && $0.status != .skipped
        }) ?? recommendation.activeActions.first else {
            return
        }
        omakaseSheet = .why(action)
    }

    private var latestAchievementText: String {
        guard let latest = appStore.workoutHistory.first else {
            return "-"
        }

        return AppFormatters.percent(latest.achievementRate)
    }

    private func metricTint(for kind: BodyMetricKind) -> Color {
        switch kind {
        case .bodyWeight: AppTheme.blue
        case .waist: AppTheme.orange
        case .bodyFatPercentage: AppTheme.purple
        }
    }

    private func performBeginnerJourneyAction() {
        switch beginnerJourney.nextAction {
        case .createPlan:
            onCreatePlan()
        case .startWorkout:
            onOpenRecord()
        case .explorePlans:
            onOpenPlans()
        }
    }
}

private struct RecommendationProgressToken: Equatable {
    var health: DailyHealthSnapshot
    var workouts: [WorkoutSession]
    var meals: [MealEntry]
    var bodyMetrics: [BodyMetricEntry]
    var bodyPhotos: [BodyPhotoEntry]
    var recovery: [SubjectiveRecoveryEntry]
}

private struct RecommendationRuleToken: Equatable {
    var plans: [TrainingPlan]
    var selection: DailyWorkoutSelection?
    var profile: UserProfile
}

private enum OmakaseHomeSheet: Identifiable {
    case meal
    case bodyMetric(BodyMetricKind)
    case bodyPhoto
    case condition
    case why(DailyAction)

    var id: String {
        switch self {
        case .meal: "meal"
        case .bodyMetric(let kind): "bodyMetric-\(kind.rawValue)"
        case .bodyPhoto: "bodyPhoto"
        case .condition: "condition"
        case .why(let action): "why-\(action.id.uuidString)"
        }
    }
}

private struct BeginnerNextStageCard: View {
    let profile: UserProfile
    let completedWorkoutCount: Int
    let onAction: () -> Void

    private var progress: BeginnerJourneyProgress {
        BeginnerJourneyProgress(hasPlan: true, completedWorkoutCount: completedWorkoutCount)
    }

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 12) {
                IconBadge(systemImage: "sparkles", tint: AppTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("BEGINNER LEVEL \(progress.level)")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.positive)
                    Text("次は目的別メニュー")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("\(profile.outcomeStyle.displayName)・\(profile.availableEquipment.count)種類の器具")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(completedWorkoutCount)回")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .padding(14)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("beginnerNextStageCard")
        .overlay(alignment: .bottom) {
            if progress.nextLevelWorkoutTarget != nil {
                ProgressView(value: progress.levelProgressValue)
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .offset(y: -4)
            }
        }
    }
}

private struct HomeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(AppTheme.ink)
        .padding(.top, 4)
    }
}

private struct GoalActionCard: View {
    let profile: UserProfile
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                IconBadge(systemImage: profile.outcomeStyle.systemImage, tint: AppTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("目的・目標")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.mutedInk)

                    Text(profile.goalType.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Text("\(profile.outcomeStyle.displayName)・週\(profile.weeklyTrainingDays)日")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(width: 34, height: 34)
            }
            .padding(14)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("目的を変更")
        .accessibilityIdentifier("goalActionCard")
    }
}

private struct GoalPickerView: View {
    let selectedGoal: GoalType
    let onSelect: (GoalType) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(GoalType.allCases) { goalType in
                        Button {
                            onSelect(goalType)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedGoal == goalType ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedGoal == goalType ? AppTheme.accent : AppTheme.mutedInk)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goalType.displayName)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.ink)

                                    Text(goalType.shortAction)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.mutedInk)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("goalOption-\(goalType.rawValue)")
                    }
                } header: {
                    Text("目的モード")
                } footer: {
                    Text("目的に合わせてホームの確認ポイントと次にやることを切り替えます。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("目的を選択")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BeginnerJourneyCard: View {
    let progress: BeginnerJourneyProgress
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemImage: "flag.checkered", tint: AppTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("BEGINNER LEVEL \(progress.level)")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("beginnerJourneyCard")

                    Text(levelTitle)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer()

                Text("\(progress.completedMilestoneCount)/3")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.mutedInk)
            }

            ProgressView(value: progress.progressValue)
                .tint(AppTheme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                BeginnerMissionRow(
                    title: "初心者メニューを作る",
                    isCompleted: progress.hasPlan,
                    isCurrent: !progress.hasPlan
                )
                BeginnerMissionRow(
                    title: "最初のトレーニングを完了",
                    isCompleted: progress.completedWorkoutCount >= 1,
                    isCurrent: progress.hasPlan && progress.completedWorkoutCount == 0
                )
                BeginnerMissionRow(
                    title: "トレーニングを3回完了",
                    isCompleted: progress.completedWorkoutCount >= 3,
                    isCurrent: progress.completedWorkoutCount >= 1 && progress.completedWorkoutCount < 3
                )
            }

            Button(action: onAction) {
                HStack {
                    Image(systemName: actionSystemImage)
                    Text(actionTitle)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("beginnerJourneyActionButton")
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
    }

    private var levelTitle: String {
        switch progress.level {
        case 1: "全身メニューから始める"
        case 2: "3回続けて動きを覚える"
        default: "目的別メニューが解放"
        }
    }

    private var actionTitle: String {
        switch progress.nextAction {
        case .createPlan: "初心者メニューを作る"
        case .startWorkout: "トレーニングを開く"
        case .explorePlans: "目的別メニューを見る"
        }
    }

    private var actionSystemImage: String {
        switch progress.nextAction {
        case .createPlan: "plus.circle.fill"
        case .startWorkout: "play.fill"
        case .explorePlans: "list.bullet.rectangle"
        }
    }
}

private struct BeginnerMissionRow: View {
    let title: String
    let isCompleted: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSystemImage)
                .font(.headline)
                .foregroundStyle(statusColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent || isCompleted ? AppTheme.ink : AppTheme.mutedInk)

            Spacer()

            if isCurrent {
                Text("NEXT")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var statusSystemImage: String {
        if isCompleted {
            return "checkmark.circle.fill"
        }
        return isCurrent ? "circle.inset.filled" : "lock.fill"
    }

    private var statusColor: Color {
        if isCompleted {
            return AppTheme.positive
        }
        return isCurrent ? AppTheme.accent : AppTheme.mutedInk
    }
}

private struct TodayTrainingCard: View {
    let plan: TrainingPlan?
    let completedSessions: [WorkoutSession]
    let onStart: () -> Void
    let onCreatePlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日のメニュー")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.foregroundOnDark)

                    Text(plan?.name ?? "計画を作成しましょう")
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(AppTheme.foregroundOnDark)
                        .lineLimit(2)
                }

                Spacer()

                Text(statusTitle)
                    .font(.footnote.bold())
                    .foregroundStyle(plan == nil ? AppTheme.foregroundOnDark.opacity(0.65) : AppTheme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        completedSessions.isEmpty
                            ? (plan == nil ? AppTheme.foregroundOnDark.opacity(0.12) : AppTheme.accent)
                            : AppTheme.positive,
                        in: Capsule()
                )
            }

            if !completedSessions.isEmpty {
                completedSessionList
            }

            if let plan {
                HStack(spacing: 10) {
                    Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                    Label("\(plan.totalSetCount)セット", systemImage: "checklist")
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.foregroundOnDark)

                Button(action: onStart) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(completedSessions.isEmpty ? "トレーニング開始" : "追加で開始")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.onAccent)
            } else {
                Button(action: onCreatePlan) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("計画を作成")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.onAccent)
                .accessibilityIdentifier("createPlanFromHomeButton")
            }
        }
        .padding(20)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .fill(AppTheme.darkBase)

                VStack(spacing: 8) {
                    ForEach(0..<5) { _ in
                        Rectangle()
                            .fill(AppTheme.foregroundOnDark.opacity(0.06))
                            .frame(width: 150, height: 1)
                    }
                }
                .rotationEffect(.degrees(-28))
                .offset(x: 18, y: -18)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: AppTheme.gymFloor.opacity(0.28), radius: 24, x: 0, y: 16)
    }

    private var statusTitle: String {
        if !completedSessions.isEmpty {
            return "\(completedSessions.count)回完了"
        }
        return plan == nil ? "未設定" : "Ready"
    }

    private var completedSessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(completedSessions) { session in
                NavigationLink {
                    HistoryDetailView(session: session)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.positive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title)
                                .font(.footnote.bold())
                            Text(
                                "\(AppFormatters.shortDateTime.string(from: session.startedAt))・"
                                    + "\(session.completedPlannedSetCount)セット"
                            )
                            .font(.footnote)
                            .foregroundStyle(AppTheme.foregroundOnDark)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.bold())
                    }
                    .foregroundStyle(AppTheme.foregroundOnDark)
                    .padding(9)
                    .background(
                        AppTheme.foregroundOnDark.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayCompletedSession-\(session.id)")
            }
        }
    }
}

private struct CompactStat: View {
    let title: String
    let value: String
    let suffix: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            Capsule()
                .fill(tint)
                .frame(width: 28, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
    }
}

private struct BodyKPIDashboard: View {
    let kinds: [BodyMetricKind]
    let latestEntry: (BodyMetricKind) -> BodyMetricEntry?
    let goal: (BodyMetricKind) -> BodyMetricGoal
    let tint: (BodyMetricKind) -> Color

    var body: some View {
        NavigationLink {
            BodyMetricListView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("身体KPI")
                            .font(.headline)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                ForEach(kinds) { kind in
                    BodyKPIProgressRow(
                        kind: kind,
                        entry: latestEntry(kind),
                        goal: goal(kind),
                        tint: tint(kind)
                    )
                }
            }
            .padding(16)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bodyMetricListLink")
    }
}

private struct AIInsightStatusCard: View {
    let insight: AIInsight?
    let persona: CoachPersona
    let coachRole: String

    var body: some View {
        NavigationLink {
            AIReportView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CoachAvatarView(persona: persona, size: 42, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(persona.displayName)の週次レポート")
                            .font(.headline)
                        Text(coachRole)
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.mutedInk)
                }

                if let insight {
                    Text(insight.outputComment)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2)
                } else {
                    Text("AIサーバーから週次コメントを生成します")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .padding(16)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aiReportLink")
    }
}

private struct BodyKPIProgressRow: View {
    let kind: BodyMetricKind
    let entry: BodyMetricEntry?
    let goal: BodyMetricGoal
    let tint: Color

    private var progress: Double {
        guard let entry,
              let rate = goal.achievementRate(from: entry.value) else {
            return 0
        }

        return rate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.subheadline.bold())
            }

            ProgressView(value: progress)
                .tint(tint)

            Text(detailText)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(1)
        }
    }

    private var valueText: String {
        guard let entry else {
            return "未記録"
        }

        return AppFormatters.metricValue(entry.value, unit: kind.unit)
    }

    private var detailText: String {
        guard let entry else {
            return "最初の値を記録してください"
        }

        guard let target = goal.targetValue,
              let delta = goal.delta(from: entry.value) else {
            return "目標未設定"
        }

        let sign = delta > 0 ? "+" : ""
        return "目標 \(AppFormatters.metricValue(target, unit: kind.unit)) / 差分 \(sign)\(AppFormatters.metricValue(delta, unit: kind.unit))"
    }
}

#Preview {
    HomeView()
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
