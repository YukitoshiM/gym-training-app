import SwiftUI

struct WorkoutStartView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            Group {
                List {
                    Section {
                        Button {
                            activeSession = WorkoutSession(
                                title: "フリートレーニング",
                                sourcePlanID: nil,
                                exercises: []
                            )
                        } label: {
                            CardContainer {
                                HStack(spacing: 12) {
                                    IconBadge(systemImage: "plus.circle.fill", tint: AppTheme.orange)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("フリートレーニング")
                                            .font(.headline)
                                        Text("計画なしで種目を追加して記録します")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }

                                    Spacer()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("startFreeWorkoutButton")
                    }

                    if !appStore.plans.isEmpty {
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
                                                .foregroundStyle(AppTheme.mutedInk)
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.pageBackground)
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
