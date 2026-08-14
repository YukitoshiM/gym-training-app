import SwiftUI

struct AITrainerChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var aiTrainerBackgroundService: AITrainerBackgroundService
    @State private var draft: String
    @State private var errorPresentation: AIErrorPresentation?
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
                        detail: "あなたの記録を見ながら一緒に考えます。",
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
                            Text("\(appStore.userProfile.coachPersona.displayName)に相談")
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text("次のトレーニングや食事について聞いてみましょう。")
                                .font(.body)
                                .foregroundStyle(AppTheme.mutedInk)
                                .multilineTextAlignment(.center)
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
                            Text("\(appStore.userProfile.coachPersona.displayName)が回答を考えています")
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
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: appStore.coachChatMessages.count) {
                guard let last = appStore.coachChatMessages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
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
                .accessibilityLabel("AIが参照する記録")
                .accessibilityValue("参照可能\(contextCoverage.readyItems.count)件、不足\(contextCoverage.missingItems.count)件")
                .accessibilityIdentifier("coachContextCoverageButton")

                Button {
                    isConfirmingClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("会話を削除")
                .disabled(appStore.coachChatMessages.isEmpty || isSending)
            }
        }
        .confirmationDialog("AIトレーナーとの会話を削除しますか？", isPresented: $isConfirmingClear) {
            Button("会話を削除", role: .destructive) {
                appStore.clearCoachChatMessages()
                failedMessage = nil
                errorPresentation = nil
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存した記憶は削除されません。")
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
            HStack(alignment: .bottom, spacing: 10) {
                TextField("メッセージ", text: $draft, axis: .vertical)
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
                .accessibilityLabel("送信")
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
            insights: appStore.aiInsights
        )
        let request = CoachChatRequest(
            coachID: appStore.userProfile.coachType.rawValue,
            message: message,
            context: context,
            recentMessages: recentMessages
        )
        var sharedCategories = appStore.aiSettings.dataSharing.enabledCategoryNames + ["会話"]
        if !appStore.coachMemories.isEmpty {
            sharedCategories.append("承認済みの記憶")
        }
        let transmission = AITransmissionRecord(
            purpose: "\(appStore.userProfile.coachType.displayName)・チャット",
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
                appStore.updateAITransmission(id: transmission.id, status: .failed)
                errorPresentation = AIClientError.presentation(for: error)
                failedMessage = message
            }
        }
    }

    private func consumeBackgroundServiceUpdates() {
        if let failure = aiTrainerBackgroundService.takeLatestFailure() {
            errorPresentation = failure.presentation
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
                        detail: "この情報を使って提案します。",
                        avatarSize: 52
                    )
                }

                if !coverage.readyItems.isEmpty {
                    Section("参照中") {
                        ForEach(coverage.readyItems) { item in
                            row(item, symbol: "checkmark.circle.fill")
                        }
                    }
                }

                if !coverage.missingItems.isEmpty {
                    Section("追加すると助言が安定") {
                        ForEach(coverage.missingItems) { item in
                            row(
                                item,
                                symbol: item.state == .notShared ? "eye.slash" : "plus.circle"
                            )
                        }
                    }
                }
            }
            .navigationTitle("\(coachPersona.displayName)の参照情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
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
                                "科学的根拠 \(message.evidence.count)件",
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
                            accessibilityLabel: "役に立った"
                        )
                        responseRatingButton(
                            rating: .needsImprovement,
                            systemImage: "hand.thumbsdown",
                            accessibilityLabel: "改善が必要"
                        )
                    }
                    .padding(.top, 3)
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(AppTheme.onAccent)
                        .lineSpacing(3)
                        .textSelection(.enabled)
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
            .accessibilityIdentifier(message.role == .assistant ? "aiTrainerReply" : "aiTrainerUserMessage")

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
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(rating == candidate ? .isSelected : [])
        .accessibilityIdentifier("coachReplyRating-\(candidate.rawValue)-\(message.id.uuidString)")
    }
}

private struct CoachEvidenceCitationRow: View {
    let citation: CoachEvidenceCitation

    var body: some View {
        Group {
            if let url = URL(string: citation.url) {
                Link(destination: url) {
                    content
                }
            } else {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("科学的根拠、\(citation.title)")
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
                Text("確度 \(citation.confidenceLabel)")
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.mutedInk)
        }
    }
}

private struct AITrainerErrorView: View {
    let presentation: AIErrorPresentation
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("送信できませんでした", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(presentation.message)
            if let recovery = presentation.recovery {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            if canRetry {
                Button("再試行", action: retry)
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
                        role: "記憶の候補",
                        detail: "今後の提案に使ってよい内容だけ選んでください。",
                        avatarSize: 52
                    )
                }

                Section("記憶の候補") {
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
            .navigationTitle("記憶を確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("保存しない") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                    detail: "承認した内容だけを次の提案に使います。",
                    avatarSize: 52
                )
            }

            if appStore.coachMemories.isEmpty {
                ContentUnavailableView {
                    Label("保存した記憶はありません", systemImage: "brain.head.profile")
                } description: {
                    Text("\(appStore.userProfile.coachPersona.displayName)の提案後に、保存を承認した内容だけ表示されます。")
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
        .navigationTitle("\(appStore.userProfile.coachPersona.displayName)の記憶")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isConfirmingClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("記憶をすべて削除")
                .disabled(appStore.coachMemories.isEmpty)
            }
        }
        .confirmationDialog("保存した記憶をすべて削除しますか？", isPresented: $isConfirmingClear) {
            Button("すべて削除", role: .destructive) { appStore.clearCoachMemories() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("会話履歴は削除されません。")
        }
    }
}
