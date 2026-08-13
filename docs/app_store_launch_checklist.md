# BodyMode App Storeローンチチェックリスト

更新日: 2026-08-10

## 1. ローンチ範囲

初回ローンチは現在のBodyModeに次だけを追加する。

- 利用規約
- プライバシーポリシー
- iPhoneの非パーソナライズバナー広告
- App Store提出に必要な技術・メタデータ対応

初回には全画面・リワード広告、コミュニティ、ギフト、チャレンジ、サブスクリプション、SNS直接連携を入れない。

## 2. 判定

| 区分 | 状態 | 項目 | 対応 |
|---|---|---|---|
| 配布 | ブロック | Apple Developer Program | 現在は無料Personal Team。年間メンバーシップを有効化する |
| 法務 | 一部対応 | プライバシーポリシー | アプリ内表示と原稿は完成。公開URLを用意する |
| 法務 | 一部対応 | 利用規約 | アプリ内表示と原稿は完成。公開URLを用意する |
| 問い合わせ | 一部対応 | Support URL・連絡先 | アプリ内導線と原稿は完成。公開URLとメールアドレスを用意する |
| 広告 | 一部対応 | 初回リリース | AdMobバナー、UMP、非パーソナライズ、報告導線は完成。AdMob本番IDと同意メッセージの公開が残る |
| プライバシー | 対応済み | `PrivacyInfo.xcprivacy` | iPhoneとWatchへUserDefaults利用理由を追加・製品内確認済み |
| セキュリティ | 対応済み | App Transport Security | 全通信許可を削除し、HTTPをローカルAI接続先へ制限済み |
| App Store | 未対応 | App Privacy申告 | 本体と広告SDKの収集データを申告する |
| App Store | 未対応 | 年齢レーティング | App Store Connectの質問票に回答する |
| App Store | 未対応 | Health・医療機器申告 | 非医療アプリとして対象地域の申告を完了する |
| App Store | 一部対応 | 輸出コンプライアンス | 非免除暗号なしをInfo.plistへ設定。Connect上の確認が残る |
| App Store | 未対応 | DSA事業者申告 | EUへ配信する場合に事業者情報を登録する |
| メタデータ | 対応済み | 説明・キーワード・カテゴリ | `docs/app_store_connect/app_store_metadata_ja.md`に日本語原稿を作成済み |
| メタデータ | 未対応 | スクリーンショット | iPhone必須サイズとWatch画像を用意する |
| 審査 | 対応済み | App Review Notes | HealthKit、Watch、AI停止時の動作を原稿へ反映済み |
| 品質 | ローカル完了 | Releaseビルド・UIテスト | iPhone 27本、Watch 3本、提出画像テスト、Development署名Archiveに合格。Distribution Archiveはアカウント準備後に再確認する |
| 品質 | 要再検証 | 実機受入 | iPhoneとWatchで主要フローを一周する |
| データ | 対応済み | 全データ削除 | 設定画面から実行可能 |
| データ | 対応済み | データ書き出し | JSONで書き出し可能 |
| 権限 | 対応済み | Health・位置・モーション説明 | Info.plistに用途説明あり |
| アカウント | 対象外 | アプリ内アカウント削除 | 初回版はアカウントを作成しない |
| 課金 | 対象外 | StoreKit・購入復元 | 初回版はデジタル課金を提供しない |

## 3. 広告方針

初回版はiPhoneの共通ルート上部にバナーを1枠固定し、主要タブとその配下画面で継続表示する。HealthKit、身体値、食事、写真、睡眠、回復、トレーニング、目標、位置情報を広告選定へ使用しない。Watch、Widget、通知には広告を置かない。

広告は非パーソナライズとし、UMPの同意状態更新後にだけ読み込む。設定にデータ利用、プライバシー選択、不適切広告の報告導線を置く。

## 4. 法務画面

設定画面に「法務・プライバシー」セクションを追加する。

