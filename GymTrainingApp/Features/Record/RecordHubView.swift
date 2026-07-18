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
        appStore.bodyPhotoEntries().count
    }

    private var workoutCount: Int {
        appStore.workoutSessions().count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if gymLocationManager.isAtGym, let todayPlan = appStore.todayPlan {
                        GymArrivalPlanCard(plan: todayPlan) {
                            activeSession = WorkoutSession(plan: todayPlan)
                        }
                    }

                    DailyRecordChecklistCard(
                        bodyWeightRecorded: appStore.hasBodyMetricEntry(for: .bodyWeight),
                        waistRecorded: appStore.hasBodyMetricEntry(for: .waist),
                        mealCount: mealCount,
                        bodyPhotoCount: bodyPhotoCount,
                        workoutCount: workoutCount
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "今日の入力", subtitle: "先に短い記録を済ませて、あとでまとめて振り返れます。")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            NavigationLink {
                                BodyMetricDetailView(kind: .bodyWeight)
                            } label: {
                                RecordQuickActionCard(
                                    title: "体重",
                                    detail: appStore.hasBodyMetricEntry(for: .bodyWeight) ? "記録済み" : "追加する",
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
                                    title: "腹囲",
                                    detail: appStore.hasBodyMetricEntry(for: .waist) ? "記録済み" : "追加する",
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
                                    title: "食事",
                                    detail: mealCount > 0 ? "\(mealCount)件" : "追加する",
                                    systemImage: "fork.knife",
                                    tint: AppTheme.orange,
                                    isCompleted: mealCount > 0
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubMealLink")

                            NavigationLink {
                                BodyPhotoListView()
                            } label: {
                                RecordQuickActionCard(
                                    title: "体型写真",
                                    detail: bodyPhotoCount > 0 ? "\(bodyPhotoCount)件" : "追加する",
                                    systemImage: "camera",
                                    tint: AppTheme.purple,
                                    isCompleted: bodyPhotoCount > 0
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordHubBodyPhotoLink")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "トレーニング", subtitle: "計画から開始するか、その場で種目を追加して記録します。")

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
                                        preferredPlanID: appStore.todayPlan?.id
                                    )
                                }
                            )
                        }

                        Button {
                            activeSession = WorkoutSession(
                                title: "フリートレーニング",
                                sourcePlanID: nil,
                                exercises: []
                            )
                        } label: {
                            WorkoutStartCard(
                                title: "フリートレーニング",
                                detail: "計画なしで種目を追加",
                                systemImage: "plus.circle.fill",
                                tint: AppTheme.orange,
                                trailingText: "開始"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("startFreeWorkoutButton")

                        if appStore.plans.isEmpty {
                            NavigationLink {
                                PlanListView()
                            } label: {
                                WorkoutStartCard(
                                    title: "計画を作成",
                                    detail: "よく使うメニューを登録",
                                    systemImage: "list.bullet.rectangle",
                                    tint: AppTheme.blue,
                                    trailingText: "作成"
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(appStore.plans) { plan in
                                Button {
                                    activeSession = WorkoutSession(plan: plan)
                                } label: {
                                    WorkoutStartCard(
                                        title: plan.name,
                                        detail: "\(plan.exercises.count)種目 / \(plan.totalSetCount)セット",
                                        systemImage: "play.fill",
                                        tint: AppTheme.accent,
                                        trailingText: "開始"
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
            .navigationTitle("記録")
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
                IconBadge(systemImage: "mappin.and.ellipse", tint: .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ジムに到着しました")
                        .font(.headline)
                    Text("今日: \(plan.name)・\(plan.totalSetCount)セット")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityLabel("今日のメニューを開始")
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
                        Text("登録済みメニュー \(plans.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        onSend()
                    } label: {
                        Label("送信", systemImage: "arrow.up.forward.app")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .accessibilityLabel("Apple Watchへメニューを同期")
                    .accessibilityIdentifier("sendPlanToWatchButton")
                }

                Text(state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Label("今日のメニュー", systemImage: "calendar.badge.checkmark")
                            .font(.caption.bold())
                        Spacer()
                        Text(selectedPlanName)
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(AppTheme.pageBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("watchTodayPlanMenu")
            }
        }
    }

    private var selectedPlanName: String {
        plans.first(where: { $0.id == selectedPlanID })?.name ?? plans.first?.name ?? "未選択"
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    IconBadge(systemImage: isCompleted ? "checkmark.circle.fill" : systemImage, tint: isCompleted ? .green : tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.caption.bold())
                        .foregroundStyle(isCompleted ? .green : .secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(trailingText)
                    .font(.caption.bold())
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
