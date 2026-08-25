import SwiftUI

struct AICreditHistoryView: View {
    let settings: AISettings
    @State private var response: AICreditHistoryResponse?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let response {
                Section {
                    LabeledContent(L10n.string("ai_credit.balance", fallback: "AIクレジット")) {
                        Text(String(response.balance.available)).font(.title3.bold().monospacedDigit())
                    }
                    if let supportID = response.supportID {
                        LabeledContent(AppLanguagePreference.usesJapanese ? "サポートID" : "Support ID") {
                            Text(supportID)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                Section(L10n.string("ai_credit.history", fallback: "クレジット履歴")) {
                    ForEach(response.events) { event in
                        HStack(spacing: 12) {
                            Image(systemName: event.amount >= 0 ? "plus.circle.fill" : "bolt.fill")
                                .foregroundStyle(event.amount >= 0 ? Color.green : AppTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.label).font(.body.weight(.semibold))
                                Text(Date(timeIntervalSince1970: TimeInterval(event.occurredAt)), style: .date)
                                    .font(.caption).foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer()
                            Text("\(event.amount > 0 ? "+" : "")\(event.amount)")
                                .font(.headline.monospacedDigit())
                        }
                        .frame(minHeight: 48)
                    }
                }
            } else if errorMessage == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.string("ai_credit.history", fallback: "クレジット履歴"))
        .task { await load() }
        .alert("BodyMode", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        do { response = try await AIAPIClient(settings: settings).creditHistory() }
        catch { errorMessage = AIClientError.presentation(for: error).message }
    }
}

private extension AICreditHistoryEvent {
    var label: String {
        if let feature { return feature.replacingOccurrences(of: "_", with: " ") }
        return switch source {
        case "signup": L10n.string("ai_credit.source_signup", fallback: "初回特典")
        case "rewarded_ad": L10n.string("ai_credit.source_ad", fallback: "動画広告")
        case "purchase": L10n.string("ai_credit.source_purchase", fallback: "購入")
        case "admin": L10n.string("ai_credit.source_admin", fallback: "運営付与")
        default: L10n.string("ai_credit.adjustment", fallback: "残高調整")
        }
    }
}
