# TestFlightフィードバック 2026-08-12

取得方法: `scripts/fetch_testflight_feedback.sh`

- 取得件数: 9件
- クラッシュ報告: 0件
- フィードバック対象ビルド: 8、9
- 修正版: 10（外部TestFlight配布済み）
- 個人情報と署名付き画像URLはこの文書へ保存しない

## 現在の対応状況

2026-08-12の現在ソースと自動テストを基準に判定した。

| 状態 | 優先度 | 対象 | フィードバック | 現在の実装と残り |
|---|---|---|---|---|
| Build 10配布済み・実機確認待ち | P0 | Build 9 | 食事画像解析でAIサーバー接続エラー | AI APIを`~/Library/Application Support/BodyMode`のLaunchAgentへ移行し、Tailscale Funnelの固定`*.ts.net` URLを設定した。外部疎通は未認証`401`、認証あり`200`、CalorieCLIP・Ollamaとも正常。正式リリース前に独自ドメインのCloudflare Named Tunnelへ移行する |
| Build 10配布済み・実機確認待ち | P1 | Build 9 | 保存した食事記録を修正したい | 行タップで既存値・写真・AI下書き・食品リストを復元し、同じIDへ上書き保存する。重複しないことをUIテスト済み |
| Build 10配布済み・実機確認待ち | P1 | Build 8、9 | 食事写真をその場でカメラ撮影したい | カメラ撮影と写真ライブラリを選択可能。権限拒否時は設定画面への復旧導線を表示する |
| 対応済み | - | Build 8 | ホームの「計画を作成しましょう」から計画作成へ進みたい | ホームのCTAから計画タブへ移動し、初心者は入力済みの「初心者 全身スタート」を直接開く。UIテストあり |
| Build 10配布済み・実機確認待ち | P2 | Build 9 | 完了済みBEGINNER LEVELカードを残す意味が分からない | 3回完了後は初期チェックリストを終了し、現在レベル・次の目標・目的別メニューを示す小型カードへ置換する |
| Build 10配布済み・実機確認待ち | P2 | Build 9 | 身体KPIを画像から自動推定したい | 断定的な画像数値推定は行わず、撮影セット詳細へ同日の体重・腹囲・体脂肪率を表示し、未記録値はその場で記録できる導線を追加した |
| Build 10配布済み・実機確認待ち | P2 | Build 8 | ホームの縦スクロールを減らしたい | 今日の記録カードを1枚へ統合し、食事・体型写真の操作もカード内へ集約。重複していた進捗見出しと記録カードを削除した |
| Build 10配布済み・実機確認待ち | P3 | Build 8 | 初心者メニューを達成して段階解放したい | 3回完了後にレベル3を解放。目的・重点部位・利用可能な器具・週回数・所要時間・過去実績から最大3つのメニューを生成し、達成実績に応じて重量または回数を漸進する |

## 未対応タスク

1. TestFlight実機から食事画像解析とAIトレーナーの固定URL接続を確認する
2. 正式リリース前に独自ドメインとCloudflare Named Tunnelへ移行する

## P0原因調査

2026-08-12時点のMac miniで次を確認した。

- Ollamaは稼働している。
- `127.0.0.1:8765`のAI APIは停止している。
- LaunchAgent `com.yukitoshim.gymtraining.local-llm`は`/tmp/gym-local-llm-server`から起動する設定になっている。
- LaunchAgentは終了コード1で再起動を繰り返しており、ログは`No module named uvicorn`を示している。
- `/tmp/gym-local-llm-server`の仮想環境はPythonのシンボリックリンク以外が消失している。
- macOSのLaunchAgentは`Documents`配下の実行ファイルを直接開けないため、常駐ランタイムは`~/Library/Application Support/BodyMode`へ配置する。
- `cloudflared`プロセスと常駐サービスは存在しない。
- 配布設定の`christopher-using-organisations-hull.trycloudflare.com`はCloudflare DNSで`NXDOMAIN`になっている。

Quick Tunnelは`cloudflared`プロセスの存続中だけ有効なランダムURLである。プロセス終了の直接原因はログが残っていないため特定不能だが、終了を監視・復旧する常駐設定がなかったことが再発を許した。AI APIの停止とQuick Tunnelの停止は別障害であり、両方を修正する。

## P0対応結果

- AI APIは`~/Library/Application Support/BodyMode/local_ai_server`からLaunchAgentで自動起動する。
- TailscaleはuserspaceモードのLaunchAgentで自動起動し、Funnel設定を永続化する。
- 開発・TestFlightではTailscale提供の固定`*.ts.net` URLを使うため、独自ドメイン費用は発生しない。
- 公開エンドポイントはBearer認証必須で、未認証アクセスが`401`になることを確認した。
- AI APIとTailscaleを再起動しても同じURLで復帰し、外部から認証あり`200`になることを確認した。
- Releaseビルド設定が新しいFunnel URLを参照することを確認した。次回TestFlightビルドで実機確認する。
- 正式リリース前に独自ドメインを取得し、Cloudflare Named Tunnelへ移行する。

## 追加観察

- Build 8、9とも広告が最上部で非常に強く見える。常時表示方針は維持しつつ、アプリの主要操作を押し下げすぎない高さと配置を検証する。
- 食事画像推定結果の例では、596 kcalに対してP24g・F38g・C1gで、PFC換算値とカロリーに大きな差がある。写真推定は食品別内訳とユーザー確認を必須にする。
- KPI写真推定は利便性の要望として重要だが、数値を作るより「測定手段がない人でも変化を追える」体験へ再定義する。

## 自動テスト結果

- P1: 保存済み食事の上書き編集と重複防止をUIテスト済み
- P2: 体型写真セット詳細の実測KPIカードと再編集をUIテスト済み
- P3: 解放条件、目的別処方、設備制限、実績に基づく漸進を単体テスト済み
- P3: 初回初心者メニューとレベル3候補への画面遷移をUIテスト済み

## Build 10配布結果

- バージョン: `0.1.0 (10)`
- アップロード: 成功
- App Store Connect処理: `VALID`
- 外部グループ: `Friends & Family`
- Beta App Review: 提出済み
- 外部配布状態: `IN_BETA_TESTING`
- 公開リンク: `https://testflight.apple.com/join/1NVRKnKt`

## Build 10 AI接続エラーの追加調査

- 14:59の実機操作時、現行AIサーバーへ画像解析リクエストは到達していなかった。
- Build 10本体にはTailscale固定URLと正しいAPIキーが設定され、公開経路のヘルスチェックと食事画像解析はいずれも`HTTP 200`だった。
- Build 9が端末へ保存したQuick Tunnel URLとBuild 10の管理設定が同じ設定世代`2`だったため、起動時移行が実行されなかった。
- Build 9の旧URLが明示的な廃止URL一覧からも漏れていた。
- Build 11では設定世代を`3`へ更新し、Build 9の旧URLを移行対象へ追加した。
- 管理対象のURLまたはAPIキーが同梱設定と異なる場合は、設定世代の更新漏れがあっても自動移行する。ユーザーが保存したカスタム設定は対象外とする。
- Build 9からの更新経路を単体テスト7件と起動UIテスト1件で検証した。

## Build 11配布結果

- バージョン: `0.1.0 (11)`
- App Store Connect処理: `VALID`
- 外部グループ: `Friends & Family`
- Beta App Review: 提出済み
- 外部配布状態: `IN_BETA_TESTING`
- 公開リンク: `https://testflight.apple.com/join/1NVRKnKt`
