import SwiftUI

struct LegalAndSupportSettingsSection: View {
    var body: some View {
        Section("法務・サポート") {
            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                Label("利用規約", systemImage: "doc.text")
            }
            .accessibilityIdentifier("termsOfUseLink")

            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                Label("プライバシーポリシー", systemImage: "hand.raised")
            }
            .accessibilityIdentifier("privacyPolicyLink")

            NavigationLink {
                HealthAINoticeView()
            } label: {
                Label("健康・AIに関する注意", systemImage: "heart.text.clipboard")
            }
            .accessibilityIdentifier("healthAINoticeLink")

            NavigationLink {
                SupportInformationView()
            } label: {
                Label("サポート", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("supportInformationLink")

            LabeledContent("バージョン", value: LegalConfiguration.appVersion)
                .foregroundStyle(AppTheme.mutedInk)
        }
    }
}

struct LegalDocumentView: View {
    let document: BodyModeLegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)

                    Text("制定日: \(document.effectiveDate)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(AppTheme.mutedInk)
                            .textSelection(.enabled)
                    }
                }

                if let publishedURL = document.publishedURL {
                    Link(destination: publishedURL) {
                        Label("Web版を開く", systemImage: "safari")
                    }
                    .accessibilityIdentifier("publishedLegalDocumentLink")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(document.accessibilityIdentifier)
    }
}

struct HealthAINoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                noticeSection(
                    title: "健康情報について",
                    body: "BodyModeは日々の記録と振り返りを支援する健康・フィットネスアプリです。診断、治療、疾病の予防を目的とする医療機器ではありません。体調に不安がある場合や、痛み・めまい・息苦しさなどがある場合は運動を中止し、医療専門家へ相談してください。"
                )

                noticeSection(
                    title: "AIの提案について",
                    body: "AIによる食事推定、写真比較、トレーニング提案、週次コメントは参考情報です。画像から量、栄養、体脂肪率、健康状態を正確に判定することはできません。提案を確認し、必要に応じて手動で修正してください。"
                )

                noticeSection(
                    title: "センサー値について",
                    body: "心拍数、消費エネルギー、睡眠、動作回数、疲労度などには測定誤差があります。緊急時の判断や医療上の意思決定には使用しないでください。"
                )

                noticeSection(
                    title: "安全なトレーニング",
                    body: "体調、経験、設備に合わせて重量と運動量を調整し、無理な減量や急激な負荷増加を避けてください。必要に応じて医師、管理栄養士、理学療法士、資格を持つトレーナーへ相談してください。"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("健康・AIに関する注意")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("healthAINoticeView")
    }

    private func noticeSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(body)
                .foregroundStyle(AppTheme.mutedInk)
                .textSelection(.enabled)
        }
    }
}

struct SupportInformationView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                if let supportEmail = LegalConfiguration.supportEmail,
                   let mailURL = URL(string: "mailto:\(supportEmail)") {
                    Button {
                        openURL(mailURL)
                    } label: {
                        Label("メールで問い合わせる", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("supportEmailButton")
                }

                if let supportURL = LegalConfiguration.supportURL {
                    Link(destination: supportURL) {
                        Label("サポートサイトを開く", systemImage: "safari")
                    }
                    .accessibilityIdentifier("supportWebsiteLink")
                }

                if LegalConfiguration.supportEmail == nil && LegalConfiguration.supportURL == nil {
                    Label(
                        "TestFlightの「フィードバックを送信」からご連絡ください。",
                        systemImage: "bubble.left.and.exclamationmark.bubble.right"
                    )
                    .foregroundStyle(AppTheme.mutedInk)
                }
            } header: {
                Text("お問い合わせ")
            } footer: {
                Text("不具合の報告時は、設定の「診断ログを書き出す」で作成したファイルを添付すると調査しやすくなります。")
            }

            Section("アプリ情報") {
                LabeledContent("アプリ", value: "BodyMode")
                LabeledContent("バージョン", value: LegalConfiguration.appVersion)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("サポート")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("supportInformationView")
    }
}

