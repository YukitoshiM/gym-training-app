import SwiftUI

/// Compact, non-blocking credit context shown beside an AI action.
/// The server remains authoritative; fallback costs only keep the UI informative offline.
struct AICreditCostStatusView: View {
    let feature: String
    let settings: AISettings

    @State private var credits: AICreditSummary?

    var body: some View {
        HStack(spacing: 8) {
            Label(costText, systemImage: "bolt.fill")
            Spacer(minLength: 8)
            Text(balanceText)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.mutedInk)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aiCreditCost-\(feature)")
        .task(id: settings) {
            guard settings.isEnabled, SecureSettingsStore.hasAIAccount else {
                credits = nil
                return
            }
            credits = try? await AIAPIClient(settings: settings).usage().credits
        }
    }

    private var cost: Int {
        credits?.featureCosts[feature] ?? Self.fallbackCosts[feature] ?? 1
    }

    private var costText: String {
        L10n.string(
            "ai_credit.action_cost",
            fallback: "今回 {{value1}}クレジット",
            values: [cost.formatted()]
        )
    }

    private var balanceText: String {
        if credits?.unlimited == true {
            return L10n.string("ai_credit.unlimited", fallback: "利用無制限")
        }
        if !SecureSettingsStore.hasAIAccount {
            return L10n.string("ai_credit.signup_short", fallback: "登録で20クレジット")
        }
        if let available = credits?.balance?.available {
            return L10n.string(
                "ai_credit.balance_short",
                fallback: "残高 {{value1}}",
                values: [available.formatted()]
            )
        }
        return L10n.string("ai_credit.balance_checking", fallback: "残高を確認中")
    }

    private static let fallbackCosts = [
        "chat": 1,
        "daily_recommendation": 1,
        "plan_generation": 2,
        "meal": 3,
        "body_photo": 4,
        "weekly_report": 5,
        "monthly_report": 5,
    ]
}
