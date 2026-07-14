import SwiftUI

struct DailyRecordChecklistCard: View {
    let bodyWeightRecorded: Bool
    let waistRecorded: Bool
    let mealCount: Int
    let bodyPhotoCount: Int
    let workoutCount: Int

    private var completedCount: Int {
        [
            bodyWeightRecorded,
            waistRecorded,
            mealCount > 0,
            bodyPhotoCount > 0,
            workoutCount > 0
        ].filter { $0 }.count
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日の記録チェック")
                            .font(.headline)
                        Text("\(completedCount)/5 完了")
                            .font(.caption.bold())
                            .foregroundStyle(completedCount == 5 ? .green : .secondary)
                    }

                    Spacer()

                    Gauge(value: Double(completedCount), in: 0...5) {
                        Text("完了")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(AppTheme.accent)
                }

                ProgressView(value: Double(completedCount), total: 5)
                    .tint(AppTheme.accent)

                VStack(spacing: 9) {
                    DailyRecordStatusLine(
                        title: "体重",
                        detail: bodyWeightRecorded ? "記録済み" : "未記録",
                        systemImage: "scalemass",
                        isCompleted: bodyWeightRecorded,
                        tint: AppTheme.blue
                    )

                    DailyRecordStatusLine(
                        title: "腹囲",
                        detail: waistRecorded ? "記録済み" : "未記録",
                        systemImage: "figure.core.training",
                        isCompleted: waistRecorded,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusLine(
                        title: "食事",
                        detail: mealCount > 0 ? "\(mealCount)件" : "未記録",
                        systemImage: "fork.knife",
                        isCompleted: mealCount > 0,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusLine(
                        title: "体型写真",
                        detail: bodyPhotoCount > 0 ? "\(bodyPhotoCount)件" : "未記録",
                        systemImage: "camera",
                        isCompleted: bodyPhotoCount > 0,
                        tint: AppTheme.purple
                    )

                    DailyRecordStatusLine(
                        title: "筋トレ",
                        detail: workoutCount > 0 ? "\(workoutCount)回" : "未実施",
                        systemImage: "figure.strengthtraining.traditional",
                        isCompleted: workoutCount > 0,
                        tint: AppTheme.accent
                    )
                }
            }
        }
        .accessibilityIdentifier("dailyRecordChecklistCard")
    }
}

private struct DailyRecordStatusLine: View {
    let title: String
    let detail: String
    let systemImage: String
    let isCompleted: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCompleted ? .green : tint)
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(detail)
                .font(.caption.bold())
                .foregroundStyle(isCompleted ? .green : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
    }
}
