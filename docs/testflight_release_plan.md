# BodyMode TestFlight公開計画

更新日: 2026-08-14

## 1. 到達点

最初の到達点は、開発者本人だけでなく友人5〜10人が招待からインストールできる「外部TestFlight」とする。

公開手順は次の順番で進める。

1. App Store Connectへビルドをアップロードする
2. 内部テスターとしてiPhone・Apple Watchで最終確認する
3. 外部テストグループを作り、最初のTestFlight App Reviewへ提出する
4. 承認後、5〜10人へ招待を送る

## 2. 初回ビルドの範囲

### 入れる

- 現在実装済みのiPhone・Apple Watch・Widget機能
- 手動記録、履歴、身体、食事、トレーニング、コンディション
- iPhoneとApple Watchのトレーニング連携
- データ書き出し・全データ削除
- 利用規約、プライバシーポリシー、健康・AIに関する注意
- Privacy Manifest
- Release用の通信・AI設定
- iPhone全主要画面の共通固定テストバナー広告、UMP同意、広告報告導線
- クラッシュ修正、UIテスト、実機テスト

### 初回ビルドでは出さない

- 全画面、リワード、App Open、Watch・Widget内の広告
- SNS、コミュニティ、ギフト、チャレンジ
- サブスクリプション、アプリ内課金
- 外部SNSへの直接投稿

初回TestFlightはGoogle公式デモIDで広告表示のUXと同意・報告導線を検証する。本番IDはAdMob設定とApp Privacy確定後に入れる。

## 3. タスク一覧

| ID | 優先 | 状態 | タスク | 完了条件 |
|---|---|---|---|---|
| TF-01 | P0 | 完了 | Apple Developer Programを有効化 | App Store Connectへアクセスでき、配布用署名を作成できる |
| TF-02 | P0 | 完了 | 初回TestFlight範囲を固定 | 本書の「入れる・出さない」が合意済み |
| TF-03 | P0 | 進行中 | 利用規約とプライバシーポリシーを作成 | アプリ内表示と公開用原稿は完成。公開URLが残る |
| TF-04 | P0 | 進行中 | サポート窓口を用意 | アプリ内導線と原稿は完成。公開URLとメールアドレスが残る |
| TF-05 | P0 | 完了 | Privacy Manifestを追加 | iPhone・Watchの`UserDefaults`利用理由がRelease製品へ組み込み済み |
| TF-06 | P0 | 完了 | Release通信設定を安全化 | 全通信許可を削除し、HTTPをローカル接続先へ制限済み |
| TF-07 | P0 | 完了 | Release用AI設定を整理 | 接続初期値はGit管理外のxcconfigから注入。アプリ内で変更でき、APIキーは変更後Keychainへ保存される |
| TF-08 | P0 | 完了 | 既知クラッシュを回帰確認 | 履歴、コンディション、記録詳細の反復遷移にSimulatorで合格。実機確認はTF-16で行う |
| TF-09 | P0 | 完了 | iPhone UIテスト | 現行27シナリオとアクセシビリティ監査に合格 |
| TF-10 | P0 | 完了 | Watch UI・連携テスト | Watch主要3本とiPhoneからの送信にSimulatorで合格。実機確認はTF-16で行う |
| TF-11 | P0 | 完了 | バージョンとビルド番号を更新 | `0.1.0 (16)`へ更新済み |
| TF-12 | P0 | 完了 | App Store Connectアプリを作成 | Bundle ID、SKU、カテゴリが登録済み |
| TF-13 | P0 | 完了 | TestFlight情報を入力 | 外部テストに必要な情報と審査メモを登録済み |
| TF-14 | P0 | 完了 | 輸出コンプライアンスを回答 | 非免除暗号なしをInfo.plistとConnectへ設定済み |
| TF-15 | P0 | 完了 | 配布用アーカイブをアップロード | Build 16がApp Store Connectで`VALID`になっている |
| TF-16 | P0 | 進行中 | TestFlightで受入確認 | iPhoneとWatchへインストールし、Build 16の主要フローを一周できる |
| TF-17 | P0 | 完了 | 外部TestFlight審査へ提出 | Build 16が外部グループで`IN_BETA_TESTING`になっている |
| TF-18 | P0 | 進行中 | 初期テスターを招待 | 公開リンクで配布中。5〜10人が参加し、フィードバック手段を理解している状態まで広げる |
| TF-19 | P1 | 進行中 | クラッシュ収集を決定・導入 | MetricKit・保護された端末内ログ・保持上限・削除・書き出しは実装済み。TestFlight側の受信確認が残る |
| TF-20 | P0 | 完了 | 広告を安全に実装 | iPhone主要画面で継続する固定バナー1枠、60秒再試行、非パーソナライズ、UMP、健康データ分離、報告導線がある |
| TF-21 | P0 | 完了 | ローカル記録を保護 | 保護ファイルへ移行し、バックアップ対象外、書き出し可能にする |
| TF-22 | P0 | 完了 | 提出画像を作成 | iPhone 1320×2868を6枚、Watch 416×496を3枚、アルファなしで生成する |
| TF-23 | P0 | ブロック | AdMobを本番設定 | アプリID、バナーID、Privacy & messaging、年齢相当の広告ブロックをAdMobで設定する |

