# BodyMode App Privacy回答表

更新日: 2026-08-24
対象: AIクレジット導入後の次回公開候補 / Google Mobile Ads SDK 13.7.0 / UMP 3.1.0

App Store Connectへ転記するための作業表。最終Release ArchiveのPrivacy Reportと、AIサーバーの運用ログ保持を確認してから公開する。

## 1. 最初の回答

| 質問 | 回答案 | 根拠 |
|---|---|---|
| このAppまたは第三者パートナーはデータを収集しますか | はい | BodyModeのアカウント・課金・任意分析、Google Mobile Ads SDK、OpenAIの不正利用監視ログが対象 |
| トラッキング目的でデータを使用しますか | はい（Device IDのみ） | 同梱Google Mobile Ads SDKのPrivacy ManifestがDevice IDをTrackingありと宣言している。広告SDK起動前にATTを要求し、広告は許可状態にかかわらず非パーソナライズへ固定する |
| 収集データはユーザーに関連付けられますか | データ種類ごとに回答 | 概算位置、Device ID、広告データ、製品操作は「はい」。診断系はSDK Manifestに従い「いいえ」 |
| ユーザーアカウントを作成しますか | はい | 手動機能は登録不要。AI利用・クレジット購入時にSign in with Appleで仮名アカウントを作成し、アプリ内から削除できる |

## 2. App Store Connectで選択するデータ種類

Google Mobile Ads SDK 13.7.0とUMP 3.1.0に同梱されたPrivacy Manifestを読み取った結果。最終ArchiveのPrivacy Reportが同じであることを確認してから転記する。

| App Privacyのデータ種類 | 利用目的 | 関連付け | Tracking | 根拠 |
|---|---|---|---|---|
| おおよその位置情報 | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス、Appの機能 | はい | いいえ | AdMobはIPから推定、UMPは同意地域判定 |
| デバイスID | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス、Appの機能 | はい | はい | AdMob ManifestがTrackingあり。AI認証ではインストールIDのHMAC指紋を監査用に保持 |
| ユーザーID | Appの機能 | はい | いいえ | Appleが提供するsubjectをHMAC化したBodyMode内部IDでアカウント、AIクレジット、複数端末を管理。氏名・メールは保存しない |
| 購入履歴 | Appの機能 | はい | いいえ | App Storeの署名済みトランザクションID、商品ID、付与クレジットを重複付与防止と残高管理に保持 |
| 製品の操作 | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス、Appの機能 | はい | いいえ | 広告・同意画面の操作に加え、明示同意時にBodyModeが粗い機能利用イベントを収集する。AdMob側の関連付けありを優先 |
| 健康 | Appの機能、製品のパーソナライズ | いいえ | いいえ | AI実行時に身体測定、睡眠、心拍、食事・栄養要約をOpenAIへ送る場合があり、不正利用監視ログへ通常最大30日保持され得る |
| フィットネス | アナリティクス、Appの機能、製品のパーソナライズ | はい | いいえ | 任意分析の固定区分を仮名化インストール単位で集計するほか、AI実行時にトレーニング要約をOpenAIへ送る場合がある |
| 写真またはビデオ | Appの機能、製品のパーソナライズ | いいえ | いいえ | 食事・体型写真のAI解析を明示実行した場合にOpenAIへ送信し、不正利用監視ログへ通常最大30日保持され得る |
| その他のユーザーコンテンツ | Appの機能、製品のパーソナライズ | いいえ | いいえ | AIチャット本文、メモ、食事名などをOpenAIへ送る場合があり、不正利用監視ログへ通常最大30日保持され得る |
| 広告データ | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス | はい | いいえ | 表示広告等 |
| クラッシュデータ | アナリティクス | いいえ | いいえ | Google SDK Manifest |
| パフォーマンスデータ | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス、Appの機能 | いいえ | いいえ | AdMobとUMPの目的を合算 |
| その他の診断データ | 第三者広告、デベロッパの広告またはマーケティング、アナリティクス | いいえ | いいえ | Google SDK Manifest |

注意:

- 健康、身体、食事、写真、運動、睡眠、位置履歴を広告リクエストへ含めない。
- 本番AdMob App ID、Banner ID、Privacy & messaging、広告レーティングは設定済み。
- GoogleのSDK開示は更新されるため、公開候補ごとに確認する。
- GoogleのManifestではDevice IDだけTrackingが`true`である。非パーソナライズ広告は広告ターゲティングにモバイル広告IDを使わないが、頻度制御と集計レポートには使い得るため、「非パーソナライズ」と「Trackingなし」を同義に扱わない。
- `NSUserTrackingUsageDescription`を44公開ロケールへ追加し、Google Mobile Ads SDK起動前にATTを要求する。拒否時もアプリ機能を制限せず、非パーソナライズ広告だけを利用する。

選択しないデータ種類:

- 連絡先情報、財務情報、連絡先、閲覧履歴、検索履歴、機密情報
- 正確な位置情報

## 3. 端末内だけで扱うデータ

次は通常iPhone、Apple Watch、HealthKit内に保持し、広告・利用分析へ自動送信しない。ただし、ユーザーがAI分析を実行してOpenAIへ送った内容は、同社の不正利用監視ログへ通常最大30日保持され得るため、該当する健康、フィットネス、写真、その他のユーザーコンテンツをApp Privacyへ申告する。

