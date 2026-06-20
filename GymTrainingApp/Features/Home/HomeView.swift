import SwiftUI

struct HomeView: View {
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

                Section("Alpha") {
                    Label("計画を作る", systemImage: "list.bullet.rectangle")
                    Label("計画から記録する", systemImage: "figure.strengthtraining.traditional")
                    Label("履歴で振り返る", systemImage: "clock.arrow.circlepath")
                }
            }
            .navigationTitle("ホーム")
        }
    }
}

#Preview {
    HomeView()
}
