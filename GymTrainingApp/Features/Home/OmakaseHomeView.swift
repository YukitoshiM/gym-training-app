import SwiftUI

struct OmakaseHomeDashboard: View {
    let recommendation: DailyRecommendation
    let profile: UserProfile
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

    private var remainingActions: [DailyAction] {
        guard let primaryAction else { return activeActions }
        return activeActions.filter { $0.id != primaryAction.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            readinessHeader

            VStack(alignment: .leading, spacing: 12) {
                todayActionsHeader

                if let primaryAction {
                    PrimaryDailyActionCard(
                        action: primaryAction,
                        progress: progress(primaryAction),
                        primaryButtonTitle: primaryButtonTitle(primaryAction),
                        coachName: coachName,
                        coachAvatarName: coachAvatarName,
                        onOpen: { startPrimaryAction(primaryAction) },
                        onWhy: { openReason(primaryAction) },
                        onReplace: { replace(primaryAction) }
                    )
                }

                ForEach(remainingActions) { action in
                    DailyActionRow(
                        action: action,
                        progress: progress(action),
                        onOpen: { onOpen(action) },
                        onToggleManual: { onToggleManual(action) },
                        onWhy: { openReason(action) },
                        onReplace: { replace(action) }
                    )
                }
            }

            quickRecordActions
            aiCoachCard

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
        .onAppear {
            UsageAnalytics.shared.record(
                .recommendationSourceShown,
                dimension: recommendation.source.rawValue,
                properties: .dailyRecommendation(profile: profile, recommendation: recommendation)
            )
            for action in activeActions {
                UsageAnalytics.shared.record(
                    .dailyActionImpression,
                    dimension: action.category.rawValue,
                    properties: .dailyAction(
                        profile: profile,
                        recommendation: recommendation,
                        action: action
                    )
                )
            }
        }
    }

    private var todayActionsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string("core_ui.4df982e6c906", fallback: "今日の3つ"))
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("omakaseDashboard")
            Spacer()
            HStack(spacing: 5) {
                Text(verbatim: "\(completedCount) / \(activeActions.count)")
                    .monospacedDigit()
                Text(L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了"))
            }
            .environment(\.layoutDirection, .leftToRight)
            .font(.headline)
            .foregroundStyle(AppTheme.accent)
        }
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: readinessSymbol)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(readinessColor, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("core_ui.3e4b49a95d93", fallback: "今日の調子"))
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.mutedInk)
                    Text(recommendation.readiness.level.displayName)
                        .font(.title.bold())
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer(minLength: 4)
            }
            .accessibilityIdentifier("omakaseReadiness")

            Label(recommendationStatusText, systemImage: recommendationStatusSymbol)
                .font(.footnote.bold())
                .foregroundStyle(recommendationStatusColor)
                .accessibilityIdentifier("omakaseRecommendationStatus")
        }
        .padding(.vertical, 4)
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
                        Text(L10n.string("core_ui.0e9e7fa3d87c", fallback: "{{value1}}からの提案", values: [String(describing: coachName)]))
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

                    Text(aiStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(L10n.string("core_ui.1c56ad058cb9", fallback: "判断の詳細を見る"), systemImage: "arrow.right")
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
        if !isAIEnabled { return L10n.string("core_ui.4d7d6a61c333", fallback: "端末内") }
        if isAIRefreshing { return L10n.string("core_ui.a09a04648e2c", fallback: "AI確認中") }
        if recommendation.aiEvaluatedAt != nil { return L10n.string("core_ui.386d8d6ae3c9", fallback: "AI確認済み") }
        if recommendation.aiRequestedAt != nil { return L10n.string("core_ui.88c138af4a1e", fallback: "送信待ち") }
        return L10n.string("core_ui.4d7d6a61c333", fallback: "端末内")
    }

    private var aiStatusSymbol: String {
        if !isAIEnabled { return "checkmark.circle" }
        if isAIRefreshing { return "waveform" }
        if recommendation.aiEvaluatedAt != nil { return "checkmark.circle.fill" }
        if recommendation.aiRequestedAt != nil { return "clock" }
        return "iphone"
    }

    private var aiStatusColor: Color {
        if recommendation.aiEvaluatedAt != nil { return AppTheme.positive }
        return isAIRefreshing ? AppTheme.accent : AppTheme.mutedInk
    }

    private var aiStatusDetail: String {
        if !isAIEnabled { return L10n.string("core_ui.79fac498bcc6", fallback: "AIなしでも、今日の提案はそのまま使えます。") }
        if isAIRefreshing { return L10n.string("core_ui.ddbfa4c66ff8", fallback: "記録を確認中です。画面を閉じても続きます。") }
        if recommendation.aiEvaluatedAt != nil { return L10n.string("core_ui.716b63d8113c", fallback: "保存済みの記録をもとに確認しました。") }
        if recommendation.aiRequestedAt != nil { return L10n.string("core_ui.d624960db5e8", fallback: "通信でき次第、記録を確認します。") }
        return L10n.string("core_ui.b5a54050d994", fallback: "まず端末内の記録から作成し、必要な場合だけAIが補正します。")
    }

    private var recommendationStatusText: String {
        let date = recommendation.aiEvaluatedAt ?? recommendation.generatedAt
        let source: String
        if recommendation.aiEvaluatedAt != nil {
            source = L10n.string("core_ui.e7a6c6422c09", fallback: "{{value1}}が確認済み", values: [String(describing: coachName)])
        } else if isAIRefreshing {
            source = L10n.string("core_ui.34effd785dea", fallback: "{{value1}}が確認中・提案は利用可能", values: [String(describing: coachName)])
        } else if isAIEnabled, recommendation.aiRequestedAt != nil {
            source = L10n.string("core_ui.6ef5a3bdd141", fallback: "{{value1}}の確認待ち・提案は利用可能", values: [String(describing: coachName)])
        } else {
            source = L10n.string("core_ui.246b9f2d306d", fallback: "{{value1}}の基本提案", values: [String(describing: coachName)])
        }
        return L10n.string("core_ui.305942690f5d", fallback: "{{value1}}・{{value2}}更新", values: [String(describing: source), String(describing: date.formatted(date: .omitted, time: .shortened))])
    }

    private var recommendationStatusSymbol: String {
        if recommendation.aiEvaluatedAt != nil { return "checkmark.circle.fill" }
        if isAIRefreshing { return "arrow.triangle.2.circlepath" }
        if isAIEnabled, recommendation.aiRequestedAt != nil { return "clock" }
        return "iphone"
    }

    private var recommendationStatusColor: Color {
        recommendation.aiEvaluatedAt != nil || isAIRefreshing ? AppTheme.accent : AppTheme.mutedInk
    }

    private var quickRecordActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("core_ui.a5067c621aca", fallback: "クイック記録"))
                .font(.headline)
                .foregroundStyle(AppTheme.mutedInk)

            HStack(spacing: 10) {
                QuickRecordButton(title: L10n.string("core_ui.e8a52146d9dc", fallback: "食事"), systemImage: "camera.fill") {
                    UsageAnalytics.shared.record(.quickRecordOpened, dimension: "meal")
                    onQuickMeal()
                }
                QuickRecordButton(title: L10n.string("core_ui.d05d75dc142b", fallback: "体重"), systemImage: "scalemass") {
                    UsageAnalytics.shared.record(.quickRecordOpened, dimension: "weight")
                    onQuickWeight()
                }
                QuickRecordButton(title: L10n.string("core_ui.a1ed281773ea", fallback: "写真"), systemImage: "person.crop.rectangle.stack") {
                    UsageAnalytics.shared.record(.quickRecordOpened, dimension: "photo")
                    onQuickPhoto()
                }
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
        case .workout: L10n.string("core_ui.bb8ea3c17233", fallback: "このメニューを開始")
        case .steps: L10n.string("core_ui.13c8c880dac8", fallback: "歩数を見る")
        case .meal: L10n.string("core_ui.dd8dea3af7bd", fallback: "食事を記録")
        case .bodyMetric: L10n.string("core_ui.bbc2f5175dc6", fallback: "数値を記録")
        case .bodyPhoto: L10n.string("core_ui.451d1e265682", fallback: "写真を撮る")
        case .condition: L10n.string("core_ui.e30570ba3b2d", fallback: "状態を確認")
        case .none: L10n.string("core_ui.66bbc01c25cd", fallback: "完了にする")
        }
    }

    private func revisionSymbol(_ source: DailyRecommendationSource) -> String {
        source == .ai ? "sparkles" : "arrow.triangle.2.circlepath"
    }

    private func trigger(_ action: DailyAction) {
        if case .manuallyConfirmed = action.completionRule {
            onToggleManual(action)
        } else {
            onOpen(action)
        }
    }

    private func startPrimaryAction(_ action: DailyAction) {
        UsageAnalytics.shared.record(
            .homePrimaryActionStarted,
            dimension: action.category.rawValue,
            properties: .dailyAction(profile: profile, recommendation: recommendation, action: action)
        )
        trigger(action)
    }

    private func openReason(_ action: DailyAction) {
        UsageAnalytics.shared.record(
            .dailyActionReasonOpened,
            dimension: action.category.rawValue,
            properties: .dailyAction(profile: profile, recommendation: recommendation, action: action)
        )
        onWhy(action)
    }

    private func replace(_ action: DailyAction) {
        onReplace(action)
    }
}