- 体重、腹囲、体脂肪率、身体測定
- 食事、PFC、カロリー、バーコード
- 体型写真
- トレーニング計画、実績、PR、RPE
- 睡眠、歩数、心拍、HRV、手首温度などのHealthKit情報
- ジム位置と訪問履歴
- 診断ログ
- AI会話履歴、承認済みAI記憶、日次提案

診断ログは自動送信しない。利用分析イベントは初期オフで、更新後に明示同意した場合だけ、イベントUUID、日時、固定イベント名、アプリ版、言語と、目的、経験、今日の調子、提案カテゴリ、表示位置、提案元、完了方法、差替え理由の固定区分を、氏名やメールと結び付けない仮名化インストール単位で収集する。身体・食事・センサーの値、本文、写真、位置、広告IDは含めず、最大90日保持し、設定からサーバー上の本人分も削除できる。

## 4. AI処理の判定

AI利用時は、ユーザーの明示操作と許可カテゴリに基づき、入力文、写真、健康・食事・運動の要約をBodyModeのCloudflare Worker経由でOpenAI Responses APIへ送る。

BodyModeは`store: false`を指定し、D1データベースや運用ログへ会話本文、記録コンテキスト、写真、AI回答を保存しない。OpenAIはAPI入出力を既定では学習に使用しないが、不正利用監視ログへ入力、出力、画像を含めて通常最大30日保持する場合がある。Appleの定義では第三者パートナーによる処理時間を超えた保持も「収集」に含まれるため、AIへ送る4データ種類を申告する。

現在保持する運用情報:

- 推論メタデータ: ランダムなrequest ID、機能、モデル、処理結果、トークン数、処理時間、エラー分類。本文と画像は含めない。
- 認証・制限情報: 仮名アカウントID、期限付きのレート制限用指紋。平文のIP、APIキー、アクセストークンは保存しない。
- AIアカウント: Apple subjectから作る仮名ID、AIクレジット残高・台帳をアカウント削除まで保持する。氏名とメールは保持しない。削除前のD1日次バックアップは最大14日で失効する。
- 購入: App StoreトランザクションID、商品ID、付与量を二重付与防止のためアカウント削除まで保持する。
- 報酬広告: 匿名チャレンジID、Google署名済み広告トランザクションID、付与結果を重複防止のため保持する。健康記録やAI本文とは結合しない。

現在の13データ種類に含めるAI関連の申告:

| AIへ送信し得る内容 | データ種類 | 主な目的 |
|---|---|---|
| チャット本文、メモ | その他のユーザーコンテンツ | Appの機能 |
| 食事・体型写真 | 写真またはビデオ | Appの機能 |
| 体重、腹囲、睡眠、心拍等 | 健康、フィットネス | Appの機能 |
| 食事名、PFC、カロリー | その他のユーザーコンテンツ、健康またはフィットネス | Appの機能 |
| トレーニング履歴 | フィットネス | Appの機能 |
| IP、障害記録、応答時間 | おおよその位置情報、診断 | セキュリティ、アナリティクス、Appの機能 |

公開前の運用確認:

- Cloudflare Worker、D1、運用ログに本文や画像が残らない。
- 認証・推論ログの保持期間と削除方法を公開文書へ記載する。
- 障害調査用ペイロード保存は初期状態で無効にする。
- 委託先や外部AI APIへ転送する場合は、そのデータ利用も回答へ追加する。

## 5. App Store Connect入力状況

2026-08-23に本書の13データ種類をApp Store Connectへ下書き入力した。各項目の利用目的、関連付け、Tracking回答は本書と一致し、`公開`ボタンが有効になるところまで確認済み。公開は正式な対外申告になるため、最終ArchiveのPrivacy Reportとプライバシーポリシーを照合してからAccount Holderが確定する。

## 6. 公開前チェック

- [x] Build 30のRelease ArchiveからPrivacy Manifest監査レポートを保存した
- [x] `1.0 (25)` IPA内の4 Manifestを機械集約し、7データ種別・3 Required-Reason APIが回答表と一致した
- [x] Google SDK 13.7.0 / UMP 3.1.0の同梱Privacy Manifestを確認した
- [x] AdMob本番設定とコードでパーソナライズ広告を無効にした
- [x] `NSUserTrackingUsageDescription`を44公開ロケールへ追加した
- [x] Google Mobile Ads SDK起動前にATTを要求し、拒否時もアプリ機能を制限しない実装へ変更した
- [x] Cloudflare WorkerとD1が本文・画像を保存せず、運用メタデータだけを保持することをコードで確認した
- [ ] AdMob Device IDのTracking回答を、Build 31の最終ArchiveとFirst-party ID無効・ATT実装で再確認する
- [x] D1日次バックアップを14日保持し、復旧手順とchecksumを確認した
- [x] 公開プライバシーポリシーの委託先・保持・削除説明と一致した
- [x] App Store Connectへ13データ種類を下書き入力し、公開可能な状態にした
- [ ] App Store Connectの回答をPublishした
- [x] Sign in with Appleの仮名ユーザーID、購入履歴、報酬広告トランザクションを回答表へ追加した

## 7. 参照

- Apple App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- OpenAI API Data Controls: https://platform.openai.com/docs/models/default-usage-policies-by-endpoint
- Google Mobile Ads SDK Data Disclosure: https://developers.google.com/admob/ios/privacy/data-disclosure
- 正本データ台帳: `../privacy_data_inventory.md`
- 機械監査結果: `../../.build/reports/privacy-manifest-audit-1.0-30.md`
- 変更検出基準: `../../Config/privacy_manifest_baseline.json`
