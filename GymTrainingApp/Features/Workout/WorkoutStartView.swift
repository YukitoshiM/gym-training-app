import SwiftUI

struct WorkoutStartView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("計画から開始", systemImage: "play.circle")
                    Label("フリートレーニング", systemImage: "plus.circle")
                } footer: {
                    Text("アルファ版では、まず計画から開始する記録フローを作ります。")
                }
            }
            .navigationTitle("記録")
        }
    }
}

#Preview {
    WorkoutStartView()
}

