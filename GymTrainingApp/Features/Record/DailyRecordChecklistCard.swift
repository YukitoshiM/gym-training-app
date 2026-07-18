import SwiftUI

struct DailyRecordChecklistCard: View {
    let bodyWeightRecorded: Bool
    let waistRecorded: Bool
    let mealCount: Int
    let bodyPhotoCount: Int
    let workoutCount: Int

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

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
                            .foregroundStyle(completedCount == 5 ? AppTheme.positive : AppTheme.mutedInk)
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

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    DailyRecordStatusChip(
                        title: "体重",
                        detail: bodyWeightRecorded ? "記録済み" : "未記録",
                        systemImage: "scalemass",
                        isCompleted: bodyWeightRecorded,
                        tint: AppTheme.blue
                    )

                    DailyRecordStatusChip(
                        title: "腹囲",
                        detail: waistRecorded ? "記録済み" : "未記録",
                        systemImage: "figure.core.training",
                        isCompleted: waistRecorded,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusChip(
                        title: "食事",
                        detail: mealCount > 0 ? "\(mealCount)件" : "未記録",
                        systemImage: "fork.knife",
                        isCompleted: mealCount > 0,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusChip(
                        title: "体型写真",
                        detail: bodyPhotoCount > 0 ? "\(bodyPhotoCount)件" : "未記録",
                        systemImage: "camera",
                        isCompleted: bodyPhotoCount > 0,
                        tint: AppTheme.purple
                    )

                    DailyRecordStatusChip(
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

private struct DailyRecordStatusChip: View {
    let title: String
    let detail: String
    let systemImage: String
    let isCompleted: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCompleted ? AppTheme.positive : tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2.bold())
                    .foregroundStyle(isCompleted ? AppTheme.positive : AppTheme.mutedInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((isCompleted ? AppTheme.positive : tint).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isCompleted ? AppTheme.positive : tint).opacity(0.18), lineWidth: 1)
        )
    }
}
