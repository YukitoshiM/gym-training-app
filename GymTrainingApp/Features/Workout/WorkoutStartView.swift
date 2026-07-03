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
                                    CardContainer {
                                        HStack(spacing: 12) {
                                            IconBadge(systemImage: "play.fill", tint: AppTheme.accent)

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

                                            Spacer()

                                            Text("開始")
                                                .font(.caption.bold())
                                                .foregroundStyle(AppTheme.accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .accessibilityIdentifier("startWorkout-\(plan.name)")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pageBackground)
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
