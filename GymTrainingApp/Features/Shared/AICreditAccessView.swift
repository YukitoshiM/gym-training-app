import AuthenticationServices
import SwiftUI

struct AICreditAccessIssue: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case signInRequired
        case insufficientCredits
    }

    var kind: Kind
    var detail: AICreditErrorDetail?

    var id: String {
        switch kind {
        case .signInRequired:
            "sign-in"
        case .insufficientCredits:
            "insufficient-\(detail?.feature ?? "unknown")-\(detail?.cost ?? 0)"
        }
    }

    init?(error: Error) {
        guard let error = error as? AIClientError else { return nil }
        switch error {
        case .accountSignInRequired:
            kind = .signInRequired
            detail = nil
        case .insufficientCredits(let detail):
            kind = .insufficientCredits
            self.detail = detail
        default:
            return nil
        }
    }
}

struct AICreditRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss

    let issue: AICreditAccessIssue
    let settings: AISettings
    let onResolved: () async -> Void

    @State private var signInNonce = ""
    @State private var isSigningIn = false
    @State private var isShowingStore = false
    @State private var message: String?
    @ObservedObject private var rewardedAds = RewardedCreditAdManager.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: issue.kind == .signInRequired ? "person.crop.circle.badge.plus" : "bolt.circle")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    Text(explanation)
                        .font(.body)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail = issue.detail {
                    HStack {
                        Label(detail.feature.aiCreditDisplayName, systemImage: "sparkles")
                        Spacer()
                        Text("\(detail.balance.available) / \(detail.cost)")
                            .font(.headline.monospacedDigit())
                    }
                    .padding(14)
                    .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }

                if issue.kind == .signInRequired {
                    SignInWithAppleButton(.continue) { request in
                        prepareAppleSignIn(request)
                    } onCompletion: { result in
                        guard !signInNonce.isEmpty else { return }
                        Task { await completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .disabled(isSigningIn)
                    .accessibilityIdentifier("creditRecoveryAppleSignInButton")
                } else {
                    Button {
                        Task { await watchRewardedAd() }
                    } label: {
                        Label(
                            L10n.string("ai_credit.watch_ad", fallback: "動画を見て5クレジット"),
                            systemImage: "play.rectangle.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(rewardedAds.isBusy)
                    .accessibilityIdentifier("creditRecoveryRewardedAdButton")

                    Button {
                        isShowingStore = true
                    } label: {
                        Label(L10n.string("ai_credit.buy", fallback: "クレジットを購入"), systemImage: "cart")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("creditRecoveryStoreButton")
                }

                if isSigningIn || rewardedAds.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.critical)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Text(L10n.string("ai_credit.continue_manual", fallback: "AIを使わず続ける"))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("creditRecoveryManualButton")
            }
            .padding(20)
            .background(TrainingBackground())
            .navigationTitle(L10n.string("ai_credit.title", fallback: "AIクレジット"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("core_ui.37a3754927b6", fallback: "キャンセル")) { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingStore) {
                AICreditStoreView(settings: settings) {
                    await resolvedAndDismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if issue.kind == .insufficientCredits {
                UsageAnalytics.shared.record(
                    .aiCreditInsufficientShown,
                    dimension: issue.detail?.feature ?? "unknown"
                )
            }
        }
        .onChange(of: isShowingStore) { _, isShowing in
            if isShowing {
                UsageAnalytics.shared.record(.creditStoreOpened, dimension: "recovery")
            }
        }
    }

    private var title: String {
        switch issue.kind {
        case .signInRequired:
            L10n.string("ai_credit.start_title", fallback: "AIトレーナーを始める")
        case .insufficientCredits:
            L10n.string("ai_credit.insufficient_title", fallback: "AIクレジットが足りません")
        }
    }

    private var explanation: String {
        switch issue.kind {
        case .signInRequired:
            L10n.string(
                "ai_credit.signup_bonus_no_subscription",
                fallback: "Appleで登録すると、最初の20クレジットを受け取れます。課金や自動更新は始まりません。"
            )
        case .insufficientCredits:
            L10n.string(
                "ai_credit.insufficient_choices",
                fallback: "動画でクレジットを受け取るか、必要な分だけ購入できます。手動記録は無料のまま使えます。"
            )
        }
    }

    private func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AIAppleSignIn.nonce()
            signInNonce = nonce
            request.requestedScopes = []
            request.nonce = AIAppleSignIn.hashedNonce(nonce)
        } catch {
            message = error.localizedDescription
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
            let response = try await AIAPIClient(settings: settings)
                .createAppleAccount(
                    identityToken: credential.identityToken,
                    authorizationCode: credential.authorizationCode,
                    rawNonce: signInNonce
                )
            UsageAnalytics.shared.record(.aiAccountRegistered, dimension: "recovery")
            if response.signupGranted {
                UsageAnalytics.shared.record(.aiSignupGrantReceived)
            }
            await resolvedAndDismiss()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            message = AIClientError.presentation(for: error).message
        }
    }

    @MainActor
    private func watchRewardedAd() async {
        do {
            _ = try await rewardedAds.watchAndClaim(settings: settings)
            await resolvedAndDismiss()
        } catch {
            message = AIClientError.presentation(for: error).message
        }
    }

    @MainActor
    private func resolvedAndDismiss() async {
        await onResolved()
        dismiss()
    }
}

extension View {
    func aiCreditRecoverySheet(
        issue: Binding<AICreditAccessIssue?>,
        settings: AISettings,
        onResolved: @escaping () async -> Void = {}
    ) -> some View {
        sheet(item: issue) { issue in
            AICreditRecoverySheet(issue: issue, settings: settings, onResolved: onResolved)
        }
    }
}

extension String {
    var aiCreditDisplayName: String {
        switch self {
        case "chat": L10n.string("health_meals_body_ai.bb243f7c92b4", fallback: "AI相談")
        case "daily_recommendation": L10n.string("health_meals_body_ai.8f9454672f34", fallback: "今日の提案")
        case "plan_generation": L10n.string("health_meals_body_ai.1c1f8aa404fd", fallback: "計画作成")
        case "meal": L10n.string("health_meals_body_ai.3c90f2799f7f", fallback: "食事分析")
        case "body_photo": L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型分析")
        case "weekly_report": L10n.string("ai_credit.weekly", fallback: "週次レポート")
        case "monthly_report": L10n.string("ai_credit.monthly", fallback: "月次レポート")
        case "refund_adjustment": L10n.string("ai_credit.refund_adjustment", fallback: "購入返金の調整")
        default: self
        }
    }
}
