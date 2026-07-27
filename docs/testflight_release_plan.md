# BodyMode TestFlight公開計画

更新日: 2026-07-27

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
- クラッシュ修正、UIテスト、実機テスト

### 初回ビルドでは出さない

- 本番広告
- SNS、コミュニティ、ギフト、チャレンジ
- サブスクリプション、アプリ内課金
- 外部SNSへの直接投稿

広告はTestFlightの2本目でテスト広告を導入し、正式公開版で本番広告へ切り替える。初回TestFlightでは、アプリ本体の継続利用とWatch連携の検証に集中する。

## 3. タスク一覧

| ID | 優先 | 状態 | タスク | 完了条件 |
|---|---|---|---|---|
| TF-01 | P0 | ブロック | Apple Developer Programを有効化 | App Store Connectへアクセスでき、配布用署名を作成できる |
| TF-02 | P0 | 完了 | 初回TestFlight範囲を固定 | 本書の「入れる・出さない」が合意済み |
| TF-03 | P0 | 一部完了 | 利用規約とプライバシーポリシーを作成 | アプリ内表示と公開用原稿は完成。公開URLが残る |
| TF-04 | P0 | 一部完了 | サポート窓口を用意 | アプリ内導線と原稿は完成。公開URLとメールアドレスが残る |
| TF-05 | P0 | 完了 | Privacy Manifestを追加 | iPhone・Watchの`UserDefaults`利用理由がRelease製品へ組み込み済み |
| TF-06 | P0 | 完了 | Release通信設定を安全化 | 全通信許可を削除し、HTTPをローカル接続先へ制限済み |
| TF-07 | P0 | 完了 | Release用AI設定を整理 | ReleaseはAI初期オフ。開発用APIキーがReleaseバイナリにないことを確認済み |
| TF-08 | P0 | Simulator完了 | 既知クラッシュを回帰確認 | 履歴、コンディション、記録詳細の反復遷移に合格。実機確認はTF-16で行う |
| TF-09 | P0 | 完了 | iPhone UIテスト | コア16本、AI食事解析、Watch送信の計18本に合格 |
| TF-10 | P0 | Simulator完了 | Watch UI・連携テスト | Watch主要2本とiPhoneからの送信に合格。実機確認はTF-16で行う |
| TF-11 | P0 | 完了 | バージョンとビルド番号を更新 | `0.1.0 (3)`へ更新済み |
| TF-12 | P0 | 未着手 | App Store Connectアプリを作成 | Bundle ID、SKU、カテゴリが登録済み |
| TF-13 | P0 | 原稿完了 | TestFlight情報を入力 | 登録用原稿は完成。App Store Connectへの入力と連絡先が残る |
| TF-14 | P0 | アプリ対応完了 | 輸出コンプライアンスを回答 | 非免除暗号なしをInfo.plistへ設定。App Store Connect確認が残る |
| TF-15 | P0 | 未着手 | 配布用アーカイブをアップロード | App Store Connectで処理完了になる |
| TF-16 | P0 | 未着手 | 内部TestFlightで受入確認 | iPhoneとWatchへインストールし、主要フローを一周できる |
| TF-17 | P0 | 未着手 | 外部TestFlight審査へ提出 | 最初の外部ビルドがBeta App Review承認済み |
| TF-18 | P0 | 未着手 | 初期テスターを招待 | 5〜10人が招待を受け、フィードバック手段を理解している |
| TF-19 | P1 | 一部完了 | クラッシュ収集を決定・導入 | MetricKit・端末内ログ・書き出しは実装済み。TestFlight側の受信確認が残る |
| TF-20 | P1 | 未着手 | テスト広告を導入 | 本番IDと分離され、非パーソナライズ・一枠・iPhone限定で動く |

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

## 6. 正式公開まで後回しにできるもの

- App Store用の最終スクリーンショットとキーワード調整
- 本番広告IDと広告収益の設定
- App Privacyの広告SDK分を含む最終更新
- 販売地域の拡大
- SNS、コミュニティ、ギフト、チャレンジ
- 課金、サブスクリプション

TestFlightビルドはアップロードから最大90日間利用できる。1週間の検証単位でビルドを更新し、各ビルドの「What to Test」に変更点と確認してほしい操作を明記する。

## 7. 2026-07-28実施記録

- iPhone・Apple Watchの実機アーキテクチャ向けReleaseビルド成功
- iPhone・Watch製品内の`PrivacyInfo.xcprivacy`を検証
- Release製品から開発用AIキーが除外されていることを検証
- Release製品に`NSAllowsArbitraryLoads`がないことを検証
- iPhone UIテスト18本合格
- Apple Watch UIテスト2本合格
- iPhoneからApple Watchへのメニュー送信テスト合格
- 履歴・コンディション・記録詳細の反復遷移テスト合格
- ローカルOllamaによる食事写真解析テスト合格
- 利用規約、プライバシー、健康・AI注意、サポート画面の遷移テスト合格

再検証は`scripts/testflight_preflight.sh`でRelease製品を確認した後、iPhone・WatchのUIテストを実行する。
