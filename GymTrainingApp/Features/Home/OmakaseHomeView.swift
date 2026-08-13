import SwiftUI

struct OmakaseHomeDashboard: View {
    let recommendation: DailyRecommendation
    let progress: (DailyAction) -> DailyActionProgress
    let isAIRefreshing: Bool
    let isAIEnabled: Bool
    let coachName: String
    let coachRole: String
    let coachAvatarName: String
    let review: DailyReview?
    let latestRevision: RecommendationRevision?
    let targetAdjustment: TargetAdjustmentProposal?
    let onOpen: (DailyAction) -> Void
    let onToggleManual: (DailyAction) -> Void
    let onWhy: (DailyAction) -> Void
    let onReplace: (DailyAction) -> Void
    let onQuickMeal: () -> Void
    let onQuickWeight: () -> Void
    let onQuickPhoto: () -> Void
    let onOpenAICoach: () -> Void
    let onAcceptTargetAdjustment: (TargetAdjustmentProposal) -> Void
    let onDeclineTargetAdjustment: (TargetAdjustmentProposal) -> Void

    private var activeActions: [DailyAction] { recommendation.activeActions }

    private var primaryAction: DailyAction? {
        activeActions.first { $0.status != .completed && $0.status != .skipped }
            ?? activeActions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            readinessHeader
            aiCoachCard

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("今日やること")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("omakaseDashboard")
                    Spacer()
                    Text("\(completedCount) / \(activeActions.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }

                ForEach(activeActions) { action in
                    DailyActionRow(
                        action: action,
                        progress: progress(action),
                        onOpen: { onOpen(action) },
                        onToggleManual: { onToggleManual(action) },
                        onWhy: { onWhy(action) },
                        onReplace: { onReplace(action) }
                    )
                }
            }

            if let primaryAction {
                Button {
                    if case .manuallyConfirmed = primaryAction.completionRule {
                        onToggleManual(primaryAction)
                    } else {
                        onOpen(primaryAction)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: primaryAction.status == .completed ? "checkmark" : primaryAction.category.systemImage)
                        Text(primaryAction.status == .completed ? "今日の詳細を見る" : primaryButtonTitle(primaryAction))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.onAccent)
                .accessibilityIdentifier("omakasePrimaryActionButton")
                .appTourTarget(.homeTodayTraining)
            }

            quickRecordActions

            if let review {
                DailyReviewSummary(review: review, totalCount: activeActions.count)
            }

            if let targetAdjustment {
                TargetAdjustmentProposalView(
                    proposal: targetAdjustment,
                    onAccept: { onAcceptTargetAdjustment(targetAdjustment) },
                    onDecline: { onDeclineTargetAdjustment(targetAdjustment) }
                )
            }

            if let latestRevision {
                Label(latestRevision.reason, systemImage: revisionSymbol(latestRevision.source))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("omakaseRevisionReason")
            }
        }
    }

    private var readinessHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: readinessSymbol)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.onAccent)
                .frame(width: 50, height: 50)
                .background(readinessColor, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("今日の調子")
                    .font(.footnote.bold())
                    .foregroundStyle(AppTheme.mutedInk)
                Text(recommendation.readiness.level.displayName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.ink)
            }

            Spacer(minLength: 4)

        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("omakaseReadiness")
    }

    private var aiCoachCard: some View {
        Button(action: onOpenAICoach) {
            HStack(alignment: .top, spacing: 12) {
                Image(coachAvatarName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(coachName)からの提案")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Label(aiStatusText, systemImage: aiStatusSymbol)
                            .font(.footnote.bold())
                            .foregroundStyle(aiStatusColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.trailing)
                    }

                    Text(coachRole)
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(recommendation.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("提案の理由を見る", systemImage: "arrow.right")
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("omakaseAICoachCard")
    }

    private var aiStatusText: String {
        if !isAIEnabled { return "基本提案" }
        if isAIRefreshing { return "記録を確認中" }
        if recommendation.aiEvaluatedAt != nil { return "確認済み" }
        if recommendation.aiRequestedAt != nil { return "確認待ち" }
        return "すぐ使えます"
    }

    private var aiStatusSymbol: String {
        if !isAIEnabled { return "checkmark.circle" }
        if isAIRefreshing { return "waveform" }
        if recommendation.aiEvaluatedAt != nil { return "checkmark.circle.fill" }
        if recommendation.aiRequestedAt != nil { return "clock" }
        return "iphone"
    }

    private var aiStatusColor: Color {
        if !isAIEnabled { return AppTheme.critical }
        if recommendation.aiEvaluatedAt != nil { return AppTheme.positive }
        return AppTheme.accent
    }

    private var quickRecordActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("クイック記録")
                .font(.headline)
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                QuickRecordButton(title: "食事", systemImage: "camera.fill", action: onQuickMeal)
                QuickRecordButton(title: "体重", systemImage: "scalemass", action: onQuickWeight)
                QuickRecordButton(title: "写真", systemImage: "person.crop.rectangle.stack", action: onQuickPhoto)
            }
        }
    }

    private var completedCount: Int {
        activeActions.filter { $0.status == .completed }.count
    }

    private var readinessColor: Color {
        switch recommendation.readiness.level {
        case .good: AppTheme.positive
        case .normal: AppTheme.accent
        case .tired, .rest: AppTheme.critical
        }
    }

    private var readinessSymbol: String {
        switch recommendation.readiness.level {
        case .good: "bolt.heart.fill"
        case .normal: "gauge.with.dots.needle.50percent"
        case .tired: "battery.25percent"
        case .rest: "bed.double.fill"
        }
    }

    private func primaryButtonTitle(_ action: DailyAction) -> String {
        switch action.destination {
        case .workout: "このメニューを開始"
        case .steps: "歩数を見る"
        case .meal: "食事を記録"
        case .bodyMetric: "数値を記録"
        case .bodyPhoto: "写真を撮る"
        case .condition: "状態を確認"
        case .none: "完了にする"
        }
    }

    private func revisionSymbol(_ source: DailyRecommendationSource) -> String {
        source == .ai ? "sparkles" : "arrow.triangle.2.circlepath"
    }
}

