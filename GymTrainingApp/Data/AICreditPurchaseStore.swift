import StoreKit

@MainActor
final class AICreditPurchaseStore: ObservableObject {
    struct UsageExamples: Equatable {
        let chat: Int
        let mealAnalysis: Int
        let bodyPhotoAnalysis: Int
    }

    enum PurchaseError: LocalizedError {
        case unverified
        var errorDescription: String? {
            L10n.string(
                "ai_credit.purchase_verification_failed",
                fallback: "App Storeの購入を確認できませんでした。"
            )
        }
    }
    static let productIDs = [
        "com.yukitoshim.gymtrainingapp.credits50",
        "com.yukitoshim.gymtrainingapp.credits150",
        "com.yukitoshim.gymtrainingapp.credits500",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    func load(settings: AISettings) async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { Self.creditAmount(for: $0.id) < Self.creditAmount(for: $1.id) }
            await recoverUnfinished(settings: settings)
        } catch {
            message = error.localizedDescription
        }
    }

    func purchase(_ product: Product, settings: AISettings) async {
        guard let appAccountToken = SecureSettingsStore.appAccountToken else {
            message = AIClientError.accountSignInRequired.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
            switch result {
            case .success(let verification):
                let response = try await verifyAndFinish(verification, settings: settings)
                UsageAnalytics.shared.record(.creditPurchaseCompleted)
                let purchasedAmount = Self.creditAmount(for: product.id)
                if response.grantedAmount < purchasedAmount {
                    message = L10n.string(
                        "ai_credit.purchase_adjusted",
                        fallback: "返金分を調整し、{{value1}}クレジットを追加しました。",
                        values: [String(response.grantedAmount)]
                    )
                } else {
                    message = L10n.string("ai_credit.purchase_complete", fallback: "クレジットを追加しました。")
                }
            case .pending:
                UsageAnalytics.shared.record(.creditPurchasePending)
                message = L10n.string("ai_credit.purchase_pending", fallback: "購入は承認待ちです。完了後に自動で反映します。")
            case .userCancelled:
                UsageAnalytics.shared.record(.creditPurchaseCancelled)
                break
            @unknown default:
                message = L10n.string("ai_credit.purchase_unknown", fallback: "購入状態を確認できませんでした。")
            }
        } catch {
            UsageAnalytics.shared.record(.creditPurchaseFailed)
            message = AIClientError.presentation(for: error).message
        }
    }

    func clearMessage() { message = nil }

    static func creditAmount(for productID: String) -> Int {
        switch productID {
        case "com.yukitoshim.gymtrainingapp.credits50": 50
        case "com.yukitoshim.gymtrainingapp.credits150": 150
        case "com.yukitoshim.gymtrainingapp.credits500": 500
        default: 0
        }
    }

    static func usageExamples(for productID: String) -> UsageExamples {
        let credits = creditAmount(for: productID)
        return UsageExamples(
            chat: credits,
            mealAnalysis: credits / 3,
            bodyPhotoAnalysis: credits / 4
        )
    }

    private func recoverUnfinished(settings: AISettings) async {
        for await verification in Transaction.unfinished {
            _ = try? await verifyAndFinish(verification, settings: settings)
        }
    }

    private func verifyAndFinish(
        _ verification: VerificationResult<Transaction>,
        settings: AISettings
    ) async throws -> AICreditPurchaseVerifyResponse {
        guard case .verified(let transaction) = verification else {
            throw PurchaseError.unverified
        }
        let response = try await AIAPIClient(settings: settings)
            .verifyCreditPurchase(signedTransaction: verification.jwsRepresentation)
        await transaction.finish()
        return response
    }
}
