import SwiftUI

struct AdvertisingSettingsSection: View {
    @ObservedObject private var advertising = AdvertisingManager.shared
    @State private var privacyOptionsError: String?

    var body: some View {
        Section {
            LabeledContent("表示方式", value: advertising.statusText)
                .accessibilityIdentifier("advertisingStatus")

            NavigationLink {
                AdvertisingInformationView()
            } label: {
                Label("広告とデータ利用", systemImage: "rectangle.badge.person.crop")
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
                    Label("広告のプライバシー設定", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("advertisingPrivacyOptionsButton")
            }

            NavigationLink {
                AdReportView()
            } label: {
                Label("不適切な広告を報告", systemImage: "exclamationmark.bubble")
            }
            .accessibilityIdentifier("reportAdLink")

            if let privacyOptionsError {
                Text(privacyOptionsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("広告・プライバシー")
        } footer: {
            Text("広告はiPhoneだけに表示し、健康・食事・写真やBodyModeの位置記録を広告選定に使用しません。")
        }
    }
}

struct AdvertisingInformationView: View {
    var body: some View {
        List {
            Section("表示方針") {
                Label("操作を遮らないバナーのみ", systemImage: "rectangle.bottomthird.inset.filled")
                Label("パーソナライズ無効", systemImage: "person.crop.circle.badge.xmark")
                Label("健康記録と広告データを分離", systemImage: "square.split.2x1")
            }

            Section("広告事業者") {
                LabeledContent("配信", value: "Google AdMob")
                Text("広告配信では、IPアドレス、端末・アプリの概要情報、SDKの診断・パフォーマンス情報、広告の表示・操作情報がGoogleに送信され、IPアドレスから概算位置が推定される場合があります。BodyModeで記録した体重、心拍、睡眠、食事、写真、トレーニング、目標、GPS・ジム位置は広告リクエストに含めません。")
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Section("関連情報") {
                Link(destination: URL(string: "https://policies.google.com/privacy")!) {
                    Label("Googleプライバシーポリシー", systemImage: "safari")
                }
                Link(destination: URL(string: "https://support.google.com/admob/answer/6128543")!) {
                    Label("Googleの広告データ利用", systemImage: "safari")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("広告とデータ利用")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("advertisingInformationView")
    }
}

struct AdReportView: View {
    enum Reason: String, CaseIterable, Identifiable {
        case inappropriate = "不適切な内容"
        case misleading = "誤解を招く内容"
        case offensive = "不快な内容"
        case ageRating = "年齢に適さない"
        case other = "その他"

        var id: String { rawValue }
    }

    @State private var reason: Reason = .inappropriate
    @State private var details = ""

    var body: some View {
        Form {
            Section("理由") {
                Picker("報告理由", selection: $reason) {
                    ForEach(Reason.allCases) { reason in
                        Text(reason.rawValue).tag(reason)
                    }
                }
            }

            Section("補足") {
                TextField("広告の商品名や気になった内容", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("adReportDetailsField")
            }

            Section {
                ShareLink(item: reportText) {
                    Label("報告内容を送信", systemImage: "paperplane")
                }
                .accessibilityIdentifier("submitAdReportButton")
            } footer: {
                Text("メールなどの送信先を選び、BodyModeサポートへお送りください。身体や健康の記録は報告文に含まれません。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("広告を報告")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("adReportView")
    }

    private var reportText: String {
        let detailText = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "BodyMode 広告報告",
            "バージョン: \(LegalConfiguration.appVersion)",
            "理由: \(reason.rawValue)",
            "補足: \(detailText.isEmpty ? "なし" : detailText)"
        ].joined(separator: "\n")
    }
}
