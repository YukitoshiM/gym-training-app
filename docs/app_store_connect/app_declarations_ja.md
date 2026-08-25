# BodyMode App Store共通申告 回答案

更新日: 2026-08-24
対象: 初回一般公開候補

App Store Connectへ入力するための回答表。Appleの質問文が変更された場合は、画面上の最新文言を優先する。

## 1. 年齢レーティング

### アプリ内コントロール

| 質問 | 回答 | 根拠 |
|---|---|---|
| Parental Controls | なし | 保護者向け制御機能はない |
| Age Assurance | なし | 年齢確認・年齢推定・Declared Age Range APIは使わない |

### 機能

| 質問 | 回答 | 根拠 |
|---|---|---|
| Unrestricted Web Access | なし | アプリ内で自由にWeb閲覧できない。法務・サポートは限定URLを開くだけ |
| User-Generated Content | なし | ユーザー投稿を他ユーザーへ配信しない |
| Messaging and Chat | なし | AIとの会話だけで、ユーザー同士の通信はない |
| Social Media | なし | フィード、フォロー、コメント、公開投稿はない |
| Social Media Disabled for Users Under 13 | なし | Social Media自体がない |
| Advertising | あり | Google AdMobのバナー広告を表示する |

### Medical or Wellness

| 質問 | 回答 | 根拠 |
|---|---|---|
| Health or Wellness Topics | あり | カロリー、食事、運動、睡眠、回復、トレーニングの生活習慣提案を扱う |
| Medical or Treatment Information | なし | 診断、疾病管理、服薬、治療、救急医療の助言を提供しない。AIにも禁止する |

### その他の内容

次はすべて`なし`または`No`とする。

- Profanity or Crude Humor
- Horror or Fear Themes
- Alcohol, Tobacco, or Drug Use or References
- Mature or Suggestive Themes
- Sexual Content or Nudity
- Graphic Sexual Content and Nudity
- Cartoon or Fantasy Violence
- Realistic Violence
- Prolonged Graphic or Sadistic Realistic Violence
- Guns or Other Weapons
- Simulated Gambling
- Gambling
- Contests
- Loot Boxes

### 年齢カテゴリ

- Made for Kids: `いいえ`
- Age Categories and Override: `Not Applicable`
- App Store Connect算出レーティング: `4+`（必須24項目回答済み）
- 地域別レーティングはAppleの自動算出結果を採用する

## 2. 規制対象医療機器

| 質問 | 回答 |
|---|---|
| いずれかの国・地域で規制対象医療機器か | `いいえ` |

理由:

- 診断、予防、監視、治療を目的としない。
- FDA承認・登録、CEマーク、UKCAマーク、MDR自己認証の対象製品として提供しない。
- AI推定、写真コメント、コンディション表示は参考情報であることをアプリと法務文書に表示する。

## 3. 輸出コンプライアンス

| 項目 | 回答 |
|---|---|
| 独自・非標準暗号を実装するか | `いいえ` |
| 非免除暗号を使用するか | `いいえ` |
| 輸出書類 | 不要の想定 |

App PrivacyではDevice IDのTrackingを`はい`として申告する。Build 31から広告SDK起動前にATTを要求し、許可された場合に限って広告事業者がIDFAを頻度制御と広告効果測定へ利用できる。拒否時もアプリ機能を制限せず、広告は非パーソナライズへ固定する。App Store Connectに`Uses IDFA`確認項目が表示される場合は`true`としてBuild 31の実装と一致させる。

`Info.plist`には`ITSAppUsesNonExemptEncryption = false`を設定済み。HTTPS、KeychainなどApple OSまたは標準ライブラリが提供する免除対象の暗号化だけを使用する。

## 4. Digital Services Act

初回正式版ではEU27か国を配信対象外とする。個人開発者の住所・電話番号・メールアドレスをApp Store商品ページへ公開せず、専用の事業者連絡先を用意できる収益段階までEU配信を保留する。

App Store Connectでは次を保存済み。

- 回答: `DSAに基づくトレーダーではありません、またはEU内で配信する予定はありません`
- 公開連絡先: 登録不要
- 状態: `すべての規制要件を満たしています`、DSA `有効`

EUを追加する前には、法的なTrader区分を再評価し、必要な場合は専用住所・電話・メールの検証を完了してから配信地域を変更する。

## 5. コンテンツ権利

| 質問 | 回答 |
|---|---|
| 第三者コンテンツを含む、表示する、またはアクセスするか | `はい` |
| 必要な権利または許可を保有しているか | `はい` |

対象:

- Google AdMobの広告素材
- Apple Health、SF Symbols等のApple提供機能・素材
- 文部科学省食品成分表に基づく食品情報
- Europe PMC、Crossref、PubMed等の文献メタデータと出典リンク
- アプリ用に生成・制作したコーチ画像と画面素材

広告、Apple素材、データベース、文献メタデータは各提供条件の範囲で使用し、論文本文や第三者画像を無断再配布しない。出典と第三者通知はアプリ内または`third_party_notices.md`で維持する。

## 6. 配信地域

- App Store価格は無料、基準地域は米国として設定済み。
- App Store Connect上はEU27か国を除く148地域を有効化済み。
- EU27か国が配信不可であることをAPIとApp Store Connect画面で確認済み。
- AIクレジット商品は作成済みの地域設定を維持するが、親アプリがEUで配信されないためEUのStorefrontでは購入導線が成立しない。EU再開時はIAPを含めてDSA対応を再確認する。
- 既存設定では今後追加される新地域の自動有効化はオンだが、現在のEU27除外には影響しない。新地域追加時は法務要件を監査する。
- 地域ごとに追加許可・届出が必要な場合は、Appleの公開可否判定と現地要件に従う。

## 7. Connectへ入力する前の残件

- [x] Account HolderがApple Developer Programの更新契約へ同意する
- [ ] 法人情報を再確認・保存し、Paid Apps Agreement、税務、銀行情報を完了する（法人情報とPaid Apps Agreementは完了、税務・銀行が残件）
- [x] EU27を除外し、Account HolderがDSA非トレーダー区分を保存する
- [x] App PrivacyのAdMob Device IDはTrackingありで申告すると確定する
- [ ] Build 31の最終ArchiveでATT利用目的、4 Privacy Manifest、7データ種類、3 Required-Reason APIを確認する
- [x] App Store Connectの最新質問票と本書を再照合する
- [x] 年齢、輸出、コンテンツ権利、価格、配信地域をAPIで保存・再取得する
- [x] App PrivacyをApp Store Connectへ下書き保存し、13データ種類の未回答がないことを確認する
- [x] 最終Archive確認後にApp Privacyを公開する
- [x] 規制対象医療機器を`いいえ`として保存する
- [x] DSAをApp Store Connect画面で保存し、規制要件が有効であることを確認する
- [x] Build 30とAIクレジット3商品を同じ審査提出物へ追加する
- [x] 4項目をまとめてApp Reviewへ提出する（2026-08-24 0:01 JST、`WAITING_FOR_REVIEW`）

## 8. 公式資料

- 年齢レーティング: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
- 規制対象医療機器: https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status
- 輸出コンプライアンス: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- DSA: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- App情報とコンテンツ権利: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