## 4. 実施順

### Gate 1: 配布資格

- TF-01を完了する
- App Store Connectの契約・税務・口座情報のうち、TestFlightアップロードに要求される項目を確認する

### Gate 2: 提出可能なアプリ

- TF-03〜TF-11を完了する
- Simulatorと実機の両方でクラッシュ回帰を確認する
- AIサーバーがない環境でも記録アプリとして成立させる

### Gate 3: App Store Connect

- TF-12〜TF-15を完了する
- 審査メモへ「アカウント不要」「HealthKitなしでも手入力可能」「Watchは任意」「AI未接続でも利用可能」を記載する

### Gate 4: 配布

- TF-16の内部確認後にTF-17を提出する
- 承認後にTF-18を実施する
- 1週間の利用結果を見て、TF-19とTF-20を次ビルドへ入れる

## 5. 初回テスト項目

- 初回起動から目的設定まで完了できる
- 体重・腹囲・食事・コンディションを手入力できる
- トレーニング計画を作り、iPhoneだけで完了できる
- Apple Watchで今日のメニューを選び、セット・休憩・完了を記録できる
- Watch完了後、iPhoneのToday's Sessionが完了状態になり詳細を開ける
- 履歴とコンディションを繰り返し開いても落ちない
- AIサーバー未接続時にクラッシュせず、記録を継続できる
- HealthKit、位置、モーションを拒否しても手動記録を使える
- 全データ削除とデータ書き出しが動作する
- 利用規約、プライバシーポリシー、サポート導線を開ける
- 全主要タブで固定テスト広告が継続し、広告のデータ説明、プライバシー選択、報告導線を確認できる

## 6. 正式公開まで後回しにできるもの

- バナー以外の広告フォーマット
- 販売地域の拡大
- SNS、コミュニティ、ギフト、チャレンジ
- 課金、サブスクリプション

TestFlightビルドはアップロードから最大90日間利用できる。1週間の検証単位でビルドを更新し、各ビルドの「What to Test」に変更点と確認してほしい操作を明記する。

## 7. アップロード認証

日常のアップロードはXcodeのApple Accountセッションではなく、App Store Connect APIキーを使用する。これによりXcodeの認証情報が失効・欠損しても、再ログインなしで自動アップロードできる。

TestFlightフィードバックも同じAPIキーで取得する。スクリーンショット、コメント、端末情報、クラッシュ報告は次のコマンドで`.build/TestFlightFeedback`へ保存する。

```bash
scripts/fetch_testflight_feedback.sh
```

アップロード後は、同じAPIキーで処理完了確認、外部テストグループへの追加、必要なBeta App Review提出を自動化する。

```bash
scripts/distribute_testflight_build.sh <BUILD_NUMBER>
```

App Store Connectの「ユーザとアクセス」からAPIキーを一度発行し、キーID、Issuer ID、ダウンロードした秘密鍵を次のコマンドで登録する。

```bash
scripts/configure_app_store_connect_api_key.sh <KEY_ID> <ISSUER_ID> <AuthKey_XXXX.p8>
```

秘密鍵と設定は`~/Library/Application Support/BodyMode/AppStoreConnect`へ権限`600`で保存し、Git管理下には置かない。`scripts/upload_testflight_archive.sh`は登録済みAPIキーを自動利用し、未登録の場合のみXcodeのApple Accountへフォールバックする。

2026年8月11日、チームAPIキーを保護フォルダへ登録し、BodyModeのApp Store Connect情報を読み取り専用で取得できることを確認した。今後のアップロードはこのAPIキーを使用し、XcodeのApple Accountセッションには依存しない。

## 8. 2026-08-03実施記録

- iPhone・Apple Watchの実機アーキテクチャ向けReleaseビルド成功
- iPhone・Watch製品内の`PrivacyInfo.xcprivacy`を検証
- Release製品から開発用AIキーが除外されていることを検証
- Release製品に`NSAllowsArbitraryLoads`がないことを検証
- iPhone UIテスト27シナリオ、主要4画面のアクセシビリティ監査に合格
- Apple Watch UIテスト3本、Watch提出画像テスト3本に合格
- iPhoneからApple Watchへのメニュー送信テスト合格
- 履歴・コンディション・記録詳細の反復遷移テスト合格
- 食事写真AIのUIフローを決定的なDebugスタブで検証。実サーバーは統合テストとして分離
- 利用規約、プライバシー、健康・AI注意、サポート画面の遷移テスト合格
- 端末ロック連動の記録ファイル保護、バックアップ除外、旧保存値の移行を実装
- 診断ログを14日・1,000件・2MiBへ制限し、設定から削除可能にした
- 6.9インチiPhone画像6枚とSeries 11 Watch画像3枚をApple指定サイズで生成
- Apple Development署名Archiveを作成し、iPhone・Watch・Widgetの署名と埋め込みを検証
- App Store Connectエクスポートは`No Accounts`と配布プロファイル不足で停止することを確認

再検証は`scripts/testflight_preflight.sh`でRelease製品を確認した後、iPhone・WatchのUIテストを実行する。
