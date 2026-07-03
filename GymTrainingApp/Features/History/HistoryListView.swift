import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if appStore.workoutHistory.isEmpty {
                    ContentUnavailableView {
                        Label("履歴はまだありません", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("ワークアウトを完了すると、ここから過去の重量・回数を見返せます。")
                    }
                } else {
                    List {
                        ForEach(appStore.workoutHistory) { session in
                            NavigationLink(value: session) {
                                HistoryRow(session: session)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("historyRow-\(session.title)")
                        }
                        .onDelete(perform: appStore.deleteWorkoutHistory)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pageBackground)
                }
            }
            .navigationTitle("履歴")
            .navigationDestination(for: WorkoutSession.self) { session in
                HistoryDetailView(session: session)
            }
        }
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(AppFormatters.shortDateTime.string(from: session.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(AppFormatters.percent(session.achievementRate))
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.accent)
                }

                HStack(spacing: 10) {
                    Label(AppFormatters.volume(session.totalVolume), systemImage: "scalemass")
                    Label("\(session.exercises.count)種目", systemImage: "dumbbell")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(session.exercises.map { $0.exercise.name }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    HistoryListView()
        .environmentObject(AppStore())
}
