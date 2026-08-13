import SwiftUI

struct PlanListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var editorRequest: PlanCreationRequest?
    @State private var isShowingExerciseLibrary = false
    @State private var isShowingAIPlanCoach = false
    @State private var pendingAIPlan: TrainingPlan?
    @State private var planToEdit: TrainingPlan?
    @State private var pendingDeletePlan: TrainingPlan?

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
                        Text("目的・重点部位・使える器具・過去の実績から作成しています。保存前に種目と数値を変更できます。")
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
                            Label("計画はまだありません", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("種目とセット目標を登録して、次のトレーニングを迷わず始めましょう。")
                        } actions: {
                            Button("計画を作成") {
                                startRecommendedCreation()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("createPlanEmptyButton")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("トレーニング計画") {
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("計画")
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
                    .accessibilityLabel("計画を作成")
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
            .confirmationDialog(
                "この計画を削除しますか？",
                isPresented: Binding(
                    get: { pendingDeletePlan != nil },
                    set: { if !$0 { pendingDeletePlan = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let pendingDeletePlan,
                       let index = appStore.plans.firstIndex(where: { $0.id == pendingDeletePlan.id }) {
                        appStore.deletePlans(at: IndexSet(integer: index))
                    }
                    pendingDeletePlan = nil
                }
                Button("キャンセル", role: .cancel) {
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
                    Text(recommendation.plan.exercises.map { $0.exercise.name }.joined(separator: "・"))
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
                    Text("\(persona.displayName)と計画を作る")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("\(coachRole)・\(goalName)")
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
                    Text("種目ライブラリ")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Text("検索・詳細・カスタム種目追加")
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
                        Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                        Label("\(plan.totalSetCount)セット", systemImage: "checklist")
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