private struct TargetAdjustmentProposalView: View {
    let proposal: TargetAdjustmentProposal
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("目標の調整候補", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Text(proposal.reason)
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("\(Int(proposal.currentValue.rounded()).formatted()) kcal")
                Image(systemName: "arrow.right")
                Text("\(Int(proposal.proposedValue.rounded()).formatted()) kcal")
                    .foregroundStyle(AppTheme.accent)
            }
            .font(.headline.monospacedDigit())

            HStack(spacing: 10) {
                Button("今回は変えない", action: onDecline)
                    .buttonStyle(.bordered)
                Button("この目安に変更", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("targetAdjustmentProposal")
    }
}

private struct DailyActionRow: View {
    let action: DailyAction
    let progress: DailyActionProgress
    let onOpen: () -> Void
    let onToggleManual: () -> Void
    let onWhy: () -> Void
    let onReplace: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: completionAction) {
                Image(systemName: action.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(action.status == .completed ? AppTheme.positive : AppTheme.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.status == .completed ? "完了済み" : "\(action.title)を開く")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: action.category.systemImage)
                            .foregroundStyle(AppTheme.accent)
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(progress.detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppTheme.mutedInk)
                    ProgressView(value: progress.fraction)
                        .tint(action.status == .completed ? AppTheme.positive : AppTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onWhy) {
                    Label("トレーナーの理由", systemImage: "person.crop.circle")
                }
                if action.status != .completed {
                    Button(action: onReplace) {
                        Label("別の行動に替える", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(action.title)を提案した理由")
        }
        .padding(12)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("dailyAction-\(action.category.rawValue)")
    }

    private func completionAction() {
        if case .manuallyConfirmed = action.completionRule {
            onToggleManual()
        } else {
            onOpen()
        }
    }
}

private struct QuickRecordButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.title2.bold())
                Text(title)
                    .font(.subheadline.bold())
            }
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("omakaseQuickRecord-\(title)")
    }
}

private struct DailyReviewSummary: View {
    let review: DailyReview
    let totalCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: review.completedActionIDs.count == totalCount ? "checkmark.seal.fill" : "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("今日の達成")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("\(review.completedActionIDs.count) / \(totalCount)達成")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                Text(review.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dailyReviewSummary")
    }
}

struct DailyActionWhyView: View {
    @Environment(\.dismiss) private var dismiss
    let action: DailyAction
    let recommendation: DailyRecommendation
    let latestRevision: RecommendationRevision?
    let coachPersona: CoachPersona

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoachIdentityView(
                        persona: coachPersona,
                        role: "今日の提案",
                        detail: action.title,
                        avatarSize: 56
                    )
                }

                Section("この行動を選んだ理由") {
                    Label(action.title, systemImage: action.category.systemImage)
                        .font(.headline)
                    Text(action.rationale)
                        .font(.body)
                        .lineSpacing(4)
                }

                Section("参考にした情報") {
                    ForEach(recommendation.readiness.contributingFactors, id: \.self) { factor in
                        Label(factor, systemImage: "checkmark.circle")
                    }
                    if recommendation.readiness.contributingFactors.isEmpty {
                        Text("現在取得できる記録と設定を使用しました。")
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if !recommendation.readiness.missingData.isEmpty {
                    Section("あると判断が安定する情報") {
                        Text(recommendation.readiness.missingData.joined(separator: "・"))
                        Text("データ充足度 \(Int((recommendation.readiness.confidence * 5).rounded())) / 5")
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if let latestRevision {
                    Section("変更履歴") {
                        Text(latestRevision.reason)
                        Text(latestRevision.timestamp.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Section {
                    NavigationLink {
                        AITrainerChatView(initialDraft: "\(action.title)について、今日この提案になった理由と調整案を教えてください。")
                    } label: {
                        Label("\(coachPersona.displayName)に相談", systemImage: "message.fill")
                    }
                }
            }
            .navigationTitle("\(coachPersona.displayName)の判断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
