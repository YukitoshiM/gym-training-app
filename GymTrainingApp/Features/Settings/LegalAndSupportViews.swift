import SwiftUI

struct ReleaseConsentView: View {
    let onAccept: () -> Void

    @State private var hasConfirmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "figure.mind.and.body")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)

                        Text(LegalCopy.text(ja: "BodyModeを始める", en: "Get started with BodyMode"))
                            .font(.largeTitle.bold())

                        Text(LegalCopy.text(ja: "大切な点だけ確認してください。", en: "Please review these important points."))
                            .font(.title3)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        consentPoint(
                            icon: "iphone",
                            title: LegalCopy.text(ja: "記録は端末内", en: "Records stay on your device"),
                            detail: LegalCopy.text(ja: "健康記録は広告へ送りません", en: "Health records are not sent for advertising")
                        )
                        consentPoint(
                            icon: "cross.case",
                            title: LegalCopy.text(ja: "医療診断ではありません", en: "Not a medical diagnosis"),
                            detail: LegalCopy.text(ja: "体調に不安があれば専門家へ", en: "Consult a professional if you have health concerns")
                        )
                        consentPoint(
                            icon: "hand.raised",
                            title: LegalCopy.text(ja: "利用分析は任意", en: "Usage analytics are optional"),
                            detail: LegalCopy.text(ja: "設定からいつでも変更・削除", en: "Change or delete them anytime in Settings")
                        )
                        consentPoint(
                            icon: "bubble.left.and.bubble.right",
                            title: LegalCopy.text(ja: "AI送信は操作した時だけ", en: "AI data is sent only when requested"),
                            detail: LegalCopy.text(ja: "記憶候補も確認後に保存", en: "Suggested memories are saved only after confirmation")
                        )
                        consentPoint(
                            icon: "rectangle.badge.person.crop",
                            title: LegalCopy.text(ja: "広告は別管理", en: "Ads are handled separately"),
                            detail: LegalCopy.text(ja: "パーソナライズせず、同意後に表示", en: "Non-personalized ads appear only after consent")
                        )
                    }

                    HStack(spacing: 24) {
                        NavigationLink(LegalCopy.text(ja: "利用規約", en: "Terms of Use")) {
                            LegalDocumentView(document: .terms)
                        }
                        .accessibilityIdentifier("consentTermsLink")

                        NavigationLink(LegalCopy.text(ja: "プライバシー", en: "Privacy")) {
                            LegalDocumentView(document: .privacy)
                        }
                        .accessibilityIdentifier("consentPrivacyLink")
                    }
                    .font(.headline)

                    Toggle(LegalCopy.text(ja: "内容を確認し、同意します", en: "I have reviewed and agree"), isOn: $hasConfirmed)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("legalConsentToggle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAccept()
                } label: {
                    Label(LegalCopy.text(ja: "同意して始める", en: "Agree and continue"), systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasConfirmed)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityIdentifier("acceptLegalConsentButton")
            }
            .background(AppTheme.pageBackground)
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("legalConsentView")
    }

    private func consentPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

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

            NavigationLink {
                InAppFeedbackView()
            } label: {
                Label("フィードバック", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
            .accessibilityIdentifier("inAppFeedbackLink")

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
                        .font(.footnote)
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
                NavigationLink {
                    InAppFeedbackView()
                } label: {
                    Label("アプリから送る", systemImage: "paperplane")
                }
                .accessibilityIdentifier("supportFeedbackLink")
            }

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
        case .terms: LegalCopy.text(ja: "利用規約", en: "Terms of Use")
        case .privacy: LegalCopy.text(ja: "プライバシーポリシー", en: "Privacy Policy")
        }
    }

    var effectiveDate: String {
        switch self {
        case .terms: "2026年8月13日"
        case .privacy: "2026年8月16日"
        }
    }

    var summary: String {
        switch self {
        case .terms:
            LegalCopy.text(
                ja: "この利用規約は、BodyModeの利用条件を定めるものです。アプリを利用する前に内容をご確認ください。",
                en: "These Terms describe the conditions for using BodyMode. Please review them before using the app."
            )
        case .privacy:
            LegalCopy.text(
                ja: "BodyModeは、健康・トレーニングに関する情報をユーザー自身が管理できることを重視します。このポリシーでは、データの保存場所と利用方法を説明します。",
                en: "BodyMode is designed to keep you in control of your health and training information. This policy explains where data is stored and how it is used."
            )
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

    private static var termsSections: [LegalSection] { [
        .init(
            title: LegalCopy.text(ja: "1. 適用", en: "1. Scope"),
            body: LegalCopy.text(ja: "本規約は、BodyModeのアプリ、Apple Watch機能、Widgetおよび関連機能の利用に適用されます。ユーザーは本規約に同意したうえで本サービスを利用します。", en: "These Terms apply to the BodyMode app, Apple Watch features, widgets, and related features. You may use the service after agreeing to these Terms.")
        ),
        .init(
            title: LegalCopy.text(ja: "2. 提供する機能", en: "2. Features"),
            body: LegalCopy.text(ja: "本サービスは、身体測定、食事、写真、トレーニング、活動、睡眠、コンディションなどの記録・表示・分析を支援します。機能の内容は、品質改善や法令・プラットフォーム要件への対応のため変更される場合があります。", en: "The service helps record, display, and analyze body measurements, meals, photos, workouts, activity, sleep, and condition. Features may change to improve quality or meet legal and platform requirements.")
        ),
        .init(
            title: LegalCopy.text(ja: "3. 健康・医療上の注意", en: "3. Health and medical notice"),
            body: LegalCopy.text(ja: "本サービスは医療機器ではなく、診断、治療、疾病予防または緊急対応を行いません。表示される数値、分析、アラートは参考情報です。健康上の懸念がある場合は医療専門家へ相談してください。", en: "The service is not a medical device and does not provide diagnosis, treatment, disease prevention, or emergency response. Values, analyses, and alerts are informational only. Consult a medical professional if you have health concerns.")
        ),
        .init(
            title: LegalCopy.text(ja: "4. AIによる出力", en: "4. AI output"),
            body: LegalCopy.text(ja: "AIによる食事量・栄養の推定、写真比較、トレーニング提案、会話、週次・月次コメントには誤りが含まれる可能性があります。食品成分表の値も標準的な参考値であり、個々の商品や調理状態と一致するとは限りません。ユーザーは出力、月次目標案、記憶候補を確認し、自身の判断で修正・利用するものとします。体脂肪率や健康状態を写真だけから断定するものではありません。", en: "AI estimates, photo comparisons, workout suggestions, conversations, and weekly or monthly comments may contain errors. Food composition values are standard references and may not match a specific product or preparation. Review and adjust outputs, proposed goals, and memory suggestions using your own judgment. Photos alone are not used to make definitive claims about body-fat percentage or health.")
        ),
        .init(
            title: LegalCopy.text(ja: "5. Apple Health・センサーデータ", en: "5. Apple Health and sensor data"),
            body: LegalCopy.text(ja: "Apple HealthやApple Watchから取得するデータには測定誤差や欠損が生じる場合があります。これらを医療判断、緊急時の判断、危険を伴う運動の安全確認へ使用しないでください。", en: "Data from Apple Health and Apple Watch may contain measurement errors or gaps. Do not use it for medical decisions, emergencies, or safety checks for hazardous exercise.")
        ),
        .init(
            title: LegalCopy.text(ja: "6. ユーザーの責任", en: "6. Your responsibilities"),
            body: LegalCopy.text(ja: "ユーザーは、自身の体調、経験、設備、周囲の安全を確認し、適切な範囲で本サービスを利用します。端末、Apple ID、AIサーバーおよび記録データの管理もユーザーの責任となります。", en: "Use the service within an appropriate range after considering your condition, experience, equipment, and surroundings. You are also responsible for managing your device, Apple ID, AI server, and recorded data.")
        ),
        .init(
            title: LegalCopy.text(ja: "7. 禁止事項", en: "7. Prohibited conduct"),
            body: LegalCopy.text(ja: "法令または公序良俗に反する行為、本サービスの解析・妨害・不正利用、第三者の権利侵害、虚偽情報による他者への危害、サービス運営に支障を与える行為を禁止します。", en: "You must not violate laws or public order, analyze or interfere with the service, misuse it, infringe third-party rights, harm others through false information, or disrupt service operation.")
        ),
        .init(
            title: LegalCopy.text(ja: "8. データの保存とバックアップ", en: "8. Storage and backup"),
            body: LegalCopy.text(ja: "初期版の記録は主にユーザーの端末内へ保存されます。端末の故障、紛失、アプリ削除などに備え、必要な記録はデータ書き出し機能などを利用してユーザー自身で保全してください。", en: "Records are primarily stored on your device. Use data export or another method to retain important records in case of device failure, loss, or app deletion.")
        ),
        .init(
            title: LegalCopy.text(ja: "9. 外部サービス", en: "9. External services"),
            body: LegalCopy.text(ja: "本サービスはApple Health、App Store、Cloudflare、OpenAI API、Google AdMobなどの外部サービスと連携します。外部サービスには各提供者の利用条件とプライバシーポリシーが適用されます。", en: "BodyMode works with external services including Apple Health, the App Store, Cloudflare, the OpenAI API, and Google AdMob. Each provider's terms and privacy policy apply to its service.")
        ),
        .init(
            title: LegalCopy.text(ja: "10. 広告", en: "10. Advertising"),
            body: LegalCopy.text(ja: "iPhoneアプリに非パーソナライズ広告を表示します。任意の動画広告は、表示前に示したAIクレジットを視聴完了後に付与します。視聴を拒否または中断しても手動記録などの無料機能は利用できます。広告の内容とリンク先は第三者が提供するものであり、BodyModeが商品・サービスを保証するものではありません。", en: "The iPhone app displays non-personalized ads. Optional rewarded videos grant the stated AI credits only after completion. Declining or stopping a video does not prevent use of free features such as manual records. Ad content and destinations are provided by third parties, and BodyMode does not guarantee advertised products or services.")
        ),
        .init(
            title: LegalCopy.text(ja: "11. AIクレジットと購入", en: "11. AI credits and purchases"),
            body: LegalCopy.text(ja: "AI機能は機能ごとに表示されたクレジットを消費します。App Storeで購入するクレジットは消耗型のデジタル商品で、有効期限はありませんが、譲渡・換金・他サービスへの交換はできません。購入の成否、保留、返金はAppleの処理に従います。返金された購入の未使用クレジットは残高から除き、使用済み分で残高を負数にはせず、将来の購入付与から調整します。アカウント削除時は未使用の購入分・特典分を含む残高を削除し、復元できません。重複特典と購入返金の防止に必要な取引記録は保持します。", en: "AI features consume the number of credits shown for each action. Credits purchased through the App Store are consumable digital goods. They do not expire, but cannot be transferred, redeemed for cash, or exchanged for another service. Apple controls purchase completion, pending status, and refunds. Unused credits from a refunded purchase are removed. Credits already used do not create a negative balance; the adjustment is applied to future purchased-credit grants. Deleting your account deletes all unused purchased and promotional credits, and they cannot be restored. Minimal transaction records needed to prevent duplicate bonuses and reconcile refunds are retained.")
        ),
        .init(
            title: LegalCopy.text(ja: "12. 知的財産", en: "12. Intellectual property"),
            body: LegalCopy.text(ja: "本サービスに関するプログラム、デザイン、文章、商標その他の権利は、権利者に帰属します。ユーザーが記録した文章や写真の権利はユーザーに留保されます。", en: "Rights in the service's software, design, text, trademarks, and other materials belong to their respective owners. You retain rights in text and photos you record.")
        ),
        .init(
            title: LegalCopy.text(ja: "13. 利用停止", en: "13. Changes or suspension"),
            body: LegalCopy.text(ja: "安全性、保守、法令対応、不可抗力その他やむを得ない事情により、本サービスの全部または一部を変更・停止する場合があります。", en: "All or part of the service may be changed or suspended for safety, maintenance, legal compliance, force majeure, or other unavoidable reasons.")
        ),
        .init(
            title: LegalCopy.text(ja: "14. 保証と責任の範囲", en: "14. Warranty and liability"),
            body: LegalCopy.text(ja: "本サービスは、特定の減量、筋肥大、健康改善、競技成績その他の結果を保証しません。法令で認められる範囲において、本サービスの利用または利用不能から生じた間接的・特別な損害について責任を負いません。", en: "The service does not guarantee weight loss, muscle growth, health improvement, athletic performance, or any other result. To the extent permitted by law, we are not liable for indirect or special damages arising from use or inability to use the service.")
        ),
        .init(
            title: LegalCopy.text(ja: "15. 規約の変更", en: "15. Changes to these Terms"),
            body: LegalCopy.text(ja: "機能追加、法令変更その他の必要に応じて本規約を変更する場合があります。重要な変更は、アプリ内または公開ページで告知します。", en: "These Terms may be updated for new features, legal changes, or other needs. Material changes will be announced in the app or on a published page.")
        ),
        .init(
            title: LegalCopy.text(ja: "16. 準拠法・管轄", en: "16. Governing law and jurisdiction"),
            body: LegalCopy.text(ja: "本規約は日本法を準拠法とします。本サービスに関する紛争は、法令上認められる範囲で、運営者の所在地を管轄する日本の裁判所を第一審の専属的合意管轄裁判所とします。", en: "These Terms are governed by Japanese law. To the extent permitted by law, disputes concerning the service are subject to the exclusive jurisdiction of the Japanese court with jurisdiction over the operator's location as the court of first instance.")
        )
    ] }

    private static var privacySections: [LegalSection] { [
        .init(
            title: LegalCopy.text(ja: "1. 取得・保存する情報", en: "1. Information handled"),
            body: LegalCopy.text(ja: "ユーザーが入力または許可した場合に、プロフィール、目的、身体測定、食事、体型写真、トレーニング、睡眠、活動、コンディション、ジム訪問、設定を扱います。AI利用時はSign in with AppleでBodyModeアカウントを作成し、Appleが提供する識別子から生成した仮名ID、AIクレジット残高、取得・消費台帳、購入トランザクションIDをサーバーに保存します。氏名やApple IDのメールアドレスはAIクレジット管理に保存しません。", en: "When you enter or authorize them, BodyMode handles profile details, goals, body measurements, meals, progress photos, workouts, sleep, activity, condition, gym visits, and settings. When you use AI, Sign in with Apple creates a BodyMode account. The server stores a pseudonymous ID derived from Apple's identifier, AI credit balance, grant and usage ledger, and purchase transaction IDs. Your name and Apple ID email address are not stored for AI credit management.")
        ),
        .init(
            title: LegalCopy.text(ja: "2. 利用目的", en: "2. Purposes"),
            body: LegalCopy.text(ja: "記録の保存・表示、目標との差分表示、グラフ・レポート作成、Apple Watchとの同期、選択されたAI分析、品質改善、不具合調査のために利用します。健康情報を広告の選定には利用しません。", en: "Information is used to save and display records, compare them with goals, create charts and reports, sync with Apple Watch, perform selected AI analyses, improve quality, and investigate problems. Health information is not used to select ads.")
        ),
        .init(
            title: LegalCopy.text(ja: "3. 端末内保存", en: "3. On-device storage"),
            body: LegalCopy.text(ja: "BodyModeの記録、設定、バーコード商品辞書、日次提案の完了・スキップ傾向は、原則としてiPhoneまたはApple Watch内へ保存されます。行動傾向の利用は設定から停止・リセットできます。iPhone内の記録ファイルには端末ロックと連動するファイル保護を適用し、BodyModeの記録用フォルダは端末バックアップの対象外にしています。必要な記録は設定画面から書き出して保管してください。", en: "BodyMode records, settings, the barcode product dictionary, and patterns of completing or skipping daily recommendations are generally stored on your iPhone or Apple Watch. You can stop or reset behavioral learning in Settings. Record files use protection tied to the device lock, and BodyMode's record folder is excluded from device backups. Export important records from Settings for safekeeping.")
        ),
        .init(
            title: "4. Apple Health",
            body: LegalCopy.text(ja: "ユーザーの許可に基づき、歩数、活動量、睡眠、心拍、消費エネルギー、ワークアウト、身体測定などを読み書きします。HealthKitデータを広告、データ販売、信用判断には使用しません。権限はiPhoneの設定またはヘルスケアアプリから変更できます。", en: "With your permission, BodyMode reads or writes steps, activity, sleep, heart rate, active energy, workouts, body measurements, and related data. HealthKit data is not used for advertising, data sales, or credit decisions. Permissions can be changed in iPhone Settings or the Health app.")
        ),
        .init(
            title: LegalCopy.text(ja: "5. 写真", en: "5. Photos"),
            body: LegalCopy.text(ja: "食事や体型の写真は、ユーザーが選択した場合だけ利用します。写真は記録表示と、明示的に実行したAI分析のために使用します。写真だけから健康状態や体脂肪率を断定しません。", en: "Meal and progress photos are used only when you select them. They are used to display records and for AI analysis you explicitly request. Photos alone are not used to make definitive claims about health or body-fat percentage.")
        ),
        .init(
            title: LegalCopy.text(ja: "6. 位置情報・モーション", en: "6. Location and motion"),
            body: LegalCopy.text(ja: "ユーザーが機能を有効にした場合、ジム訪問の記録やApple Watchでの動作回数・テンポ推定に使用します。これらの情報を広告の選定には使用しません。", en: "When enabled, location and motion are used to record gym visits and estimate repetitions or tempo on Apple Watch. This information is not used to select ads.")
        ),
        .init(
            title: LegalCopy.text(ja: "7. AIサーバー", en: "7. AI server"),
            body: LegalCopy.text(ja: "選択したデータは、AI操作を開始した場合、または予約レポートでAIクレジットの自動利用を明示的に有効にした場合だけ送信します。本番AIリクエストはCloudflare Workersを経由してOpenAI APIへ送信されます。BodyModeはResponses APIへstore: falseを指定し、D1データベースや運用ログへ入力文、AI回答、写真、身体・健康値を保存しません。OpenAIはAPI入出力を既定ではモデル学習に使用しませんが、不正利用監視のため入力、出力、画像を含み得るログを通常最大30日保持する場合があります。記憶候補は自動保存しません。", en: "Selected data is sent only when you start an AI action or explicitly enable scheduled reports with automatic AI-credit use. Production AI requests pass through Cloudflare Workers to the OpenAI API. BodyMode sets store: false on Responses API requests and does not store prompts, AI responses, photos, or body and health values in D1 or operational logs. OpenAI does not use API inputs or outputs for model training by default, but may retain abuse-monitoring logs that can include inputs, outputs, and images for up to 30 days. Memory suggestions are not saved automatically.")
        ),
        .init(
            title: LegalCopy.text(ja: "8. 診断情報", en: "8. Diagnostics"),
            body: LegalCopy.text(ja: "アプリは端末内に動作ログとAppleのMetricKit診断情報を保存する場合があります。Watchは最大14日または500件、iPhoneは最大14日、1,000件、2MiBまで保持し、自動送信しません。ユーザーが書き出した場合だけ不具合調査に利用します。サーバーは認証、クレジット管理、障害調査のため、仮名アカウントID、ランダムなリクエストID、機能、モデル、処理結果、トークン数、処理時間、エラー分類を保存します。会話本文、写真、身体・健康値、APIキー、アクセストークンは保存しません。アカウント削除により稼働中データベースの本人データを削除し、日次バックアップ内の削除前データは最大14日で失効します。", en: "The app may store operational logs and Apple MetricKit diagnostics on-device. Watch retains up to 14 days or 500 entries; iPhone retains up to 14 days, 1,000 entries, or 2 MiB. They are not sent automatically and are used for support only when you export them. For authentication, credit management, and incident investigation, the server stores a pseudonymous account ID, random request ID, feature, model, result, token counts, duration, and error category. It does not store conversation text, photos, health values, API keys, or access tokens. Account deletion removes your data from the live database; deleted data expires from daily backups within 14 days.")
        ),
        .init(
            title: LegalCopy.text(ja: "9. 利用分析", en: "9. Usage analytics"),
            body: LegalCopy.text(ja: "利用分析は初期状態では無効です。ユーザーが有効にした場合、画面の選択、記録保存、日次提案、通知の開封、AI登録、残高不足表示、クレジット画面、報酬広告と購入の結果などの固定イベントを、日時、アプリ版、言語、配布チャネルとともに、氏名やメールと結び付けない仮名化されたインストール単位で運営サーバーへ送信し、最大90日保持します。購入額、身体値、食事の数値・内容、写真、種目名・重量・回数、心拍値、睡眠時間、位置情報、自由記述、AI本文、氏名、メール、広告IDは含めません。設定画面から端末内データの書き出し、端末内・サーバー上の削除、無効化ができます。", en: "Usage analytics are off by default. If enabled, BodyMode sends fixed events for screen choices, saved records, daily recommendations, notification opens, AI registration, insufficient-credit displays, credit screens, rewarded-ad outcomes, and purchase outcomes, together with time, app version, language, and distribution channel under a pseudonymous installation identifier not tied to your name or email. Data is retained for up to 90 days. Purchase amount, body measurements, meal values or content, photos, exercise names, weights, repetitions, heart-rate values, sleep duration, location, free text, AI text, name, email, and advertising ID are excluded. You can export, disable, and delete on-device and server analytics in Settings.")
        ),
        .init(
            title: LegalCopy.text(ja: "10. 広告・追跡", en: "10. Advertising and tracking"),
            body: LegalCopy.text(ja: "iPhone版はGoogle AdMob SDKでバナー広告と、ユーザーが選択した場合だけ報酬動画広告を表示します。広告は非パーソナライズに固定しています。広告SDKの起動前にApp Tracking Transparencyで許可を求め、許可された場合に限り広告識別子を広告の頻度制御と効果測定に使用します。拒否しても機能は制限されません。広告の表示・完了情報と一意な報酬取引IDは、重複付与防止とAIクレジット付与に使用します。HealthKit、身体値、心拍、睡眠、食事、写真、トレーニング、目標、GPS・ジム位置を広告選定へ使用・送信しません。", en: "The iPhone app uses Google AdMob for banner ads and rewarded video ads only when you choose to watch one. Ads are always requested as non-personalized. Before the advertising SDK starts, BodyMode requests permission through App Tracking Transparency. If permission is granted, the advertising identifier may be used only for ad frequency control and performance measurement. Declining does not restrict any app feature. Ad presentation and completion data and a unique reward transaction ID are used to prevent duplicate grants and add AI credits. HealthKit data, body values, heart rate, sleep, meals, photos, workouts, goals, GPS, and gym locations are not used or sent for ad selection.")
        ),
        .init(
            title: LegalCopy.text(ja: "11. 第三者提供", en: "11. Third parties"),
            body: LegalCopy.text(ja: "法令に基づく場合を除き、ユーザーの情報を第三者へ販売しません。機能提供に必要な範囲でApple、Cloudflare、OpenAI、Google AdMobへ情報が移動する場合があります。各社はそれぞれの規約とプライバシーポリシーに基づいて処理します。", en: "BodyMode does not sell user information, except that information may be disclosed when required by law. Information may be processed by Apple, Cloudflare, OpenAI, and Google AdMob only as needed for the features described here, subject to each provider's terms and privacy policy.")
        ),
        .init(
            title: LegalCopy.text(ja: "12. 保持・削除・書き出し", en: "12. Retention, deletion, and export"),
            body: LegalCopy.text(ja: "端末内記録は個別削除、全データ削除、またはアプリ削除まで保持されます。AIクレジット残高と台帳はアカウント削除までサーバーに保持され、アプリ削除だけでは消えません。設定の全データ削除はBodyModeアカウントも削除し、未使用の購入・特典クレジットは復元できません。OpenAIの不正利用監視ログに含まれる可能性があるAI入出力は、通常最大30日後に削除されます。", en: "On-device records remain until you delete an item, delete all data, or remove the app. AI credit balances and the ledger remain on the server until account deletion and are not removed merely by uninstalling the app. Delete All Data in Settings also deletes the BodyMode account; unused purchased and promotional credits cannot be restored. AI inputs and outputs that may be present in OpenAI abuse-monitoring logs are normally deleted within 30 days.")
        ),
        .init(
            title: LegalCopy.text(ja: "13. 安全管理", en: "13. Security"),
            body: LegalCopy.text(ja: "不要な外部送信を避け、権限を機能ごとに求め、AIへ送るデータをユーザーが選べるようにします。ユーザーは端末のパスコード、Apple ID、AIサーバーの認証情報を適切に管理してください。", en: "BodyMode avoids unnecessary external transmission, requests permissions by feature, and lets you choose data shared with AI. Protect your device passcode, Apple ID, and AI server credentials.")
        ),
        .init(
            title: LegalCopy.text(ja: "14. 子どもの利用", en: "14. Children's use"),
            body: LegalCopy.text(ja: "年齢や健康状態に応じて、保護者または専門家の助言のもとで利用してください。本サービスは子どもを対象とした広告プロファイリングを行いません。", en: "Depending on age and health, use BodyMode with guidance from a guardian or professional. The service does not perform advertising profiling directed at children.")
        ),
        .init(
            title: LegalCopy.text(ja: "15. 変更・問い合わせ", en: "15. Changes and contact"),
            body: LegalCopy.text(ja: "機能や取扱情報の変更に応じて本ポリシーを更新します。重要な変更はアプリ内または公開ページで告知します。問い合わせ方法は設定画面の「サポート」に表示します。", en: "This policy may be updated as features or data practices change. Material changes will be announced in the app or on a published page. Contact options are shown under Support in Settings.")
        )
    ] }
}

private enum LegalCopy {
    static func text(ja: String, en: String) -> String {
        AppLanguagePreference.usesJapanese ? ja : en
    }
}

struct LegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

enum LegalConfiguration {
    static let currentConsentVersion = "2026-08-24-att-v1"

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

enum LegalConsentStore {
    static let acceptedVersionKey = "bodymode.legal.acceptedVersion"

    static func acceptCurrent() {
        UserDefaults.standard.set(LegalConfiguration.currentConsentVersion, forKey: acceptedVersionKey)
        UsageAnalytics.shared.record(.legalAccepted)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: acceptedVersionKey)
    }
}
