import SwiftUI

struct RootTabView: View {
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

            WorkoutStartView()
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
}

#Preview {
    RootTabView()
}

