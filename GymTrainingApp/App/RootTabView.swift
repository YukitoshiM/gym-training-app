import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var watchPlanSyncService: WatchPlanSyncService
    @EnvironmentObject private var gymLocationManager: GymLocationManager

    var body: some View {
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
        .tint(AppTheme.accent)
        .onAppear {
            watchPlanSyncService.bind(appStore: appStore)
            gymLocationManager.bind(appStore: appStore)
        }
        .alert(
            "予定したジム記録がありません",
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
}

#Preview {
    RootTabView()
        .environmentObject(AppStore())
        .environmentObject(WatchPlanSyncService())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
