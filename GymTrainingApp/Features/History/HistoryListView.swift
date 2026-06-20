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
                            .accessibilityIdentifier("historyRow-\(session.title)")
                        }
                        .onDelete(perform: appStore.deleteWorkoutHistory)
                    }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title)
                    .font(.headline)

                Spacer()

                Text(AppFormatters.percent(session.achievementRate))
                    .font(.subheadline.bold())
            }

            HStack(spacing: 10) {
                Label(AppFormatters.shortDateTime.string(from: session.startedAt), systemImage: "calendar")
                Label(AppFormatters.volume(session.totalVolume), systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(session.exercises.map { $0.exercise.name }.joined(separator: "、"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryListView()
        .environmentObject(AppStore())
}
