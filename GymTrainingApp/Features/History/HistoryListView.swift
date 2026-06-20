import SwiftUI

struct HistoryListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("履歴はまだありません", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("ワークアウトを完了すると、ここから過去の重量・回数を見返せます。")
            }
            .navigationTitle("履歴")
        }
    }
}

#Preview {
    HistoryListView()
}

