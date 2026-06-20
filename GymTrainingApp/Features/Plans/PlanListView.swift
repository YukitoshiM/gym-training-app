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
                        }
                        .onDelete(perform: appStore.deletePlans)
                    }
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
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                PlanEditorView(plan: planToEdit)
            }
        }
    }
}

private struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.name)
                .font(.headline)

            HStack(spacing: 10) {
                Label("\(plan.exercises.count)種目", systemImage: "dumbbell")
                Label("\(plan.totalSetCount)セット", systemImage: "checklist")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(plan.exercises.map { $0.exercise.name }.joined(separator: "、"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PlanListView()
        .environmentObject(AppStore())
}

