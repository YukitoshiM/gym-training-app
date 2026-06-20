import SwiftUI

struct PlanListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("計画はまだありません", systemImage: "list.bullet.rectangle")
            } description: {
                Text("次はユーザーストーリー US-015〜019 と US-107〜111 に沿って、計画作成を実装します。")
            } actions: {
                Button("計画作成を始める") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
            .navigationTitle("計画")
        }
    }
}

#Preview {
    PlanListView()
}

