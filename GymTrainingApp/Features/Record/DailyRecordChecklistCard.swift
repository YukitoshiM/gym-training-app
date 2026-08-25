import SwiftUI

struct DailyRecordChecklistCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let bodyWeightRecorded: Bool
    let waistRecorded: Bool
    let nutritionProgress: DailyNutritionProgress
    let bodyPhotoCount: Int
    let workoutCount: Int
    var showsQuickActions = false

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var completedCount: Int {
        [
            bodyWeightRecorded,
            waistRecorded,
            nutritionProgress.isMealCountAchieved,
            nutritionProgress.isNutritionAchieved,
            bodyPhotoCount > 0,
            workoutCount > 0
        ].filter { $0 }.count
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("core_ui.58c1f125a05a", fallback: "今日の記録"))
                            .font(.title3.bold())
                            .accessibilityIdentifier("dailyRecordChecklistCard")
                        Text(L10n.string("core_ui.06eaf4650b54", fallback: "{{value1}}/6 完了", values: [String(describing: completedCount)]))
                            .font(.subheadline.bold())
                            .foregroundStyle(completedCount == 6 ? AppTheme.positive : AppTheme.mutedInk)
                    }

                    Spacer()

                    Gauge(value: Double(completedCount), in: 0...6) {
                        Text(L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了"))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(AppTheme.accent)
                    .accessibilityHidden(true)
                }

                ProgressView(value: Double(completedCount), total: 6)
                    .tint(AppTheme.accent)
                    .accessibilityHidden(true)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.d05d75dc142b", fallback: "体重"),
                        detail: bodyWeightRecorded ? L10n.string("core_ui.da6af7f58be0", fallback: "記録済み") : L10n.string("core_ui.de7e126d0b16", fallback: "未記録"),
                        systemImage: "scalemass",
                        isCompleted: bodyWeightRecorded,
                        tint: AppTheme.blue
                    )

                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.424306f5227a", fallback: "腹囲"),
                        detail: waistRecorded ? L10n.string("core_ui.da6af7f58be0", fallback: "記録済み") : L10n.string("core_ui.de7e126d0b16", fallback: "未記録"),
                        systemImage: "figure.core.training",
                        isCompleted: waistRecorded,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.3871f0a40fbb", fallback: "食事回数"),
                        detail: L10n.string("core_ui.5e0934899b21", fallback: "{{value1}}/{{value2}}回", values: [String(describing: nutritionProgress.mealCount), String(describing: nutritionProgress.goals.mealCount)]),
                        systemImage: "fork.knife",
                        isCompleted: nutritionProgress.isMealCountAchieved,
                        tint: AppTheme.orange
                    )

                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.6c96c72399c0", fallback: "カロリー/PFC"),
                        detail: nutritionProgress.isNutritionAchieved ? L10n.string("core_ui.32670ed3aace", fallback: "目標達成") : L10n.string("core_ui.a9efa7f0620d", fallback: "記録中"),
                        systemImage: "chart.bar.fill",
                        isCompleted: nutritionProgress.isNutritionAchieved,
                        tint: AppTheme.accent
                    )

                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.910d79f7cbf5", fallback: "体型写真"),
                        detail: bodyPhotoCount > 0 ? L10n.string("core_ui.f913cce82a70", fallback: "{{value1}}件", values: [bodyPhotoCount.formatted()]) : L10n.string("core_ui.de7e126d0b16", fallback: "未記録"),
                        systemImage: "camera",
                        isCompleted: bodyPhotoCount > 0,
                        tint: AppTheme.purple
                    )

                    DailyRecordStatusChip(
                        title: L10n.string("core_ui.536e51b3f816", fallback: "筋トレ"),
                        detail: workoutCount > 0 ? L10n.string("core_ui.91bc80596709", fallback: "{{value1}}回", values: [String(describing: workoutCount)]) : L10n.string("core_ui.b0b7d41109d6", fallback: "未実施"),
                        systemImage: "figure.strengthtraining.traditional",
                        isCompleted: workoutCount > 0,
                        tint: AppTheme.accent
                    )
                }

                if showsQuickActions {
                    Divider()

                    HStack(spacing: 10) {
                        NavigationLink {
                            MealListView()
                        } label: {
                            DailyRecordQuickAction(
                                title: L10n.string("core_ui.e8a52146d9dc", fallback: "食事"),
                                value: L10n.string("core_ui.f913cce82a70", fallback: "{{value1}}件", values: [nutritionProgress.mealCount.formatted()]),
                                systemImage: "fork.knife",
                                tint: AppTheme.orange
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mealListLink")

                        NavigationLink {
                            BodyPhotoListView()
                        } label: {
                            DailyRecordQuickAction(
                                title: L10n.string("core_ui.910d79f7cbf5", fallback: "体型写真"),
                                value: bodyPhotoCount > 0 ? L10n.string("core_ui.da6af7f58be0", fallback: "記録済み") : L10n.string("core_ui.cfb169f1651f", fallback: "追加"),
                                systemImage: "camera",
                                tint: AppTheme.purple
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bodyPhotoListLink")
                    }
                }
            }
        }
    }
}

private struct DailyRecordQuickAction: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(value)
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.mutedInk)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(isCompleted ? AppTheme.positive : tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.subheadline.bold())
                    .foregroundStyle(isCompleted ? AppTheme.positive : AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((isCompleted ? AppTheme.positive : tint).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isCompleted ? AppTheme.positive : tint).opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、\(detail)")
        .accessibilityValue(isCompleted ? L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了") : L10n.string("core_ui.3c3407bde7db", fallback: "未完了"))
    }
}
