import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gym Training")
                            .font(.title2.bold())
                        Text("アルファ版の中核体験を作成中")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("現在") {
                    LabeledContent("計画", value: "\(appStore.plans.count)件")
                    LabeledContent("履歴", value: "\(appStore.workoutHistory.count)件")

                    if let latest = appStore.workoutHistory.first {
                        LabeledContent("直近", value: latest.title)
                        LabeledContent("達成率", value: AppFormatters.percent(latest.achievementRate))
                    }
                }

                Section("Alpha") {
                    Label("計画を作る", systemImage: "checkmark.circle")
                    Label("計画から記録する", systemImage: "checkmark.circle")
                    Label("履歴で振り返る", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("ホーム")
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppStore())
}