private struct TargetAdjustmentProposalView: View {
    let proposal: TargetAdjustmentProposal
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.string("core_ui.9ce2ddc2666c", fallback: "目標の調整候補"), systemImage: "slider.horizontal.3")
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
                Button(L10n.string("core_ui.01f9df15aee7", fallback: "今回は変えない"), action: onDecline)
                    .buttonStyle(.bordered)
                Button(L10n.string("core_ui.d9bbe4698b75", fallback: "この目安に変更"), action: onAccept)
                    .buttonStyle(.borderedProminent)
            }

            if let evidence = proposal.evidence, !evidence.isEmpty {
                DisclosureGroup(L10n.string("release_delta.evidence_count", fallback: "科学的根拠 {{value1}}件", values: [evidence.count.formatted()])) {
                    ForEach(evidence) { citation in
                        CoachEvidenceCitationRow(citation: citation)
                            .padding(.vertical, 4)
                    }
                }
            } else if proposal.evidenceStatus != nil {
                Label(L10n.string("release_delta.insufficient_direct_evidence", fallback: "直接使える根拠が不足しているため、記録傾向を優先した目安です"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
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

private struct PrimaryDailyActionCard: View {
    let action: DailyAction
    let progress: DailyActionProgress
    let primaryButtonTitle: String
    let coachName: String
    let coachAvatarName: String
    let onOpen: () -> Void
    let onWhy: () -> Void
    let onReplace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(coachAvatarName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
                        }
                        .accessibilityHidden(true)
                    Text(L10n.string("core_ui.7f624f77db97", fallback: "{{value1}}のおすすめ", values: [String(describing: coachName)]))
                        .font(.footnote.bold())
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(2)
                }
                ActionControlBar(
                    action: action,
                    onWhy: onWhy,
                    onReplace: onReplace
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: action.category.systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dailyAction-\(action.category.rawValue)")
                    Text(action.rationale)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progress.detail)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: progress.fraction)
                .tint(action.status == .completed ? AppTheme.positive : AppTheme.accent)
                .accessibilityHidden(true)

            if action.status == .completed {
                Label(L10n.string("core_ui.a16ead46fb2d", fallback: "完了しました"), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.positive)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        Text(primaryButtonTitle)
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
        }
        .padding(14)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.accent.opacity(0.6), lineWidth: 1)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: completionAction) {
                    Image(systemName: action.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(action.status == .completed ? AppTheme.positive : AppTheme.accent)
                        .padding(13)
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel(action.status == .completed ? L10n.string("core_ui.3362a5982780", fallback: "完了済み") : L10n.string("core_ui.9c32e5e1faac", fallback: "{{value1}}を開く", values: [String(describing: action.title)]))

                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: action.category.systemImage)
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityHidden(true)
                            Text(action.title)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("dailyAction-\(action.category.rawValue)")
                        }
                        Text(progress.detail)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppTheme.mutedInk)
                        ProgressView(value: progress.fraction)
                            .tint(action.status == .completed ? AppTheme.positive : AppTheme.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            ActionControlBar(
                action: action,
                onWhy: onWhy,
                onReplace: onReplace
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    private func completionAction() {
        if case .manuallyConfirmed = action.completionRule {
            onToggleManual()
        } else {
            onOpen()
        }
    }
}

private struct ActionControlBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let action: DailyAction
    let onWhy: () -> Void
    let onReplace: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onWhy) {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                } else {
                    Label(L10n.string("health_meals_body_ai.bde5657225e5", fallback: "判断の根拠"), systemImage: "info.circle")
                        .font(.footnote.bold())
                        .padding(.horizontal, 13)
                        .padding(.vertical, 17)
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 72, minHeight: 48)
            .contentShape(Rectangle())
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel(L10n.string("core_ui.81040e1e98f5", fallback: "{{value1}}を提案した理由", values: [String(describing: action.title)]))
            .accessibilityIdentifier("omakaseReason-\(action.category.rawValue)")

            if action.status != .completed {
                Menu {
                    Button(action: onReplace) {
                        Label(L10n.string("core_ui.4e4c49222b4d", fallback: "別の行動に替える"), systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                    } else {
                        Label(L10n.string("core_ui.f04176da6625", fallback: "変更"), systemImage: "ellipsis.circle")
                            .font(.footnote.bold())
                            .frame(minWidth: 72, minHeight: 48)
                    }
                }
                .foregroundStyle(AppTheme.mutedInk)
                .accessibilityLabel(L10n.string("core_ui.b3e3454f449d", fallback: "{{value1}}を別の行動に変更", values: [String(describing: action.title)]))
                .accessibilityIdentifier("omakaseReplace-\(action.category.rawValue)")
            }
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
                Text(L10n.string("core_ui.98bcbb87d970", fallback: "今日の達成"))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                HStack(spacing: 5) {
                    Text(verbatim: "\(review.completedActionIDs.count) / \(totalCount)")
                        .monospacedDigit()
                    Text(L10n.string("training.6f68dd807f5f", fallback: "達成"))
                }
                .environment(\.layoutDirection, .leftToRight)
                .font(.title3.bold())
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
                        role: L10n.string("core_ui.0221665d470d", fallback: "今日の提案"),
                        detail: action.title,
                        avatarSize: 56
                    )
                }

                Section(L10n.string("core_ui.cf7bb911516d", fallback: "この行動を選んだ理由")) {
                    Label(action.title, systemImage: action.category.systemImage)
                        .font(.headline)
                    Text(action.rationale)
                        .font(.body)
                        .lineSpacing(4)
                }

                Section(L10n.string("core_ui.3bd14a48af52", fallback: "参考にした情報")) {
                    ForEach(recommendation.readiness.contributingFactors, id: \.self) { factor in
                        Label(factor, systemImage: "checkmark.circle")
                    }
                    if recommendation.readiness.contributingFactors.isEmpty {
                        Text(L10n.string("core_ui.8f44663f425e", fallback: "現在取得できる記録と設定を使用しました。"))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if !recommendation.readiness.missingData.isEmpty {
                    Section(L10n.string("core_ui.af3103318eb4", fallback: "あると判断が安定する情報")) {
                        Text(recommendation.readiness.missingData.joined(separator: L10n.string("core_ui.3b67eb100838", fallback: "・")))
                        Text(L10n.string("core_ui.dcd096e9f343", fallback: "データ充足度 {{value1}} / 5", values: [String(describing: Int((recommendation.readiness.confidence * 5).rounded()))]))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if let latestRevision {
                    Section(L10n.string("core_ui.3bcfc8fdb197", fallback: "変更履歴")) {
                        Text(latestRevision.reason)
                        Text(latestRevision.timestamp.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                if recommendation.evidenceStatus != nil || !(recommendation.evidence ?? []).isEmpty {
                    Section {
                        NavigationLink {
                            DailyActionEvidenceView(
                                action: action,
                                evidence: recommendation.evidence ?? [],
                                status: recommendation.evidenceStatus
                            )
                        } label: {
                            Label(
                                L10n.string("evidence.view_scientific", fallback: "科学的根拠を見る"),
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }
                        .accessibilityIdentifier("dailyActionEvidenceLink")
                    }
                }

                Section {
                    NavigationLink {
                        AITrainerChatView(initialDraft: L10n.string("core_ui.eafad186b3bf", fallback: "{{value1}}について、今日この提案になった理由と調整案を教えてください。", values: [String(describing: action.title)]))
                    } label: {
                        Label(L10n.string("core_ui.1d7aec6451c6", fallback: "{{value1}}に相談", values: [String(describing: coachPersona.displayName)]), systemImage: "message.fill")
                    }
                }
            }
            .navigationTitle(L10n.string("core_ui.0e0996974372", fallback: "{{value1}}の判断", values: [String(describing: coachPersona.displayName)]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了")) { dismiss() }
                }
            }
        }
    }

}

private struct DailyActionEvidenceView: View {
    let action: DailyAction
    let evidence: [CoachEvidenceCitation]
    let status: CoachEvidenceStatus?

    var body: some View {
        List {
            Section {
                Label(action.title, systemImage: action.category.systemImage)
                    .font(.headline)
                Text(action.rationale)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            if evidence.isEmpty {
                Section {
                    Label(
                        emptyEvidenceMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(AppTheme.warning)
                }
            } else {
                Section(L10n.string("evidence.referenced_research", fallback: "参照した文献")) {
                    ForEach(evidence) { citation in
                        CoachEvidenceCitationRow(citation: citation)
                            .padding(.vertical, 4)
                    }
                }
            }

            if let status {
                Section(L10n.string("evidence.search_information", fallback: "検索情報")) {
                    LabeledContent(
                        L10n.string("evidence.overall_confidence", fallback: "全体の確度"),
                        value: confidenceLabel(status.confidence)
                    )
                    if status.searchedDocuments > 0 {
                        LabeledContent(
                            L10n.string("evidence.documents_searched", fallback: "検索対象"),
                            value: status.searchedDocuments.formatted()
                        )
                    }
                }
            }

            Section {
                Text(
                    L10n.string("evidence.general_trends_disclaimer", fallback: "研究結果は一般的な傾向です。あなた自身への効果を断定するものではありません。")
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .navigationTitle(L10n.string("evidence.recommendation_evidence", fallback: "提案の根拠"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func confidenceLabel(_ confidence: String) -> String {
        switch confidence {
        case "high": L10n.string("evidence.confidence_high", fallback: "高")
        case "moderate": L10n.string("evidence.confidence_moderate", fallback: "中")
        case "low": L10n.string("evidence.confidence_low", fallback: "低")
        default: L10n.string("evidence.confidence_reference", fallback: "参考")
        }
    }

    private var emptyEvidenceMessage: String {
        switch status?.state {
        case "population_mismatch":
            L10n.string("evidence.population_mismatch", fallback: "条件の近い対象者を扱った文献が見つからなかったため、今回は記録と一般原則を中心に判断しています。")
        case "unavailable":
            L10n.string("evidence.search_unavailable", fallback: "文献検索を利用できませんでした。根拠を確認できていないため、今回は記録を中心に判断しています。")
        case "empty", "disabled":
            L10n.string("evidence.library_unavailable", fallback: "文献データを利用できないため、今回は記録と一般原則を中心に判断しています。")
        default:
            L10n.string("evidence.no_direct_paper", fallback: "この提案に直接使える文献は確認できませんでした。記録と一般的な運動原則を中心に判断しています。")
        }
    }
}
