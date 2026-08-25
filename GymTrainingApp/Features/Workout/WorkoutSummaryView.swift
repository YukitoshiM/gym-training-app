import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject private var appStore: AppStore

    let session: WorkoutSession
    let onClose: () -> Void

    @State private var isShowingAIRevision = false
    @State private var revisionResult: PlanRevisionResult?

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        MetricPill(title: L10n.string("training.e79acd05d832", fallback: "達成率"), value: AppFormatters.percent(session.achievementRate), systemImage: "target", tint: AppTheme.accent)
                        MetricPill(title: L10n.string("training.a85ababac45e", fallback: "計画セット"), value: "\(session.completedPlannedSetCount)/\(session.plannedSetCount)", systemImage: "checklist", tint: AppTheme.blue)
                        MetricPill(title: L10n.string("training.922870c3ac56", fallback: "総ボリューム"), value: AppFormatters.volume(session.totalVolume, unit: appStore.userProfile.weightUnit), systemImage: "scalemass", tint: AppTheme.orange)
                        MetricPill(
                            title: L10n.string("training.f85857b6a867", fallback: "目標差"),
                            value: AppFormatters.signedVolume(session.volumeDelta, unit: appStore.userProfile.weightUnit),
                            systemImage: "plusminus",
                            tint: session.volumeDelta >= 0 ? AppTheme.accent : AppTheme.orange
                        )
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section(L10n.string("training.6b602a42b27f", fallback: "種目別")) {
                    ForEach(session.exercises) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.exercise.name)
                                    .font(.headline)
                                Text(L10n.string("training.597a1eba1bab", fallback: "計画 {{value1}}/{{value2}}セット完了 / 達成 {{value3}}/{{value4}}", values: [String(describing: exercise.completedPlannedSetCount), String(describing: exercise.plannedSetCount), String(describing: exercise.achievedPlannedSetCount), String(describing: exercise.plannedSetCount)]))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                Text(L10n.string("training.7f60357273d2", fallback: "目標差 {{value1}}", values: [String(describing: AppFormatters.signedVolume(exercise.volumeDelta, unit: appStore.userProfile.weightUnit))]))
                                    .font(.footnote.bold())
                                    .foregroundStyle(exercise.volumeDelta >= 0 ? AppTheme.positive : AppTheme.orange)
                            }

                            Spacer()

                            Text(exercise.isSkipped ? L10n.string("training.17135f0f1ac6", fallback: "スキップ") : AppFormatters.percent(exercise.achievementRate))
                                .font(.headline)
                                .foregroundStyle(exercise.isSkipped ? AppTheme.mutedInk : AppTheme.ink)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listRowBackground(AppTheme.cardBackground)

                if sourcePlan != nil, let revisionTrigger {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(revisionHeadline, systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text(revisionTrigger.summary)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)

                            Button {
                                isShowingAIRevision = true
                            } label: {
                                Label(
                                    L10n.string("workout_summary.adjust_next_plan_ai", fallback: "次回計画をAIで整える"),
                                    systemImage: "wand.and.stars"
                                )
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("reviewWorkoutPlanWithAIButton")
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(L10n.string("workout_summary.next_session", fallback: "次回"))
                    } footer: {
                        Text(L10n.string("workout_summary.revision_approval_notice", fallback: "変更内容を確認するまで、現在の計画は書き換えません。"))
                    }
                    .listRowBackground(AppTheme.cardBackground)

                    if let revisionResult {
                        Section {
                            Label(revisionResult.message, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.positive)
                            if revisionResult.canUndo, let revisionID = revisionResult.revisionID {
                                Button {
                                    appStore.revertPlanRevision(revisionID)
                                    self.revisionResult = PlanRevisionResult(
                                        message: L10n.string("workout_summary.revision_restored", fallback: "更新前の計画へ戻しました。"),
                                        canUndo: false,
                                        revisionID: revisionID
                                    )
                                } label: {
                                    Label(L10n.string("workout_summary.undo_revision", fallback: "更新を取り消す"), systemImage: "arrow.uturn.backward")
                                }
                                .accessibilityIdentifier("undoAIPlanRevisionButton")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("training.4dce1b477edb", fallback: "完了"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("training.2ea27dba9b9a", fallback: "閉じる"), action: onClose)
                }
            }
            .sheet(isPresented: $isShowingAIRevision) {
                if let sourcePlan {
                    AIPlanCoachView(
                        startingPlan: sourcePlan,
                        launchMode: .automaticRevision,
                        onDeclineRevision: {
                            appStore.rejectPlanRevision(triggerSession: session, originalPlan: sourcePlan)
                            revisionResult = PlanRevisionResult(
                                message: L10n.string("workout_summary.keep_current_plan", fallback: "現在の計画をそのまま続けます。"),
                                canUndo: false,
                                revisionID: nil
                            )
                        },
                        onRevisionDecision: { proposal, asNew in
                            let record = appStore.acceptPlanRevision(
                                triggerSession: session,
                                originalPlan: sourcePlan,
                                revisedPlan: proposal.plan,
                                asNew: asNew,
                                summary: proposal.summary,
                                evidence: proposal.evidence,
                                evidenceStatus: proposal.evidenceStatus
                            )
                            let appliedName = record.revisedPlan?.name ?? proposal.plan.name
                            revisionResult = PlanRevisionResult(
                                message: asNew
                                    ? L10n.string("workout_summary.new_plan_saved", fallback: "「{{value1}}」を新しく保存しました。", values: [appliedName])
                                    : L10n.string("workout_summary.next_plan_updated", fallback: "次回計画を更新しました。"),
                                canUndo: true,
                                revisionID: record.id
                            )
                        }
                    ) { _ in }
                }
            }
        }
    }

    private var sourcePlan: TrainingPlan? {
        session.sourcePlanID.flatMap { id in appStore.plans.first { $0.id == id } }
    }

    private var revisionTrigger: PlanRevisionProposal? {
        appStore.pendingPlanRevision(for: session.id)
    }

    private var revisionHeadline: String {
        if session.achievementRate >= 0.9 {
            return L10n.string("workout_summary.revision_headline_met", fallback: "達成できています。次の負荷を確認しましょう。")
        }
        if session.achievementRate < 0.7 {
            return L10n.string("workout_summary.revision_headline_missed", fallback: "少し届かなかったので、次回を調整できます。")
        }
        return L10n.string("workout_summary.revision_headline_ready", fallback: "今日の実績を次回へ反映できます。")
    }
}

private struct PlanRevisionResult {
    var message: String
    var canUndo: Bool
    var revisionID: UUID?
}

struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            Text(value)
                .font(.title2.bold())
        }
    }
}

#Preview {
    WorkoutSummaryView(
        session: WorkoutSession(plan: TrainingPlan(
            name: L10n.string("training.d30ca9b91ccb", fallback: "胸の日"),
            exercises: [
                PlanExercise(exercise: PresetExerciseStore.exercises[0], sortOrder: 0)
            ]
        )),
        onClose: {}
    )
    .environmentObject(AppStore())
}
