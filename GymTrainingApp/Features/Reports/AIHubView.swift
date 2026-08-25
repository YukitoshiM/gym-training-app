import AuthenticationServices
import SwiftUI

struct AIHubView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingAIPlanCoach = false
    @State private var pendingAIPlan: TrainingPlan?
    @State private var aiPlanForEditing: TrainingPlan?
    @State private var usageSummary: AIUsageSummary?
    @State private var signInNonce = ""
    @State private var isSigningIn = false
    @State private var accountMessage: String?
    @State private var isShowingCreditStore = false
    @ObservedObject private var rewardedAds = RewardedCreditAdManager.shared

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    AIHubSectionTitle(title: L10n.string("health_meals_body_ai.f0b4abc21d0c", fallback: "AIコーチ"))

                    if !SecureSettingsStore.hasAIAccount || usageSummary == nil {
                        aiAccountCard
                    } else if let credits = usageSummary?.credits {
                        AICreditBalanceCard(summary: credits)
                        NavigationLink {
                            AICreditHistoryView(settings: appStore.aiSettings)
                        } label: {
                            Label(L10n.string("ai_credit.history", fallback: "クレジット履歴"), systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            Task { await watchRewardedAd() }
                        } label: {
                            Label(
                                L10n.string("ai_credit.watch_ad", fallback: "動画を見て5クレジット"),
                                systemImage: "play.rectangle.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(rewardedAds.isBusy || credits.unlimited)
                        .accessibilityIdentifier("aiRewardedCreditButton")

                        if !credits.unlimited {
                            Button {
                                isShowingCreditStore = true
                            } label: {
                                Label(L10n.string("ai_credit.buy", fallback: "クレジットを購入"), systemImage: "cart")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("aiCreditStoreButton")
                        }
                    }

                    NavigationLink {
                        AITrainerChatView()
                    } label: {
                        AITrainerEntryCard(
                            persona: appStore.userProfile.coachPersona,
                            coachRole: appStore.userProfile.coachType.displayName,
                            coachingStyle: appStore.userProfile.coachingStyle,
                            detail: appStore.userProfile.coachType.expertiseProfile.promise
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiHubTrainerLink")
                    .appTourTarget(.aiTrainer)

                    Button {
                        isShowingAIPlanCoach = true
                    } label: {
                        AIHubNavigationRow(
                            title: L10n.string("health_meals_body_ai.2e6d80b23ca9", fallback: "トレーニング計画"),
                            detail: L10n.string("health_meals_body_ai.227ec548982d", fallback: "{{value1}}と作成・相談して修正", values: [String(describing: appStore.userProfile.coachPersona.displayName)]),
                            systemImage: "sparkles.rectangle.stack",
                            coachPersona: appStore.userProfile.coachPersona
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiHubPlanCoachButton")

                    AIHubSectionTitle(title: L10n.string("health_meals_body_ai.09ef2612396c", fallback: "写真で分析"))

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        NavigationLink {
                            MealListView(startsWithEditor: true)
                        } label: {
                            AIHubToolCard(
                                title: L10n.string("health_meals_body_ai.3d31c5bc2270", fallback: "食事写真AI"),
                                detail: L10n.string("health_meals_body_ai.3ef862b1075b", fallback: "{{value1}}が料理とPFCを確認", values: [String(describing: appStore.userProfile.coachPersona.displayName)]),
                                systemImage: "fork.knife",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubMealPhotoLink")

                        NavigationLink {
                            BodyPhotoListView(startsWithEditor: true)
                        } label: {
                            AIHubToolCard(
                                title: L10n.string("health_meals_body_ai.0b508232ea17", fallback: "体型写真AI"),
                                detail: L10n.string("health_meals_body_ai.eed6016a2209", fallback: "{{value1}}が複数方向を確認", values: [String(describing: appStore.userProfile.coachPersona.displayName)]),
                                systemImage: "camera.viewfinder",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubBodyPhotoLink")
                    }
                    .appTourTarget(.aiPhotoTools)

                    AIHubSectionTitle(title: L10n.string("health_meals_body_ai.05b6f177b81d", fallback: "振り返り"))

                    VStack(spacing: 10) {
                        NavigationLink {
                            AIReportView()
                        } label: {
                            AIHubNavigationRow(
                                title: L10n.string("health_meals_body_ai.fafa909be0a5", fallback: "週次・月次レポート"),
                                detail: latestWeeklyInsight?.actionSuggestion ?? L10n.string("health_meals_body_ai.cafd0ed89a65", fallback: "記録をまとめて次の行動と翌月目標を提案"),
                                systemImage: "chart.line.text.clipboard",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubReportLink")

                        NavigationLink {
                            CoachMemoryListView()
                        } label: {
                            AIHubNavigationRow(
                                title: L10n.string("health_meals_body_ai.9341e4c7e4b5", fallback: "{{value1}}が覚えていること", values: [String(describing: appStore.userProfile.coachPersona.displayName)]),
                                detail: L10n.string("health_meals_body_ai.b5a13bb1eb04", fallback: "確認済みの記憶 {{value1}}件", values: [String(describing: appStore.coachMemories.count)]),
                                systemImage: "brain.head.profile",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubMemoryLink")
                    }

                    if let usageSummary {
                        AIUsageQuotaCard(summary: usageSummary)
                    }

                    Label(
                        appStore.aiSettings.isEnabled ? L10n.string("health_meals_body_ai.e92c4b6bfa1d", fallback: "AI接続が有効です") : L10n.string("health_meals_body_ai.ebaaf28b717e", fallback: "AI機能は設定でオフです"),
                        systemImage: appStore.aiSettings.isEnabled ? "checkmark.circle" : "slash.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding()
            }
            .background(TrainingBackground())
            .navigationTitle("AI")
            .alert(
                L10n.string("ai_credit.account_notice", fallback: "AIアカウント"),
                isPresented: Binding(
                    get: { accountMessage != nil },
                    set: { if !$0 { accountMessage = nil } }
                )
            ) {
                Button(L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了"), role: .cancel) {}
            } message: {
                Text(accountMessage ?? "")
            }
            .task(id: appStore.aiSettings) {
                await refreshUsage()
            }
            .sheet(isPresented: $isShowingAIPlanCoach, onDismiss: presentPendingAIPlan) {
                AIPlanCoachView { plan in
                    pendingAIPlan = plan
                }
            }
            .sheet(item: $aiPlanForEditing) { plan in
                PlanEditorView(plan: plan, mode: .aiCoach) {
                    aiPlanForEditing = nil
                }
            }
            .sheet(isPresented: $isShowingCreditStore) {
                AICreditStoreView(settings: appStore.aiSettings) {
                    await refreshUsage()
                }
            }
        }
    }

    private func presentPendingAIPlan() {
        guard let pendingAIPlan else { return }
        self.pendingAIPlan = nil
        aiPlanForEditing = pendingAIPlan
    }

    private func refreshUsage() async {
        guard appStore.aiSettings.isEnabled else {
            usageSummary = nil
            return
        }
        usageSummary = try? await AIAPIClient(settings: appStore.aiSettings).usage()
    }

    private var aiAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.string("ai_credit.start_title", fallback: "AIトレーナーを始める"),
                systemImage: "apple.logo"
            )
            .font(.title3.weight(.bold))
            Text(
                SecureSettingsStore.hasAIAccount
                    ? L10n.string("ai_credit.sign_in_again", fallback: "セッションの有効期限が切れました。もう一度サインインしてください。")
                    : L10n.string("ai_credit.signup_bonus", fallback: "Appleで登録すると、最初の20クレジットを受け取れます。手動記録は登録なしで使えます。")
            )
            .font(.subheadline)
            .foregroundStyle(AppTheme.mutedInk)

            SignInWithAppleButton(.continue) { request in
                do {
                    let nonce = try AIAppleSignIn.nonce()
                    signInNonce = nonce
                    request.requestedScopes = []
                    request.nonce = AIAppleSignIn.hashedNonce(nonce)
                } catch {
                    accountMessage = error.localizedDescription
                }
            } onCompletion: { result in
                guard !signInNonce.isEmpty else { return }
                Task { await completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .disabled(isSigningIn)
            .accessibilityIdentifier("aiAppleSignInButton")

            if isSigningIn {
                ProgressView(L10n.string("ai_credit.signing_in", fallback: "登録しています"))
                    .font(.footnote)
            }
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    @MainActor
    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        defer {
            isSigningIn = false
            signInNonce = ""
        }
        do {
            let credential = try AIAppleSignIn.credential(from: result)
            let response = try await AIAPIClient(settings: appStore.aiSettings)
                .createAppleAccount(
                    identityToken: credential.identityToken,
                    authorizationCode: credential.authorizationCode,
                    rawNonce: signInNonce
                )
            UsageAnalytics.shared.record(.aiAccountRegistered, dimension: "ai_hub")
            if response.signupGranted {
                UsageAnalytics.shared.record(.aiSignupGrantReceived)
            }
            await refreshUsage()
            accountMessage = response.signupGranted
                ? L10n.string("ai_credit.bonus_received", fallback: "{{value1}}クレジットを受け取りました。", values: [String(response.signupGrantedAmount)])
                : L10n.string("ai_credit.sign_in_complete", fallback: "Appleアカウントでサインインしました。")
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            accountMessage = AIClientError.presentation(for: error).message
        }
    }

    @MainActor
    private func watchRewardedAd() async {
        do {
            let claim = try await rewardedAds.watchAndClaim(settings: appStore.aiSettings)
            await refreshUsage()
            accountMessage = claim.granted
                ? L10n.string("ai_credit.reward_received", fallback: "5クレジットを受け取りました。")
                : L10n.string("ai_credit.reward_limit", fallback: "本日の広告特典は受取済みです。")
        } catch {
            accountMessage = AIClientError.presentation(for: error).message
        }
    }
}

private struct AICreditBalanceCard: View {
    let summary: AICreditSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.string("ai_credit.balance", fallback: "AIクレジット"), systemImage: "bolt.fill")
                    .font(.headline)
                Spacer()
                Text(summary.unlimited ? "∞" : String(summary.balance?.available ?? 0))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
            }
            if !summary.unlimited {
                let costs = summary.featureCosts.sorted { $0.value < $1.value }
                Text(costs.map { "\($0.key.aiCreditFeatureName) \($0.value)" }.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("aiCreditBalanceCard")
    }
}

private extension String {
    var aiCreditFeatureName: String {
        switch self {
        case "chat": L10n.string("health_meals_body_ai.bb243f7c92b4", fallback: "相談")
        case "daily_recommendation": L10n.string("health_meals_body_ai.8f9454672f34", fallback: "今日の提案")
        case "plan_generation": L10n.string("health_meals_body_ai.1c1f8aa404fd", fallback: "計画")
        case "meal": L10n.string("health_meals_body_ai.3c90f2799f7f", fallback: "食事")
        case "body_photo": L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型")
        case "weekly_report": L10n.string("ai_credit.weekly", fallback: "週次レポート")
        case "monthly_report": L10n.string("ai_credit.monthly", fallback: "月次レポート")
        default: self
        }
    }
}

private struct AIHubSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppTheme.mutedInk)
    }
}

private struct AIUsageQuotaCard: View {
    let summary: AIUsageSummary
    @State private var isExpanded = false

    private var isRunningLow: Bool {
        summary.isEnforced && summary.features.contains { $0.remaining <= 3 }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 10) {
                ForEach(summary.features) { feature in
                    HStack {
                        Text(feature.displayName)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(
                            summary.isEnforced
                                ? L10n.string("health_meals_body_ai.37ee0f70625a", fallback: "残り {{value1}} / {{value2}}", values: [String(describing: feature.remaining), String(describing: feature.limit)])
                                : "利用 \(feature.used)回"
                        )
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(
                                summary.isEnforced && feature.remaining <= 3
                                    ? AppTheme.accent
                                    : AppTheme.mutedInk
                            )
                    }
                    .frame(minHeight: 32)
                }
            }
            .padding(.top, 12)
        } label: {
            Label(
                summary.isEnforced
                    ? (isRunningLow ? L10n.string("health_meals_body_ai.a7d57de9953d", fallback: "AI利用枠を確認") : L10n.string("health_meals_body_ai.d320406ff6df", fallback: "AI利用枠に余裕があります"))
                    : L10n.string("release_delta.ai_unlimited", fallback: "AI利用上限なし"),
                systemImage: isRunningLow ? "hourglass.bottomhalf.filled" : "checkmark.circle"
            )
            .font(.headline)
            .foregroundStyle(isRunningLow ? AppTheme.accent : AppTheme.mutedInk)
        }
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityIdentifier("aiUsageQuotaCard")
    }
}

private struct AITrainerEntryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let persona: CoachPersona
    let coachRole: String
    let coachingStyle: CoachingStyle
    let detail: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    CoachAvatarView(persona: persona, size: 128, height: 144)
                    coachDetails
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    CoachAvatarView(persona: persona, size: 96, height: 112)
                    coachDetails
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
        }
    }

    private var coachDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("health_meals_body_ai.1ff87d20c07b", fallback: "担当 {{value1}}", values: [String(describing: persona.displayName)]))
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            Text(L10n.string("health_meals_body_ai.6bf0c99ca090", fallback: "{{value1}}・{{value2}}", values: [String(describing: coachRole), String(describing: coachingStyle.displayName)]))
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            openLabel
        }
    }

    private var openLabel: some View {
        Label(L10n.string("health_meals_body_ai.b0913a8eb8e5", fallback: "相談する"), systemImage: "message.fill")
            .font(.headline)
            .foregroundStyle(AppTheme.accent)
            .frame(minHeight: 44)
    }
}

private struct AIHubToolCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let coachPersona: CoachPersona

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                CoachAvatarView(persona: coachPersona, size: 34)
            }

            Spacer(minLength: 2)

            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

private struct AIHubNavigationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var coachPersona: CoachPersona? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let coachPersona {
                CoachAvatarView(persona: coachPersona, size: 44)
            } else {
                IconBadge(systemImage: systemImage, tint: AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.mutedInk)
        }
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

#Preview {
    AIHubView()
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
