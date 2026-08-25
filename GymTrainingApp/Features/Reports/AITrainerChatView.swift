import SwiftUI

struct AITrainerChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var aiTrainerBackgroundService: AITrainerBackgroundService
    @State private var draft: String
    @State private var errorPresentation: AIErrorPresentation?
    @State private var creditAccessIssue: AICreditAccessIssue?
    @State private var failedMessage: String?
    @State private var memoryCandidates: [CoachMemoryCandidate] = []
    @State private var isReviewingMemories = false
    @State private var isConfirmingClear = false
    @State private var isShowingContextCoverage = false
    @State private var responseRatings: [UUID: CoachResponseRating] = [:]
    @FocusState private var isComposerFocused: Bool

    init(initialDraft: String = "") {
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    CoachIdentityView(
                        persona: appStore.userProfile.coachPersona,
                        role: appStore.userProfile.coachType.displayName,
                        detail: L10n.string("health_meals_body_ai.e8a45501dd61", fallback: "あなたの記録を見ながら一緒に考えます。"),
                        avatarSize: 58
                    )
                    .padding(.horizontal)
                    .accessibilityIdentifier("aiChatCoachHeader")

                    if appStore.coachChatMessages.isEmpty {
                        VStack(spacing: 12) {
                            CoachAvatarView(
                                persona: appStore.userProfile.coachPersona,
                                size: 112,
                                cornerRadius: 12
                            )
                            Text(L10n.string("health_meals_body_ai.ea35bda4ca72", fallback: "{{value1}}に相談", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text(
                                L10n.string("health_meals_body_ai.402c5e169f80", fallback: "{{value1}}・", values: [String(describing: appStore.userProfile.coachType.displayName)])
                                    + appStore.userProfile.coachingStyle.displayName
                            )
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                            Text(appStore.userProfile.coachType.expertiseProfile.promise)
                                .font(.body)
                                .foregroundStyle(AppTheme.mutedInk)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(appStore.userProfile.coachingStyle.openingLine)
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 270)
                        .padding(.horizontal, 28)
                        .accessibilityIdentifier("aiChatEmptyCoach")
                    } else {
                        ForEach(appStore.coachChatMessages) { message in
                            CoachChatBubble(
                                message: message,
                                coachPersona: appStore.userProfile.coachPersona,
                                rating: responseRating(for: message),
                                rateResponse: { rating in
                                    responseRatings[message.id] = rating
                                    UsageAnalytics.shared.recordCoachResponseRating(
                                        messageID: message.id,
                                        rating: rating,
                                        coachType: appStore.userProfile.coachType.rawValue
                                    )
                                }
                            )
                                .id(message.id)
                        }
                    }

                    if isSending {
                        HStack(spacing: 10) {
                            CoachAvatarView(
                                persona: appStore.userProfile.coachPersona,
                                size: 34,
                                cornerRadius: 7
                            )
                            ProgressView()
                            Text(L10n.string("health_meals_body_ai.f31fb12d4b07", fallback: "{{value1}}が回答を考えています", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("aiTrainerSendingIndicator")
                    }

                    if let errorPresentation {
                        AITrainerErrorView(
                            presentation: errorPresentation,
                            canRetry: failedMessage != nil,
                            retry: retryFailedMessage
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    scrollToLatestMessage(proxy)
                }
            }
            .onChange(of: appStore.coachChatMessages.count) {
                guard !appStore.coachChatMessages.isEmpty else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation {
                        scrollToLatestMessage(proxy)
                    }
                }
            }
        }
        .background(AppTheme.pageBackground)
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .navigationTitle(appStore.userProfile.coachPersona.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingContextCoverage = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel(L10n.string("health_meals_body_ai.9f3fa8dd0ea9", fallback: "AIが参照する記録"))
                .accessibilityValue(L10n.string("health_meals_body_ai.02cbbe915d5f", fallback: "参照可能{{value1}}件、不足{{value2}}件", values: [String(describing: contextCoverage.readyItems.count), String(describing: contextCoverage.missingItems.count)]))
                .accessibilityIdentifier("coachContextCoverageButton")

                Button {
                    isConfirmingClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L10n.string("health_meals_body_ai.41ce58020850", fallback: "会話を削除"))
                .disabled(appStore.coachChatMessages.isEmpty || isSending)
            }
        }
        .confirmationDialog(L10n.string("health_meals_body_ai.ab8ec8a66973", fallback: "AIトレーナーとの会話を削除しますか？"), isPresented: $isConfirmingClear) {
            Button(L10n.string("health_meals_body_ai.41ce58020850", fallback: "会話を削除"), role: .destructive) {
                appStore.clearCoachChatMessages()
                failedMessage = nil
                errorPresentation = nil
            }
            Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.string("health_meals_body_ai.de69cad40c07", fallback: "保存した記憶は削除されません。"))
        }
        .sheet(isPresented: $isReviewingMemories) {
            CoachMemoryCandidateReviewView(
                candidates: memoryCandidates,
                coachPersona: appStore.userProfile.coachPersona
            ) { approved in
                approved.forEach(appStore.approveCoachMemory)
            }
        }
        .sheet(isPresented: $isShowingContextCoverage) {
            CoachContextCoverageView(
                coverage: contextCoverage,
                coachPersona: appStore.userProfile.coachPersona,
                coachRole: appStore.userProfile.coachType.displayName
            )
        }
        .aiCreditRecoverySheet(
            issue: $creditAccessIssue,
            settings: appStore.aiSettings,
            onResolved: {
                await MainActor.run {
                    errorPresentation = nil
                    retryFailedMessage()
                }
            }
        )
        .onAppear(perform: consumeBackgroundServiceUpdates)
        .task(id: appStore.coachChatMessages.map(\.id)) {
            restoreResponseRatings()
        }
        .onChange(of: aiTrainerBackgroundService.latestFailure) {
            consumeBackgroundServiceUpdates()
        }
        .onChange(of: aiTrainerBackgroundService.pendingMemoryCandidates) {
            consumeBackgroundServiceUpdates()
        }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            AICreditCostStatusView(feature: "chat", settings: appStore.aiSettings)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(L10n.string("health_meals_body_ai.340d133557fc", fallback: "メッセージ"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                    .accessibilityIdentifier("aiTrainerMessageField")
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.accent, in: Circle())
                }
                .accessibilityLabel(L10n.string("health_meals_body_ai.28d11eaa4971", fallback: "送信"))
                .accessibilityIdentifier("sendAITrainerMessageButton")
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
            }

            if draft.count >= 240 {
                Text("\(draft.count.formatted()) / \(CoachChatRequest.maximumUserMessageCharacters.formatted())")
                    .font(.caption)
                    .foregroundStyle(draft.count > CoachChatRequest.maximumUserMessageCharacters ? AppTheme.critical : AppTheme.mutedInk)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= CoachChatRequest.maximumUserMessageCharacters
            && !isSending
    }

    private var isSending: Bool {
        aiTrainerBackgroundService.isSending
    }

    private var contextCoverage: CoachContextCoverage {
        CoachContextBuilder().coverage(
            profile: appStore.userProfile,
            sharing: appStore.aiSettings.dataSharing,
            bodyMetrics: appStore.bodyMetricEntries,
            meals: appStore.mealEntries,
            bodyPhotos: appStore.bodyPhotoEntries,
            workouts: appStore.workoutHistory,
            subjectiveRecovery: appStore.subjectiveRecoveryEntries,
            healthSnapshot: healthDataManager.snapshot,
            recoveryHistory: healthDataManager.recoveryHistory
        )
    }

    private func responseRating(for message: CoachChatMessage) -> CoachResponseRating? {
        guard message.role == .assistant else { return nil }
        return responseRatings[message.id]
    }

    private func restoreResponseRatings() {
        let assistantMessageIDs = appStore.coachChatMessages
            .filter { $0.role == .assistant }
            .map(\.id)
        let storedRatings = UsageAnalytics.shared.coachResponseRatings(for: assistantMessageIDs)
        responseRatings.merge(storedRatings) { current, _ in current }
    }

    private func sendDraft() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message.count <= CoachChatRequest.maximumUserMessageCharacters else { return }
        isComposerFocused = false
        draft = ""
        requestReply(for: message, appendUserMessage: true)
    }

    private func retryFailedMessage() {
        guard let failedMessage else { return }
        requestReply(for: failedMessage, appendUserMessage: false)
    }

    private func requestReply(for message: String, appendUserMessage: Bool) {
        guard !isSending else { return }

        var recentMessages = Array(appStore.coachChatMessages.suffix(CoachChatRequest.maximumSentRecentMessages))
        if !appendUserMessage,
           recentMessages.last?.role == .user,
           recentMessages.last?.content == message {
            recentMessages.removeLast()
        }
        if appendUserMessage {
            appStore.appendCoachChatMessage(CoachChatMessage(role: .user, content: message))
        }

        let context = CoachContextBuilder().build(
            profile: appStore.userProfile,
            sharing: appStore.aiSettings.dataSharing,
            bodyMetrics: appStore.bodyMetricEntries,
            bodyMetricGoals: appStore.bodyMetricGoals,
            meals: appStore.mealEntries,
            bodyPhotos: appStore.bodyPhotoEntries,
            workouts: appStore.workoutHistory,
            gymVisits: appStore.gymVisits,
            subjectiveRecovery: appStore.subjectiveRecoveryEntries,
            healthSnapshot: healthDataManager.snapshot,
            recoveryHistory: healthDataManager.recoveryHistory,
            memories: appStore.coachMemories,
            insights: appStore.aiInsights,
            planRevisions: appStore.planRevisionProposals
        )
        let request = CoachChatRequest(
            coachID: appStore.userProfile.coachType.rawValue,
            coach: AIRequestCoachContext(profile: appStore.userProfile),
            message: message,
            context: context,
            recentMessages: recentMessages
        )
        var sharedCategories = appStore.aiSettings.dataSharing.enabledCategoryNames + [L10n.string("health_meals_body_ai.abf6a2685234", fallback: "会話")]
        if !appStore.coachMemories.isEmpty {
            sharedCategories.append(L10n.string("health_meals_body_ai.c437a0ce5ac1", fallback: "承認済みの記憶"))
        }
        let transmission = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.d1b5f3636ed7", fallback: "{{value1}}・チャット", values: [String(describing: appStore.userProfile.coachType.displayName)]),
            sharedCategories: sharedCategories,
            itemCount: context.itemCount + recentMessages.count
        )

        errorPresentation = nil
        failedMessage = nil
        appStore.saveAITransmission(transmission)

        Task { @MainActor in
            do {
                try await aiTrainerBackgroundService.submit(
                    payload: request,
                    transmissionID: transmission.id,
                    settings: appStore.aiSettings
                )
            } catch {
                appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                errorPresentation = AIClientError.presentation(for: error)
                creditAccessIssue = AICreditAccessIssue(error: error)
                failedMessage = message
            }
        }
    }

    private func consumeBackgroundServiceUpdates() {
        if let failure = aiTrainerBackgroundService.takeLatestFailure() {
            errorPresentation = failure.presentation
            creditAccessIssue = failure.creditAccessIssue
            failedMessage = failure.originalMessage
        }

        let candidates = aiTrainerBackgroundService.takeMemoryCandidates()
        if !candidates.isEmpty {
            memoryCandidates = candidates
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !memoryCandidates.isEmpty else { return }
                isReviewingMemories = true
            }
        }
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy) {
        if let last = appStore.coachChatMessages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct CoachContextCoverageView: View {
    @Environment(\.dismiss) private var dismiss
    let coverage: CoachContextCoverage
    let coachPersona: CoachPersona
    let coachRole: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoachIdentityView(
                        persona: coachPersona,
                        role: coachRole,
                        detail: L10n.string("health_meals_body_ai.9db16b95c403", fallback: "この情報を使って提案します。"),
                        avatarSize: 52
                    )
                }

                if !coverage.readyItems.isEmpty {
                    Section(L10n.string("health_meals_body_ai.a01511b65af0", fallback: "参照中")) {
                        ForEach(coverage.readyItems) { item in
                            row(item, symbol: "checkmark.circle.fill")
                        }
                    }
                }

                if !coverage.missingItems.isEmpty {
                    Section(L10n.string("health_meals_body_ai.855dc416beda", fallback: "追加すると助言が安定")) {
                        ForEach(coverage.missingItems) { item in
                            row(
                                item,
                                symbol: item.state == .notShared ? "eye.slash" : "plus.circle"
                            )
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.6867358ace30", fallback: "{{value1}}の参照情報", values: [String(describing: coachPersona.displayName)]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("health_meals_body_ai.16f7a1da8526", fallback: "完了")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: CoachContextCoverageItem, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(item.state == .ready ? AppTheme.accent : AppTheme.mutedInk)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 8)
            Image(systemName: symbol)
                .foregroundStyle(item.state == .ready ? AppTheme.accent : AppTheme.mutedInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachContextCoverageRow-\(item.id)")
    }
}

private struct CoachChatBubble: View {
    let message: CoachChatMessage
    let coachPersona: CoachPersona
    let rating: CoachResponseRating?
    let rateResponse: (CoachResponseRating) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 52) }

            if message.role == .assistant {
                CoachAvatarView(
                    persona: coachPersona,
                    size: 38,
                    cornerRadius: 8
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                if message.role == .assistant {
                    Text(coachPersona.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("aiTrainerReply")
                }
                if message.role == .assistant {
                    CoachFormattedText(content: message.content)
                    if !message.evidence.isEmpty {
                        Divider()
                            .padding(.vertical, 3)
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(message.evidence) { citation in
                                    CoachEvidenceCitationRow(citation: citation)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label(
                                L10n.string("health_meals_body_ai.24d491e59887", fallback: "科学的根拠 {{value1}}件", values: [String(describing: message.evidence.count)]),
                                systemImage: "text.book.closed"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityIdentifier("coachEvidenceSources")
                        }
                    }
                    HStack(spacing: 6) {
                        responseRatingButton(
                            rating: .helpful,
                            systemImage: "hand.thumbsup",
                            accessibilityLabel: L10n.string("health_meals_body_ai.b82b07755169", fallback: "役に立った")
                        )
                        responseRatingButton(
                            rating: .needsImprovement,
                            systemImage: "hand.thumbsdown",
                            accessibilityLabel: L10n.string("health_meals_body_ai.4307847306a2", fallback: "改善が必要")
                        )
                    }
                    .padding(.top, 3)
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(AppTheme.onAccent)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("aiTrainerUserMessage")
                }
            }
            .padding(13)
            .background(
                message.role == .user ? AppTheme.accent : AppTheme.elevatedBackground,
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius)
            )
            .overlay {
                if message.role == .assistant {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
            }

            if message.role == .assistant { Spacer(minLength: 28) }
        }
        .padding(.horizontal)
    }

    private func responseRatingButton(
        rating candidate: CoachResponseRating,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        Button {
            rateResponse(candidate)
        } label: {
            Image(systemName: rating == candidate ? "\(systemImage).fill" : systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(rating == candidate ? AppTheme.accent : AppTheme.mutedInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(rating == candidate ? "selected" : "not selected")
        .accessibilityAddTraits(rating == candidate ? .isSelected : [])
        .accessibilityIdentifier("coachReplyRating-\(candidate.rawValue)-\(message.id.uuidString)")
    }
}

struct CoachEvidenceCitationRow: View {
    let citation: CoachEvidenceCitation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if hasDetails {
                DisclosureGroup(
                    L10n.string("health_meals_body_ai.evidence_summary_applicability", fallback: "要約と適用範囲")
                ) {
                    VStack(alignment: .leading, spacing: 7) {
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_summary", fallback: "研究の結論"),
                            value: citation.evidenceSummary
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_population", fallback: "対象者"),
                            value: citation.population
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_intervention", fallback: "介入"),
                            value: citation.intervention
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_limitations", fallback: "制約"),
                            value: citation.limitations.joined(separator: "\n")
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_applicability", fallback: "今回への適合"),
                            value: applicabilityText
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_newer", fallback: "新しい研究"),
                            value: citation.newerEvidenceNote
                        )
                        evidenceDetail(
                            title: L10n.string("health_meals_body_ai.evidence_license", fallback: "本文ライセンス"),
                            value: citation.fullTextLicense
                        )
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
            if let url = URL(string: citation.url) {
                Link(destination: url) {
                    Label(
                        L10n.string("health_meals_body_ai.evidence_open_paper", fallback: "論文を開く"),
                        systemImage: "arrow.up.right"
                    )
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(citation.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
            HStack(spacing: 5) {
                if let year = citation.year {
                    Text(String(year))
                }
                Text(citation.studyTypeLabel)
                Text(L10n.string("health_meals_body_ai.d13068c0450c", fallback: "確度 {{value1}}", values: [String(describing: citation.confidenceLabel)]))
                Text(citation.sourceScope == "full_text"
                    ? L10n.string("health_meals_body_ai.evidence_full_text", fallback: "本文確認")
                    : L10n.string("health_meals_body_ai.evidence_abstract", fallback: "抄録確認"))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.mutedInk)
        }
    }

    private var hasDetails: Bool {
        !citation.evidenceSummary.isEmpty
            || !citation.population.isEmpty
            || !citation.intervention.isEmpty
            || !citation.limitations.isEmpty
            || !citation.newerEvidenceNote.isEmpty
    }

    private var applicabilityText: String {
        switch citation.applicabilityLabel {
        case "direct": return L10n.string("health_meals_body_ai.evidence_direct", fallback: "対象者が比較的近い")
        case "partial": return L10n.string("health_meals_body_ai.evidence_partial", fallback: "一部条件が近い")
        case "mismatch": return L10n.string("health_meals_body_ai.evidence_mismatch", fallback: "対象者条件が異なる")
        default: return L10n.string("health_meals_body_ai.evidence_unclear", fallback: "情報不足で不明")
        }
    }

    @ViewBuilder
    private func evidenceDetail(title: String, value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(value).foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

private struct AITrainerErrorView: View {
    let presentation: AIErrorPresentation
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("health_meals_body_ai.a25f576fd5c5", fallback: "送信できませんでした"), systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(presentation.message)
            if let recovery = presentation.recovery {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            if canRetry {
                Button(L10n.string("health_meals_body_ai.0a6efdc04529", fallback: "再試行"), action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

struct CoachMemoryCandidateReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [CoachMemoryCandidate]
    let coachPersona: CoachPersona
    let approve: ([CoachMemoryCandidate]) -> Void
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoachIdentityView(
                        persona: coachPersona,
                        role: L10n.string("health_meals_body_ai.a6cf924ebc76", fallback: "記憶の候補"),
                        detail: L10n.string("health_meals_body_ai.d6bc1c633432", fallback: "今後の提案に使ってよい内容だけ選んでください。"),
                        avatarSize: 52
                    )
                }

                Section(L10n.string("health_meals_body_ai.a6cf924ebc76", fallback: "記憶の候補")) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        Button {
                            if selectedIDs.contains(candidate.id) {
                                selectedIDs.remove(candidate.id)
                            } else {
                                selectedIDs.insert(candidate.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(candidate.id) ? AppTheme.accent : AppTheme.mutedInk)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.content)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    if !candidate.reason.isEmpty {
                                        Text(candidate.reason)
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("memoryCandidateToggle-\(index)")
                    }
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.237f4919c9d9", fallback: "記憶を確認"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.fe17bf85705c", fallback: "保存しない")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) {
                        approve(candidates.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("approveMemoryCandidatesButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CoachMemoryListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            Section {
                CoachIdentityView(
                    persona: appStore.userProfile.coachPersona,
                    role: appStore.userProfile.coachType.displayName,
                    detail: L10n.string("health_meals_body_ai.b271ea39b530", fallback: "承認した内容だけを次の提案に使います。"),
                    avatarSize: 52
                )
            }

            if appStore.coachMemories.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("health_meals_body_ai.65a30f6f427a", fallback: "保存した記憶はありません"), systemImage: "brain.head.profile")
                } description: {
                    Text(L10n.string("health_meals_body_ai.7874427a15f4", fallback: "{{value1}}の提案後に、保存を承認した内容だけ表示されます。", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
                }
                .frame(minHeight: 300)
            } else {
                ForEach(appStore.coachMemories) { memory in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(memory.content)
                            .font(.body.weight(.semibold))
                        if !memory.reason.isEmpty {
                            Text(memory.reason)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        Text(AppFormatters.shortDate.string(from: memory.createdAt))
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("coachMemoryRow")
                }
                .onDelete(perform: appStore.deleteCoachMemories)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("health_meals_body_ai.2ccfc30d5576", fallback: "{{value1}}の記憶", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isConfirmingClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L10n.string("health_meals_body_ai.1b92bb1ce7f3", fallback: "記憶をすべて削除"))
                .disabled(appStore.coachMemories.isEmpty)
            }
        }
        .confirmationDialog(L10n.string("health_meals_body_ai.a9219094c815", fallback: "保存した記憶をすべて削除しますか？"), isPresented: $isConfirmingClear) {
            Button(L10n.string("health_meals_body_ai.0c64557b2b39", fallback: "すべて削除"), role: .destructive) { appStore.clearCoachMemories() }
            Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.string("health_meals_body_ai.3a36a6db01f0", fallback: "会話履歴は削除されません。"))
        }
    }
}
