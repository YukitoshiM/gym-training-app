import StoreKit
import SwiftUI

struct AICreditStoreView: View {
    private struct DisplayProduct: Identifiable {
        let id: String
        let displayPrice: String
    }

    @Environment(\.dismiss) private var dismiss
    let settings: AISettings
    let reviewPreview: Bool
    let onBalanceChanged: () async -> Void
    @StateObject private var store = AICreditPurchaseStore()

    init(
        settings: AISettings,
        reviewPreview: Bool = false,
        onBalanceChanged: @escaping () async -> Void
    ) {
        self.settings = settings
        self.reviewPreview = reviewPreview
        self.onBalanceChanged = onBalanceChanged
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(displayProducts) { product in
                        let usage = AICreditPurchaseStore.usageExamples(for: product.id)
                        Button {
                            guard let storeProduct = store.products.first(where: { $0.id == product.id }) else {
                                return
                            }
                            Task {
                                await store.purchase(storeProduct, settings: settings)
                                await onBalanceChanged()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        L10n.string(
                                            "ai_credit.product_amount",
                                            fallback: "{{value1}} AIクレジット",
                                            values: [String(AICreditPurchaseStore.creditAmount(for: product.id))]
                                        )
                                    )
                                        .font(.headline)
                                    Text(L10n.string("ai_credit.never_expires", fallback: "有効期限なし"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.mutedInk)
                                    Text(
                                        L10n.string(
                                            "ai_credit.usage_examples",
                                            fallback: "目安: チャット{{value1}}回・食事解析{{value2}}回・写真解析{{value3}}回",
                                            values: [
                                                String(usage.chat),
                                                String(usage.mealAnalysis),
                                                String(usage.bodyPhotoAnalysis),
                                            ]
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Text(product.displayPrice).fontWeight(.semibold)
                            }
                            .frame(minHeight: 52)
                        }
                        .disabled(store.isBusy)
                        .accessibilityIdentifier(
                            "aiCreditProduct-\(AICreditPurchaseStore.creditAmount(for: product.id))"
                        )
                    }
                    if displayProducts.isEmpty {
                        ContentUnavailableView(
                            L10n.string("ai_credit.products_unavailable", fallback: "購入商品を準備中です"),
                            systemImage: "cart",
                            description: Text(L10n.string("ai_credit.try_later", fallback: "時間をおいてもう一度お試しください。"))
                        )
                    }
                } footer: {
                    Text(L10n.string("ai_credit.purchase_terms", fallback: "購入クレジットは失効しません。譲渡・換金はできません。購入してもバナー広告は非表示になりません。"))
                }
            }
            .navigationTitle(L10n.string("ai_credit.add", fallback: "クレジットを追加"))
            .accessibilityIdentifier("aiCreditStoreView")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("core_ui.fa14b32474d2", fallback: "閉じる")) { dismiss() }
                }
            }
            .task {
                guard !reviewPreview else { return }
                await store.load(settings: settings)
                await onBalanceChanged()
            }
            .alert("BodyMode", isPresented: Binding(
                get: { store.message != nil },
                set: { if !$0 { store.clearMessage() } }
            )) { Button("OK", role: .cancel) {} } message: { Text(store.message ?? "") }
        }
    }

    private var displayProducts: [DisplayProduct] {
        if reviewPreview {
            return [
                DisplayProduct(id: AICreditPurchaseStore.productIDs[0], displayPrice: "$1.99"),
                DisplayProduct(id: AICreditPurchaseStore.productIDs[1], displayPrice: "$4.99"),
                DisplayProduct(id: AICreditPurchaseStore.productIDs[2], displayPrice: "$12.99"),
            ]
        }
        return store.products.map { DisplayProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }
}
