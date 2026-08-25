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
                                title: L10n.string("training.82b0d9b842e2", fallback: "フリートレーニング"),
                                sourcePlanID: nil,
                                exercises: []
                            )
                        } label: {
                            CardContainer {
                                HStack(spacing: 12) {
                                    IconBadge(systemImage: "plus.circle.fill", tint: AppTheme.orange)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L10n.string("training.82b0d9b842e2", fallback: "フリートレーニング"))
                                            .font(.headline)
                                        Text(L10n.string("training.41fee4a5554c", fallback: "計画なしで種目を追加して記録します"))
                                            .font(.footnote)
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
                        Section(L10n.string("training.170899739631", fallback: "計画から開始")) {
                            ForEach(appStore.plans) { plan in
                                Button {
                                    activeSession = appStore.makeWorkoutSession(from: plan)
                                } label: {
                                    CardContainer {
                                        HStack(spacing: 12) {
                                            IconBadge(systemImage: "play.fill", tint: AppTheme.accent)

                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(plan.name)
                                                    .font(.headline)

                                                HStack(spacing: 10) {
                                                    Label(L10n.string("training.70d17961dda6", fallback: "{{value1}}種目", values: [String(describing: plan.exercises.count)]), systemImage: "dumbbell")
                                                    Label(L10n.string("training.a6a1cc3a4bfc", fallback: "{{value1}}セット", values: [String(describing: plan.totalSetCount)]), systemImage: "checklist")
                                                }
                                                .font(.footnote)
                                                .foregroundStyle(AppTheme.mutedInk)
                                            }

                                            Spacer()

                                            Text(L10n.string("training.92f3acd01a38", fallback: "開始"))
                                                .font(.footnote.bold())
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
            .navigationTitle(L10n.string("training.672e0be9ce7a", fallback: "記録"))
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
