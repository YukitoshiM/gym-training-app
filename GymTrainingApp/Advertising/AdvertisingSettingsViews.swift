import SwiftUI

struct AdvertisingSettingsSection: View {
    @ObservedObject private var advertising = AdvertisingManager.shared
    @ObservedObject private var rewardedAds = RewardedCreditAdManager.shared
    @State private var privacyOptionsError: String?
    @State private var rewardedPreviewMessage: String?
    @State private var rewardedPreviewSucceeded = false

    var body: some View {
        Section {
            LabeledContent(L10n.string("core_ui.0f0e0b4defc7", fallback: "表示方式"), value: advertising.statusText)
                .accessibilityIdentifier("advertisingStatus")

            NavigationLink {
                AdvertisingInformationView()
            } label: {
                Label(L10n.string("core_ui.6ecd0742beb6", fallback: "広告とデータ利用"), systemImage: "rectangle.badge.person.crop")
            }
            .accessibilityIdentifier("advertisingInformationLink")

            if advertising.isPrivacyOptionsRequired {
                Button {
                    Task {
                        do {
                            try await advertising.presentPrivacyOptions()
                            privacyOptionsError = nil
                        } catch {
                            privacyOptionsError = error.localizedDescription
                        }
                    }
                } label: {
                    Label(L10n.string("core_ui.aac8d0ee418a", fallback: "広告のプライバシー設定"), systemImage: "hand.raised")
                }
                .accessibilityIdentifier("advertisingPrivacyOptionsButton")
            }

            NavigationLink {
                AdReportView()
            } label: {
                Label(L10n.string("core_ui.fb66b4fecde1", fallback: "不適切な広告を報告"), systemImage: "exclamationmark.bubble")
            }
            .accessibilityIdentifier("reportAdLink")

            if advertising.canPreviewRewardedAd {
                Button {
                    Task { await previewRewardedAd() }
                } label: {
                    Label(
                        "\(L10n.string("ai_credit.source_ad", fallback: "動画広告")) · \(L10n.string("core_ui.42da49eab006", fallback: "テスト広告"))",
                        systemImage: "play.rectangle.fill"
                    )
                }
                .disabled(rewardedAds.isBusy || !advertising.canDisplayAds)
                .accessibilityIdentifier("rewardedAdPreviewButton")

                if rewardedAds.isBusy {
                    ProgressView()
                        .accessibilityIdentifier("rewardedAdPreviewProgress")
                }

                if let rewardedPreviewMessage {
                    Text(rewardedPreviewMessage)
                        .font(.footnote)
                        .foregroundStyle(rewardedPreviewSucceeded ? AppTheme.mutedInk : AppTheme.critical)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rewardedAdPreviewMessage")
                }
            }

            if let privacyOptionsError {
                Text(privacyOptionsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(L10n.string("core_ui.0defda7f85a6", fallback: "広告・プライバシー"))
        } footer: {
            Text(L10n.string("core_ui.0200140f3573", fallback: "広告はiPhoneだけに表示し、健康・食事・写真やBodyModeの位置記録を広告選定に使用しません。"))
        }
    }

    @MainActor
    private func previewRewardedAd() async {
        rewardedPreviewMessage = nil
        rewardedPreviewSucceeded = false
        do {
            try await rewardedAds.preview()
            rewardedPreviewSucceeded = true
            rewardedPreviewMessage = L10n.string("core_ui.42da49eab006", fallback: "テスト広告")
        } catch is CancellationError {
            rewardedPreviewMessage = L10n.string("core_ui.37a3754927b6", fallback: "キャンセル")
        } catch {
            rewardedPreviewMessage = AIClientError.presentation(for: error).message
        }
    }
}

struct AdvertisingInformationView: View {
    var body: some View {
        List {
            Section(L10n.string("core_ui.492de47a7b63", fallback: "表示方針")) {
                Label(L10n.string("core_ui.b8fd47274dc1", fallback: "操作を遮らないバナーのみ"), systemImage: "rectangle.bottomthird.inset.filled")
                Label(L10n.string("core_ui.84cf5a25fb13", fallback: "パーソナライズ無効"), systemImage: "person.crop.circle.badge.xmark")
                Label(L10n.string("core_ui.f94b300a8f3b", fallback: "健康記録と広告データを分離"), systemImage: "square.split.2x1")
            }

            Section(L10n.string("core_ui.b28b3c7c3418", fallback: "広告事業者")) {
                LabeledContent(L10n.string("core_ui.7759ae6468d0", fallback: "配信"), value: "Google AdMob")
                Text(L10n.string("core_ui.ca5b5635259a", fallback: "広告配信では、IPアドレス、端末・アプリの概要情報、SDKの診断・パフォーマンス情報、広告の表示・操作情報がGoogleに送信され、IPアドレスから概算位置が推定される場合があります。BodyModeで記録した体重、心拍、睡眠、食事、写真、トレーニング、目標、GPS・ジム位置は広告リクエストに含めません。"))
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Section(L10n.string("core_ui.864932cf530c", fallback: "関連情報")) {
                Link(destination: URL(string: "https://policies.google.com/privacy")!) {
                    Label(L10n.string("core_ui.d8ded648c16c", fallback: "Googleプライバシーポリシー"), systemImage: "safari")
                }
                Link(destination: URL(string: "https://support.google.com/admob/answer/6128543")!) {
                    Label(L10n.string("core_ui.2a02f05069da", fallback: "Googleの広告データ利用"), systemImage: "safari")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("core_ui.6ecd0742beb6", fallback: "広告とデータ利用"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("advertisingInformationView")
    }
}

struct AdReportView: View {
    enum Reason: String, CaseIterable, Identifiable {
        case inappropriate
        case misleading
        case offensive
        case ageRating
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inappropriate: L10n.string("core_ui.5dea169a560e", fallback: "不適切な内容")
            case .misleading: L10n.string("core_ui.692e3d951baa", fallback: "誤解を招く内容")
            case .offensive: L10n.string("core_ui.d1460b55a3de", fallback: "不快な内容")
            case .ageRating: L10n.string("core_ui.4c70eaf9acf8", fallback: "年齢に適さない")
            case .other: L10n.string("core_ui.004da00de9b0", fallback: "その他")
            }
        }
    }

    @State private var reason: Reason = .inappropriate
    @State private var details = ""

    var body: some View {
        Form {
            Section(L10n.string("core_ui.3f755a378fa9", fallback: "理由")) {
                Picker(L10n.string("core_ui.8154b5aebe16", fallback: "報告理由"), selection: $reason) {
                    ForEach(Reason.allCases) { reason in
                        Text(reason.title).tag(reason)
                    }
                }
            }

            Section(L10n.string("core_ui.f4cfe025d665", fallback: "補足")) {
                TextField(L10n.string("core_ui.b059d3be52a7", fallback: "広告の商品名や気になった内容"), text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("adReportDetailsField")
            }

            Section {
                ShareLink(item: reportText) {
                    Label(L10n.string("core_ui.3fc270c70af2", fallback: "報告内容を送信"), systemImage: "paperplane")
                }
                .accessibilityIdentifier("submitAdReportButton")
            } footer: {
                Text(L10n.string("core_ui.4c48305c3a97", fallback: "メールなどの送信先を選び、BodyModeサポートへお送りください。身体や健康の記録は報告文に含まれません。"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("core_ui.845fb299a5e2", fallback: "広告を報告"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("adReportView")
    }

    private var reportText: String {
        let detailText = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            L10n.string("core_ui.bf84924a22d4", fallback: "BodyMode 広告報告"),
            L10n.string("core_ui.9aab60659c0d", fallback: "バージョン: {{value1}}", values: [String(describing: LegalConfiguration.appVersion)]),
            L10n.string("core_ui.e5553c6ea028", fallback: "理由: {{value1}}", values: [String(describing: reason.title)]),
            L10n.string("core_ui.f25b70d5d45b", fallback: "補足: {{value1}}", values: [String(describing: detailText.isEmpty ? "なし" : detailText)])
        ].joined(separator: "\n")
    }
}
