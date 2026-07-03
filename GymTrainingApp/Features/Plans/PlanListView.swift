import SwiftUI

struct PlanListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingEditor = false
    @State private var planToEdit: TrainingPlan?

    var body: some View {
        NavigationStack {
            Group {
                if appStore.plans.isEmpty {
                    ContentUnavailableView {
                        Label("計画はまだありません", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("種目とセット目標を登録して、次のトレーニングを迷わず始めましょう。")
                    } actions: {
                        Button("計画を作成") {
                            planToEdit = nil
                            isShowingEditor = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("createPlanEmptyButton")
                    }
                } else {
                    List {
                        ForEach(appStore.plans) { plan in
                            Button {
                                planToEdit = plan
                                isShowingEditor = true
                            } label: {
                                PlanRow(plan: plan)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: appStore.deletePlans)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pageBackground)
                }
            }
            .navigationTitle("計画")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        planToEdit = nil
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("計画を作成")
                    .accessibilityIdentifier("createPlanToolbarButton")
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                PlanEditorView(plan: planToEdit) {
                    isShowingEditor = false
                }
            }
        }
    }
}

private struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                IconBadge(systemImage: "list.bullet.rectangle", tint: AppTheme.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)

                    Text(plan.exercises.map { $0.exercise.name }.joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                        Label("\(plan.totalSetCount)セット", systemImage: "checklist")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    PlanListView()
        .environmentObject(AppStore())
}
