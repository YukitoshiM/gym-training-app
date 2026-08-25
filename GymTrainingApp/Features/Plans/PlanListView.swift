import SwiftUI

struct PlanListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var editorRequest: PlanCreationRequest?
    @State private var isShowingExerciseLibrary = false
    @State private var isShowingAIPlanCoach = false
    @State private var pendingAIPlan: TrainingPlan?
    @State private var planToEdit: TrainingPlan?
    @State private var pendingDeletePlan: TrainingPlan?
    @State private var revisionToReview: PlanRevisionProposal?

    let creationRequest: PlanCreationRequest?
    let onCreationRequestHandled: () -> Void

    init(
        creationRequest: PlanCreationRequest? = nil,
        onCreationRequestHandled: @escaping () -> Void = {}
    ) {
        self.creationRequest = creationRequest
        self.onCreationRequestHandled = onCreationRequestHandled
    }

    var body: some View {
        NavigationStack {
            List {
                if let pendingRevision = appStore.planRevisionProposals.first(where: { $0.decision == .pending }) {
                    Section {
                        Button {
                            revisionToReview = pendingRevision
                        } label: {
                            PlanRevisionPromptRow(
                                proposal: pendingRevision,
                                coachName: appStore.userProfile.coachPersona.displayName
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pendingPlanRevisionButton")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        isShowingAIPlanCoach = true
                    } label: {
                        AIPlanBuilderRow(
                            persona: appStore.userProfile.coachPersona,
                            coachRole: appStore.userProfile.coachType.displayName,
                            goalName: appStore.userProfile.outcomeStyle.displayName
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openAIPlanCoachButton")
                    .appTourTarget(.planCoach)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if !beginnerRecommendations.isEmpty {
                    Section {
                        ForEach(beginnerRecommendations) { recommendation in
                            Button {
                                editorRequest = .beginnerProgression(recommendation.plan)
                            } label: {
                                BeginnerRecommendationRow(recommendation: recommendation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("beginnerRecommendation-\(recommendation.id)")
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("BEGINNER LEVEL \(beginnerProgress.level)")
                    } footer: {
                        Text(L10n.string("training.d6713c7cb074", fallback: "目的・重点部位・使える器具・過去の実績から作成しています。保存前に種目と数値を変更できます。"))
                    }
                }

                Section {
                    Button {
                        isShowingExerciseLibrary = true
                    } label: {
                        ExerciseLibraryRow(exerciseCount: appStore.allExercises.count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exerciseLibraryLink")
                    .appTourTarget(.exerciseLibrary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if appStore.plans.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(L10n.string("training.75c83d4d34c6", fallback: "計画はまだありません"), systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(L10n.string("training.c1eb249e0b6c", fallback: "種目とセット目標を登録して、次のトレーニングを迷わず始めましょう。"))
                        } actions: {
                            Button(L10n.string("training.7c36c155b82c", fallback: "計画を作成")) {
                                startRecommendedCreation()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("createPlanEmptyButton")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section(L10n.string("training.4f1a5e5dfc4f", fallback: "トレーニング計画")) {
                        ForEach(appStore.plans) { plan in
                            Button {
                                planToEdit = plan
                            } label: {
                                PlanRow(plan: plan)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: confirmDeletePlan)
                    }
                }

                let decidedRevisions = appStore.planRevisionProposals.filter { $0.decision != .pending }
                if !decidedRevisions.isEmpty {
                    Section(L10n.string("training.ai_revision_history", fallback: "AI見直し履歴")) {
                        ForEach(decidedRevisions.prefix(5)) { proposal in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(proposal.revisedPlan?.name ?? proposal.originalPlan.name)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(planRevisionDecisionLabel(proposal.decision))
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.accent)
                                }
                                Text(proposal.summary)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                if proposal.effectiveness != .unknown {
                                    Label(
                                        planRevisionEffectivenessLabel(proposal.effectiveness),
                                        systemImage: proposal.effectiveness == .improved ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(proposal.effectiveness == .improved ? AppTheme.positive : AppTheme.mutedInk)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("training.84447148c208", fallback: "計画"))
            .navigationDestination(isPresented: $isShowingExerciseLibrary) {
                ExerciseListView(embedsInNavigationStack: false)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRequest = .blank
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.string("training.7c36c155b82c", fallback: "計画を作成"))
                    .accessibilityIdentifier("createPlanToolbarButton")
                }
            }
            .sheet(item: $editorRequest, onDismiss: onCreationRequestHandled) { request in
                PlanEditorView(plan: request.draft, mode: request.mode) {
                    editorRequest = nil
                }
            }
            .sheet(item: $planToEdit) { plan in
                PlanEditorView(plan: plan) {
                    planToEdit = nil
                }
            }
            .sheet(isPresented: $isShowingAIPlanCoach, onDismiss: presentPendingAIPlan) {
                AIPlanCoachView { plan in
                    pendingAIPlan = plan
                }
            }
            .sheet(item: $revisionToReview) { revision in
                if let session = appStore.workoutHistory.first(where: { $0.id == revision.triggerSessionID }) {
                    AIPlanCoachView(
                        startingPlan: revision.originalPlan,
                        launchMode: .automaticRevision,
                        onDeclineRevision: {
                            appStore.rejectPlanRevision(
                                triggerSession: session,
                                originalPlan: revision.originalPlan
                            )
                        },
                        onRevisionDecision: { proposal, asNew in
                            appStore.acceptPlanRevision(
                                triggerSession: session,
                                originalPlan: revision.originalPlan,
                                revisedPlan: proposal.plan,
                                asNew: asNew,
                                summary: proposal.summary,
                                evidence: proposal.evidence,
                                evidenceStatus: proposal.evidenceStatus
                            )
                        }
                    ) { _ in }
                }
            }
            .confirmationDialog(
                L10n.string("training.6d940b85a589", fallback: "この計画を削除しますか？"),
                isPresented: Binding(
                    get: { pendingDeletePlan != nil },
                    set: { if !$0 { pendingDeletePlan = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.string("training.ac806fcfe196", fallback: "削除"), role: .destructive) {
                    if let pendingDeletePlan,
                       let index = appStore.plans.firstIndex(where: { $0.id == pendingDeletePlan.id }) {
                        appStore.deletePlans(at: IndexSet(integer: index))
                    }
                    pendingDeletePlan = nil
                }
                Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル"), role: .cancel) {
                    pendingDeletePlan = nil
                }
            }
            .onAppear {
                presentRequestedCreationIfNeeded()
            }
            .onChange(of: creationRequest?.id) { _, _ in
                presentRequestedCreationIfNeeded()
            }
        }
    }

    private func presentPendingAIPlan() {
        guard let pendingAIPlan else { return }
        self.pendingAIPlan = nil
        editorRequest = .aiCoach(pendingAIPlan)
    }

    private func startRecommendedCreation() {
        if appStore.userProfile.experienceLevel == .beginner {
            editorRequest = .beginnerStarter(appStore.makeBeginnerStarterPlan())
        } else {
            editorRequest = .blank
        }
    }

    private var beginnerProgress: BeginnerJourneyProgress {
        BeginnerJourneyProgress(
            hasPlan: !appStore.plans.isEmpty,
            completedWorkoutCount: appStore.workoutHistory.filter(\.isCompleted).count
        )
    }

    private var beginnerRecommendations: [BeginnerProgramRecommendation] {
        guard appStore.userProfile.experienceLevel == .beginner else { return [] }
        return appStore.makeBeginnerProgramRecommendations()
    }

    private func presentRequestedCreationIfNeeded() {
        guard editorRequest == nil, let creationRequest else { return }
        editorRequest = creationRequest
    }

    private func confirmDeletePlan(at offsets: IndexSet) {
        pendingDeletePlan = offsets.first.map { appStore.plans[$0] }
    }

    private func planRevisionDecisionLabel(_ decision: PlanRevisionDecision) -> String {
        switch decision {
        case .pending: return L10n.string("training.ai_revision_pending", fallback: "確認待ち")
        case .acceptedAsNew: return L10n.string("training.ai_revision_saved_new", fallback: "新規保存")
        case .acceptedAsUpdate: return L10n.string("training.ai_revision_updated", fallback: "更新")
        case .rejected: return L10n.string("training.ai_revision_skipped", fallback: "見送り")
        case .reverted: return L10n.string("training.ai_revision_reverted", fallback: "取消済み")
        }
    }

    private func planRevisionEffectivenessLabel(_ effectiveness: PlanRevisionEffectiveness) -> String {
        switch effectiveness {
        case .unknown: return L10n.string("training.ai_revision_awaiting_result", fallback: "評価待ち")
        case .improved: return L10n.string("training.ai_revision_improved", fallback: "次回実績が改善")
        case .unchanged: return L10n.string("training.ai_revision_unchanged", fallback: "次回実績は同程度")
        case .worsened: return L10n.string("training.ai_revision_review_again", fallback: "次回は再調整候補")
        }
    }
}

private struct PlanRevisionPromptRow: View {
    let proposal: PlanRevisionProposal
    let coachName: String

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "sparkles", tint: AppTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string(
                        "training.ai_revision_from_coach",
                        fallback: "{{value1}}から計画の見直し",
                        values: [coachName]
                    ))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(proposal.summary)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct BeginnerRecommendationRow: View {
    let recommendation: BeginnerProgramRecommendation

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "arrow.up.forward", tint: AppTheme.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2)
                    Text(recommendation.plan.exercises.map { $0.exercise.name }.joined(separator: L10n.string("training.a2333d5b2d78", fallback: "・")))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AIPlanBuilderRow: View {
    let persona: CoachPersona
    let coachRole: String
    let goalName: String

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                CoachAvatarView(persona: persona, size: 50, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("training.a7f361c7373f", fallback: "{{value1}}と計画を作る", values: [String(describing: persona.displayName)]))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(L10n.string("training.82f49e5f2763", fallback: "{{value1}}・{{value2}}", values: [String(describing: coachRole), String(describing: goalName)]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ExerciseLibraryRow: View {
    let exerciseCount: Int

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "dumbbell", tint: AppTheme.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("training.640e7f5d70f7", fallback: "種目ライブラリ"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Text(L10n.string("training.379774690c05", fallback: "検索・詳細・カスタム種目追加"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer(minLength: 6)

                Text("\(exerciseCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)

                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "list.bullet.rectangle", tint: AppTheme.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)

                    Text(plan.exercises.map { $0.exercise.name }.joined(separator: "、"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label(L10n.string("training.70d17961dda6", fallback: "{{value1}}種目", values: [String(describing: plan.exercises.count)]), systemImage: "dumbbell")
                        Label(L10n.string("training.a6a1cc3a4bfc", fallback: "{{value1}}セット", values: [String(describing: plan.totalSetCount)]), systemImage: "checklist")
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.7))
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    PlanListView()
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
