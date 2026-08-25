import SwiftUI

struct RecordHubView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var watchSyncService: WatchPlanSyncService
    @EnvironmentObject private var gymLocationManager: GymLocationManager
    @State private var activeSession: WorkoutSession?

    private var mealCount: Int {
        appStore.mealEntries().count
    }

    private var bodyPhotoCount: Int {
        appStore.bodyPhotoSet() == nil ? 0 : 1
    }

    private var workoutCount: Int {
        appStore.workoutSessions().count
    }

    private var nutritionProgress: DailyNutritionProgress {
        DailyNutritionProgress(
            meals: appStore.mealEntries(),
            goals: appStore.userProfile.nutritionGoals
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if gymLocationManager.isAtGym, let todayPlan = appStore.todayPlan {
                        GymArrivalPlanCard(plan: todayPlan) {
                            activeSession = appStore.makeWorkoutSession(from: todayPlan)
                        }
                    }

                    if let liveWorkout = watchSyncService.liveWatchWorkout {
                        WatchLiveWorkoutCard(snapshot: liveWorkout)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: L10n.string("core_ui.e75bf42e2b4a", fallback: "今日の入力"), subtitle: L10n.string("core_ui.5741ec6a7cf6", fallback: "先に短い記録を済ませて、あとでまとめて振り返れます。"))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            NavigationLink {
                                BodyMetricDetailView(kind: .bodyWeight)
                            } label: {
                                RecordQuickActionCard(
                                    title: L10n.string("core_ui.d05d75dc142b", fallback: "体重"),
                                    detail: appStore.hasBodyMetricEntry(for: .bodyWeight) ? L10n.string("core_ui.da6af7f58be0", fallback: "記録済み") : L10n.string("core_ui.27259dff554d", fallback: "追加する"),
                                    systemImage: "scalemass",
                                    tint: AppTheme.blue,
                                    isCompleted: appStore.hasBodyMetricEntry(for: .bodyWeight)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubBodyWeightLink")

                            NavigationLink {
                                BodyMetricDetailView(kind: .waist)
                            } label: {
                                RecordQuickActionCard(
                                    title: L10n.string("core_ui.424306f5227a", fallback: "腹囲"),
                                    detail: appStore.hasBodyMetricEntry(for: .waist) ? L10n.string("core_ui.da6af7f58be0", fallback: "記録済み") : L10n.string("core_ui.27259dff554d", fallback: "追加する"),
                                    systemImage: "figure.core.training",
                                    tint: AppTheme.orange,
                                    isCompleted: appStore.hasBodyMetricEntry(for: .waist)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubWaistLink")

                            NavigationLink {
                                MealListView()
                            } label: {
                                RecordQuickActionCard(
                                    title: L10n.string("core_ui.e8a52146d9dc", fallback: "食事"),
                                    detail: L10n.string("core_ui.5e0934899b21", fallback: "{{value1}}/{{value2}}回", values: [String(describing: mealCount), String(describing: nutritionProgress.goals.mealCount)]),
                                    systemImage: "fork.knife",
                                    tint: AppTheme.orange,
                                    isCompleted: nutritionProgress.isMealCountAchieved
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubMealLink")

                            NavigationLink {
                                BodyPhotoListView()
                            } label: {
                                RecordQuickActionCard(
                                    title: L10n.string("core_ui.910d79f7cbf5", fallback: "体型写真"),
                                    detail: bodyPhotoCount > 0 ? L10n.string("core_ui.f913cce82a70", fallback: "{{value1}}件", values: [String(describing: bodyPhotoCount)]) : L10n.string("core_ui.27259dff554d", fallback: "追加する"),
                                    systemImage: "camera",
                                    tint: AppTheme.purple,
                                    isCompleted: bodyPhotoCount > 0
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubBodyPhotoLink")
                        }
                        .appTourTarget(.recordQuickActions)
                    }

                    DailyRecordChecklistCard(
                        bodyWeightRecorded: appStore.hasBodyMetricEntry(for: .bodyWeight),
                        waistRecorded: appStore.hasBodyMetricEntry(for: .waist),
                        nutritionProgress: nutritionProgress,
                        bodyPhotoCount: bodyPhotoCount,
                        workoutCount: workoutCount
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: L10n.string("core_ui.36b391f81e59", fallback: "トレーニング"), subtitle: L10n.string("core_ui.0bb8af30fad6", fallback: "計画から開始するか、その場で種目を追加して記録します。"))

                        if !appStore.plans.isEmpty {
                            WatchPlanSyncCard(
                                plans: appStore.plans,
                                selectedPlanID: appStore.todayPlan?.id,
                                state: watchSyncService.state,
                                onSelectPlan: { appStore.selectTodayPlan($0) },
                                onSend: {
                                    watchSyncService.send(
                                        plans: appStore.plans,
                                        profile: appStore.userProfile,
                                        sensorSettings: appStore.sensorSettings,
                                        appearanceSettings: appStore.appearanceSettings,
                                        preferredPlanID: appStore.todayPlan?.id,
                                        dailyRecommendation: appStore.dailyRecommendation()
                                    )
                                }
                            )
                        }

                        Button {
                            activeSession = WorkoutSession(
                                title: L10n.string("core_ui.e517c836f842", fallback: "フリートレーニング"),
                                sourcePlanID: nil,
                                exercises: []
                            )
                        } label: {
                            WorkoutStartCard(
                                title: L10n.string("core_ui.e517c836f842", fallback: "フリートレーニング"),
                                detail: L10n.string("core_ui.172cd4e16deb", fallback: "計画なしで種目を追加"),
                                systemImage: "plus.circle.fill",
                                tint: AppTheme.orange,
                                trailingText: L10n.string("core_ui.f5f5c6e6cc80", fallback: "開始")
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("startFreeWorkoutButton")

                        if appStore.plans.isEmpty {
                            NavigationLink {
                                PlanListView()
                            } label: {
                                WorkoutStartCard(
                                    title: L10n.string("core_ui.636a7ce9c4c4", fallback: "計画を作成"),
                                    detail: L10n.string("core_ui.8f6c619d1202", fallback: "よく使うメニューを登録"),
                                    systemImage: "list.bullet.rectangle",
                                    tint: AppTheme.blue,
                                    trailingText: L10n.string("core_ui.f37338c0fef4", fallback: "作成")
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(appStore.plans) { plan in
                                Button {
                                    activeSession = appStore.makeWorkoutSession(from: plan)
                                } label: {
                                    WorkoutStartCard(
                                        title: plan.name,
                                        detail: L10n.string("core_ui.cd89a1bc8f6a", fallback: "{{value1}}種目 / {{value2}}セット", values: [String(describing: plan.exercises.count), String(describing: plan.totalSetCount)]),
                                        systemImage: "play.fill",
                                        tint: AppTheme.accent,
                                        trailingText: L10n.string("core_ui.f5f5c6e6cc80", fallback: "開始")
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("startWorkout-\(plan.name)")
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 96)
            }
            .background(TrainingBackground())
            .navigationTitle(L10n.string("core_ui.725fe331d7f6", fallback: "記録"))
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $activeSession) { session in
                WorkoutSessionView(session: session)
            }
        }
    }
}

private struct GymArrivalPlanCard: View {
    let plan: TrainingPlan
    let onStart: () -> Void

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "mappin.and.ellipse", tint: AppTheme.positive)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("core_ui.ae6db79774b7", fallback: "ジムに到着しました"))
                        .font(.headline)
                    Text(L10n.string("core_ui.fc9d4f61d361", fallback: "今日: {{value1}}・{{value2}}セット", values: [String(describing: plan.name), String(describing: plan.totalSetCount)]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
                Spacer()
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.positive)
                .accessibilityLabel(L10n.string("core_ui.a13dde79fbc2", fallback: "今日のメニューを開始"))
                .accessibilityIdentifier("startArrivedGymPlanButton")
            }
        }
        .accessibilityIdentifier("gymArrivalPlanCard")
    }
}

private struct WatchPlanSyncCard: View {
    let plans: [TrainingPlan]
    let selectedPlanID: UUID?
    let state: WatchPlanSyncService.SyncState
    let onSelectPlan: (UUID) -> Void
    let onSend: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: state.systemImage, tint: tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Watch")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(L10n.string("core_ui.29ac6f9dcd7c", fallback: "登録済みメニュー {{value1}}件", values: [String(describing: plans.count)]))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        onSend()
                    } label: {
                        Label(L10n.string("core_ui.9bf8130ba8a1", fallback: "送信"), systemImage: "arrow.up.forward.app")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .accessibilityLabel(L10n.string("core_ui.a6e1ba4bb69f", fallback: "Apple Watchへメニューを同期"))
                    .accessibilityIdentifier("sendPlanToWatchButton")
                }

                Text(state.message)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Menu {
                    ForEach(plans) { plan in
                        Button {
                            onSelectPlan(plan.id)
                        } label: {
                            if plan.id == selectedPlanID {
                                Label(plan.name, systemImage: "checkmark")
                            } else {
                                Text(plan.name)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label(L10n.string("core_ui.b82b1b7a064a", fallback: "今日のメニュー"), systemImage: "calendar.badge.checkmark")
                            .font(.footnote.bold())
                        Spacer()
                        Text(selectedPlanName)
                            .font(.footnote)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppTheme.pageBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel(L10n.string("core_ui.b82b1b7a064a", fallback: "今日のメニュー"))
                .accessibilityValue(selectedPlanName)
                .accessibilityIdentifier("watchTodayPlanMenu")
            }
        }
    }

    private var selectedPlanName: String {
        plans.first(where: { $0.id == selectedPlanID })?.name ?? plans.first?.name ?? L10n.string("core_ui.b5bf4c52186f", fallback: "未選択")
    }

    private var tint: Color {
        switch state {
        case .idle, .ready, .sent, .received:
            AppTheme.accent
        case .sending:
            AppTheme.blue
        case .unavailable, .failed:
            AppTheme.orange
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
    }
}

private struct RecordQuickActionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isCompleted: Bool

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconBadge(systemImage: isCompleted ? "checkmark.circle.fill" : systemImage, tint: isCompleted ? AppTheme.positive : tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.mutedInk)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.footnote.bold())
                        .foregroundStyle(isCompleted ? AppTheme.positive : AppTheme.mutedInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WorkoutStartCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let trailingText: String

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Text(trailingText)
                    .font(.footnote.bold())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: Capsule())
            }
        }
    }
}

#Preview {
    RecordHubView()
        .environmentObject(AppStore())
        .environmentObject(WatchPlanSyncService())
        .environmentObject(GymLocationManager())
}
