import SwiftUI

struct WorkoutStartView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            Group {
                if appStore.plans.isEmpty {
                    ContentUnavailableView {
                        Label("開始できる計画がありません", systemImage: "play.circle")
                    } description: {
                        Text("計画タブで種目とセット目標を登録すると、ここから記録を始められます。")
                    }
                } else {
                    List {
                        Section("計画から開始") {
                            ForEach(appStore.plans) { plan in
                                Button {
                                    activeSession = WorkoutSession(plan: plan)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(plan.name)
                                            .font(.headline)

                                        HStack(spacing: 10) {
                                            Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                                            Label("\(plan.totalSetCount)セット", systemImage: "checklist")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("startWorkout-\(plan.name)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("記録")
            .fullScreenCover(item: $activeSession) { session in
                WorkoutSessionView(session: session)
            }
        }
    }
}

#Preview {
    WorkoutStartView()
        .environmentObject(AppStore())
}