- 利用規約
- プライバシーポリシー
- 広告とデータ利用
- AI・健康情報に関する注意
- オープンソースライセンス
- サポートへ連絡

プライバシーポリシーには最低限、以下を記載する。

- 端末内に保存するデータ
- HealthKit、位置情報、モーション、写真の利用目的
- ローカルLLMへ送るデータとユーザー選択
- 広告事業者と送信されるデータ
- 保持期間
- 同意を変更する方法
- データ書き出し・削除方法
- 問い合わせ先

利用規約には最低限、以下を記載する。

- 提供機能と利用条件
- 禁止事項
- 知的財産
- サービス変更・停止
- 保証と責任の範囲
- AI出力は参考情報であること
- 医療診断・治療を行わないこと
- 緊急時や体調不安時は専門家へ相談すること
- 広告・外部サービス
- 規約変更
- 準拠法・管轄

Appleの標準EULAは利用できるが、BodyMode固有の健康・AI・広告条件を説明するため、独自利用規約をアプリ内に用意する。

## 5. 技術対応

### 5.1 プライバシーマニフェスト

iPhoneとWatchは`UserDefaults`をアプリ内データ保存へ利用している。各ターゲットへ`PrivacyInfo.xcprivacy`を追加し、次を申告する。

```text
NSPrivacyAccessedAPICategoryUserDefaults
Reason: CA92.1
```

Google Mobile AdsとUser Messaging Platformの署名・プライバシーマニフェストをアーカイブ内で確認する。

### 5.2 通信

公開版は`NSAllowsArbitraryLoads`を使用せず、次の方針とする。

- Debug: ローカルLLM開発用のHTTP接続を許可
- Release: HTTPSを標準とする
- Release: 必要なローカルネットワークだけを最小権限で許可
- AIに接続できない場合も記録、履歴、Watchを利用可能にする

### 5.3 広告SDK

Google Mobile Ads 13.7.0とUser Messaging Platform 3.1.0をiPhoneターゲットだけにSwift Package Managerで追加する。設計と本番化手順は`docs/advertising_integration.md`を正とする。

## 6. App Store Connect

提出前に以下を設定する。

- アプリ名、サブタイトル
- Bundle ID、SKU
- 主カテゴリ`Health & Fitness`
- 年齢レーティング
- 説明、キーワード
- Privacy Policy URL
- Support URL
- スクリーンショット
- App Privacy
- コンテンツ権利
- 輸出コンプライアンス
- 対象地域
- DSA事業者状態
- 医療機器に該当しない旨の申告
- 審査連絡先
- App Review Notes

審査メモでは次を説明する。

- アカウント登録は不要
- HealthKit権限なしでも手動記録できる
- Apple WatchがなくてもiPhoneの主要機能を使える
- AIサーバー停止中も記録を継続できる
- 広告はiPhoneのバナーのみ、非パーソナライズで、健康データを使用しない
- 全データ削除と書き出しの場所

## 7. 提出ゲート

次をすべて満たすまでApp Reviewへ送らない。

- P0/P1クラッシュが0件
- iPhoneとWatchのReleaseビルド成功
- 主要UIテスト成功
- 実機で計画、Watch記録、履歴、身体、食事、削除を完了
- プライバシーポリシーと利用規約のURLが公開済み
- App Privacy申告とアプリ内表示が一致
- Google Mobile AdsとUMPがiPhoneだけに組み込まれ、Watch・Widgetに広告SDKが入っていない
- App PrivacyがGoogle Mobile Adsの最新開示とPrivacy Reportに一致し、本番IDとUMPメッセージが設定済み
- Privacy Manifest検証成功
- Releaseで不要なATS例外がない
- App Storeの商品ページと審査情報が入力済み
- Apple Developer Programと契約が有効

## 8. ローンチ後

- クラッシュ率とTestFlightフィードバックを毎日確認する。
- Privacy Policyまたは広告事業者の変更時にApp Privacy申告も更新する。
- 初回は日本のみで公開し、審査・広告・サポート運用が安定してから配信地域を広げる。