enum BodyModeLegalDocument {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: "利用規約"
        case .privacy: "プライバシーポリシー"
        }
    }

    var effectiveDate: String {
        "2026年7月27日"
    }

    var summary: String {
        switch self {
        case .terms:
            "この利用規約は、BodyModeの利用条件を定めるものです。アプリを利用する前に内容をご確認ください。"
        case .privacy:
            "BodyModeは、健康・トレーニングに関する情報をユーザー自身が管理できることを重視します。このポリシーでは、データの保存場所と利用方法を説明します。"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .terms: "termsOfUseView"
        case .privacy: "privacyPolicyView"
        }
    }

    var publishedURL: URL? {
        switch self {
        case .terms: LegalConfiguration.termsURL
        case .privacy: LegalConfiguration.privacyPolicyURL
        }
    }

    var sections: [LegalSection] {
        switch self {
        case .terms: Self.termsSections
        case .privacy: Self.privacySections
        }
    }

    private static let termsSections: [LegalSection] = [
        .init(
            title: "1. 適用",
            body: "本規約は、BodyModeのアプリ、Apple Watch機能、Widgetおよび関連機能の利用に適用されます。ユーザーは本規約に同意したうえで本サービスを利用します。"
        ),
        .init(
            title: "2. 提供する機能",
            body: "本サービスは、身体測定、食事、写真、トレーニング、活動、睡眠、コンディションなどの記録・表示・分析を支援します。機能の内容は、品質改善や法令・プラットフォーム要件への対応のため変更される場合があります。"
        ),
        .init(
            title: "3. 健康・医療上の注意",
            body: "本サービスは医療機器ではなく、診断、治療、疾病予防または緊急対応を行いません。表示される数値、分析、アラートは参考情報です。健康上の懸念がある場合は医療専門家へ相談してください。"
        ),
        .init(
            title: "4. AIによる出力",
            body: "AIによる食事量・栄養の推定、写真比較、トレーニング提案、コメントには誤りが含まれる可能性があります。ユーザーは出力を確認し、自身の判断で修正・利用するものとします。体脂肪率や健康状態を写真だけから断定するものではありません。"
        ),
        .init(
            title: "5. Apple Health・センサーデータ",
            body: "Apple HealthやApple Watchから取得するデータには測定誤差や欠損が生じる場合があります。これらを医療判断、緊急時の判断、危険を伴う運動の安全確認へ使用しないでください。"
        ),
        .init(
            title: "6. ユーザーの責任",
            body: "ユーザーは、自身の体調、経験、設備、周囲の安全を確認し、適切な範囲で本サービスを利用します。端末、Apple ID、ローカルAIサーバーおよび記録データの管理もユーザーの責任となります。"
        ),
        .init(
            title: "7. 禁止事項",
            body: "法令または公序良俗に反する行為、本サービスの解析・妨害・不正利用、第三者の権利侵害、虚偽情報による他者への危害、サービス運営に支障を与える行為を禁止します。"
        ),
        .init(
            title: "8. データの保存とバックアップ",
            body: "初期版の記録は主にユーザーの端末内へ保存されます。端末の故障、紛失、アプリ削除などに備え、必要な記録はデータ書き出し機能などを利用してユーザー自身で保全してください。"
        ),
        .init(
            title: "9. 外部サービス",
            body: "本サービスはApple Health、TestFlight、ユーザーが指定したAIサーバーなどの外部サービスと連携する場合があります。外部サービスには各提供者の利用条件とプライバシーポリシーが適用されます。"
        ),
        .init(
            title: "10. 知的財産",
            body: "本サービスに関するプログラム、デザイン、文章、商標その他の権利は、権利者に帰属します。ユーザーが記録した文章や写真の権利はユーザーに留保されます。"
        ),
        .init(
            title: "11. 利用停止",
            body: "安全性、保守、法令対応、不可抗力その他やむを得ない事情により、本サービスの全部または一部を変更・停止する場合があります。"
        ),
        .init(
            title: "12. 保証と責任の範囲",
            body: "本サービスは、特定の減量、筋肥大、健康改善、競技成績その他の結果を保証しません。法令で認められる範囲において、本サービスの利用または利用不能から生じた間接的・特別な損害について責任を負いません。"
        ),
        .init(
            title: "13. 規約の変更",
            body: "機能追加、法令変更その他の必要に応じて本規約を変更する場合があります。重要な変更は、アプリ内または公開ページで告知します。"
        ),
        .init(
            title: "14. 準拠法・管轄",
            body: "本規約は日本法を準拠法とします。本サービスに関する紛争は、法令上認められる範囲で、運営者の所在地を管轄する日本の裁判所を第一審の専属的合意管轄裁判所とします。"
        )
    ]

    private static let privacySections: [LegalSection] = [
        .init(
            title: "1. 取得・保存する情報",
            body: "ユーザーが入力または許可した場合に、プロフィール、目的、身体測定、食事、体型写真、トレーニング、睡眠、活動、コンディション、ジム訪問、設定を扱います。初期版ではアプリ内アカウントを作成しません。"
        ),
        .init(
            title: "2. 利用目的",
            body: "記録の保存・表示、目標との差分表示、グラフ・レポート作成、Apple Watchとの同期、選択されたAI分析、品質改善、不具合調査のために利用します。健康情報を広告の選定には利用しません。"
        ),
        .init(
            title: "3. 端末内保存",
            body: "BodyModeの記録と設定は、原則としてiPhoneまたはApple Watch内へ保存されます。端末のバックアップ設定によっては、Appleが提供するバックアップへ含まれる場合があります。"
        ),
        .init(
            title: "4. Apple Health",
            body: "ユーザーの許可に基づき、歩数、活動量、睡眠、心拍、消費エネルギー、ワークアウト、身体測定などを読み書きします。HealthKitデータを広告、データ販売、信用判断には使用しません。権限はiPhoneの設定またはヘルスケアアプリから変更できます。"
        ),
        .init(
            title: "5. 写真",
            body: "食事や体型の写真は、ユーザーが選択した場合だけ利用します。写真は記録表示と、明示的に実行したAI分析のために使用します。写真だけから健康状態や体脂肪率を断定しません。"
        ),
        .init(
            title: "6. 位置情報・モーション",
            body: "ユーザーが機能を有効にした場合、ジム訪問の記録やApple Watchでの動作回数・テンポ推定に使用します。これらの情報を広告の選定には使用しません。"
        ),
        .init(
            title: "7. ローカルAI",
            body: "AI機能は初期状態では無効です。ユーザーが有効にし、接続先と共有カテゴリを設定した場合だけ、選択されたデータをユーザー指定のAIサーバーへ送信します。送信前に共有カテゴリを変更でき、AIを使わなくても手動記録を利用できます。接続先サーバーでの保存・処理は、そのサーバーの管理者が定める条件に従います。"
        ),
        .init(
            title: "8. 診断情報",
            body: "アプリは端末内に動作ログとAppleのMetricKitが提供する診断情報を保存する場合があります。これらは自動送信されません。ユーザーが診断ログを書き出し、問い合わせへ添付した場合に限り、提供された範囲で不具合調査に使用します。"
        ),
        .init(
            title: "9. 広告・追跡",
            body: "現在のTestFlight版は広告SDKを組み込まず、クロスアプリ追跡を行いません。将来広告を導入する場合は、利用する事業者、送信データ、同意方法を本ポリシーとApp Storeのプライバシー表示へ追記してから有効にします。HealthKitや体型・食事などの機微な情報を広告ターゲティングへ使用しません。"
        ),
        .init(
            title: "10. 第三者提供",
            body: "法令に基づく場合を除き、ユーザーの情報を第三者へ販売しません。ユーザーが明示的に選択したAI接続、AppleのOS機能、共有操作など、機能提供に必要な場合のみ情報が移動します。"
        ),
        .init(
            title: "11. 保持・削除・書き出し",
            body: "端末内データは、ユーザーが個別削除、全データ削除、またはアプリ削除を行うまで保持されます。設定画面から全記録をJSONで書き出し、全データを削除できます。Apple Healthに保存された情報は、ヘルスケアアプリ側でも管理してください。"
        ),
        .init(
            title: "12. 安全管理",
            body: "不要な外部送信を避け、権限を機能ごとに求め、AIへ送るデータをユーザーが選べるようにします。ユーザーは端末のパスコード、Apple ID、AIサーバーの認証情報を適切に管理してください。"
        ),
        .init(
            title: "13. 子どもの利用",
            body: "年齢や健康状態に応じて、保護者または専門家の助言のもとで利用してください。本サービスは子どもを対象とした広告プロファイリングを行いません。"
        ),
        .init(
            title: "14. 変更・問い合わせ",
            body: "機能や取扱情報の変更に応じて本ポリシーを更新します。重要な変更はアプリ内または公開ページで告知します。問い合わせ方法は設定画面の「サポート」に表示します。"
        )
    ]
}

struct LegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

enum LegalConfiguration {
    static var termsURL: URL? {
        configuredURL(for: "BodyModeTermsURL")
    }

    static var privacyPolicyURL: URL? {
        configuredURL(for: "BodyModePrivacyPolicyURL")
    }

    static var supportURL: URL? {
        configuredURL(for: "BodyModeSupportURL")
    }

    static var supportEmail: String? {
        configuredString(for: "BodyModeSupportEmail")
    }

    static var appVersion: String {
        let version = configuredString(for: "CFBundleShortVersionString") ?? "0.0"
        let build = configuredString(for: "CFBundleVersion") ?? "0"
        return "\(version) (\(build))"
    }

    private static func configuredURL(for key: String) -> URL? {
        guard let value = configuredString(for: key),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            return nil
        }
        return url
    }

    private static func configuredString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

