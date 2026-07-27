import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var watchPlanSyncService: WatchPlanSyncService
    @EnvironmentObject private var gymLocationManager: GymLocationManager
    @State private var selectedTab: RootTab = .home

    var body: some View {
        rootContent
            .tint(AppTheme.accent)
            .onAppear {
                watchPlanSyncService.bind(appStore: appStore)
                gymLocationManager.bind(appStore: appStore)
            }
            .alert(
                "予定したトレーニング記録がありません",
                isPresented: Binding(
                    get: { appStore.pendingMissedGymPlan != nil },
                    set: { if !$0 { appStore.resolveMissedGymPlan(rescheduleForToday: false) } }
                )
            ) {
                Button("今日へ変更") {
                    appStore.resolveMissedGymPlan(rescheduleForToday: true)
                }
                Button("実施しなかった", role: .cancel) {
                    appStore.resolveMissedGymPlan(rescheduleForToday: false)
                }
            } message: {
                Text("\(appStore.pendingMissedGymPlanName ?? "選択したメニュー")の予定日に、ジム訪問またはトレーニング実績が見つかりませんでした。")
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if #available(iOS 26.0, *) {
            VStack(spacing: 0) {
                selectedTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 0) {
                    ForEach(RootTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 19, weight: .semibold))
                                Text(tab.title)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(selectedTab == tab ? AppTheme.accent : AppTheme.mutedInk)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityIdentifier("rootTab-\(tab.title)")
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
                .background(AppTheme.cardBackground)
            }
            .background(AppTheme.cardBackground.ignoresSafeArea(edges: .bottom))
        } else {
            systemTabView
        }
    }

    private var systemTabView: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }

            PlanListView()
                .tabItem {
                    Label("計画", systemImage: "list.bullet.rectangle")
                }

            RecordHubView()
                .tabItem {
                    Label("記録", systemImage: "figure.strengthtraining.traditional")
                }

            HistoryListView()
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }

            ExerciseListView()
                .tabItem {
                    Label("種目", systemImage: "dumbbell")
                }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .plans:
            PlanListView()
        case .record:
            RecordHubView()
        case .history:
            HistoryListView()
        case .exercises:
            ExerciseListView()
        }
    }
}

private enum RootTab: String, CaseIterable, Identifiable {
    case home
    case plans
    case record
    case history
    case exercises

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "ホーム"
        case .plans: "計画"
        case .record: "記録"
        case .history: "履歴"
        case .exercises: "種目"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .plans: "list.bullet.rectangle"
        case .record: "figure.strengthtraining.traditional"
        case .history: "clock.arrow.circlepath"
        case .exercises: "dumbbell"
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppStore())
        .environmentObject(WatchPlanSyncService())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
