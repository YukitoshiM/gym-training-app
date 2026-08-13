# BodyMode 並列回帰テスト報告

実施日: 2026-08-13

## 結論

回帰テストはiPhone 2台とWatch 1台の専用Simulatorへ分離する。iPhoneとWatchは事前ビルドを1回だけ行い、同じ`xctestrun`を使う。iPhone UIは最大2台で並列実行し、Watch UIはiPhone終了後に直列実行する。2026-08-13に、この回帰をリリース候補の必須ゲートへ昇格した。

自動化強化前に実行した全体回帰の確認結果は次のとおり。

| 対象 | 成功 | 失敗 | スキップ |
|---|---:|---:|---:|
| 単体テスト | 89 | 0 | 0 |
| iPhone UIテスト | 44 | 0 | 2 |
| Watch UIテスト | 4 | 0 | 0 |
| 合計 | 137 | 0 | 2 |

追加実装後の差分回帰も、3エージェントが専用Simulatorと個別DerivedDataを使って同時実行した。

| 対象 | 成功 | 失敗 | スキップ | 所要時間（ビルド込み） |
|---|---:|---:|---:|---:|
| 単体テスト全件 | 91 | 0 | 0 | 56秒 |
| AI UIテスト全件 | 5 | 0 | 0 | 203秒 |
| Watch UIテスト全件 | 7 | 0 | 0 | 231秒 |
| 差分回帰合計 | 103 | 0 | 0 | 最長231秒 |

この差分回帰では、週次AIレポートの構造化表示、コーチ回答の役立ち評価、Watchの主要7フローまで確認した。独立3系統を直列実行した場合の単純合計は490秒で、並列実行では最長系統の約231秒に収まった。

スキップはGoogle広告ネットワークの任意テストと、ペアリング済みWatchが必要なiPhone側の転送テストである。Watchアプリ単体の主要4フローは成功した。

## リリースゲート基準

`scripts/run_parallel_simulator_regression.sh`は、次の全件を必須ゲートとして実行する。

- `GymTrainingAppTests`の単体テスト全件
- スクリーンショット専用クラスを除く`GymTrainingAppUITests`全件
- スクリーンショット専用クラスを除く`GymTrainingWatchAppUITests`全件

`GymTrainingAppUITests/FigmaReferenceScreenshots`と`GymTrainingWatchAppUITests/WatchFigmaReferenceScreenshots`はApp Store画像生成用であり、表示差分を人が確認する非ゲートテストとする。通常の画面遷移中に添付される診断スクリーンショットは、テスト自体の合否へ影響しない。

失敗は1件でもゲート失敗とする。スキップは次の固定allowlistだけを許可し、それ以外のスキップ、結果bundle欠落、読み取り不能、テスト0件、テストコマンドの異常終了をゲート失敗とする。

- `IntegrationAndHealthUITests/testWatchPlanTransfer()`
- `SettingsAndAccessibilityUITests/testGoogleDemoBannerLoadsWhenNetworkIntegrationTestsAreEnabled()`

allowlist対象も結果へ明示し、暗黙のスキップにはしない。スクリーンショット専用テストが誤ってゲート結果へ混入した場合も失敗する。

ビルド後にXcodeのtest inventoryを列挙し、全レーンの`xcresult`に現れたtest identifierと照合する。新しいテストクラスをレーンへ追加し忘れた場合や、選択条件の誤りでテストが実行されなかった場合もゲート失敗になる。

## 実行構成

| レーン | Simulator | テスト |
|---|---|---|
| iPhone A | BodyMode QA Core | 単体、統合、Health、Workout、初期設定、初心者導線、AI、おまかせ |
| iPhone B | BodyMode QA Meals | 身体・食事、設定、アクセシビリティ、利用分析 |
| Watch | BodyMode QA Watch 2 | iPhone 2レーン終了後にWatch主要フロー |

3本以上のUIテストや複数のクリーンビルドを同時実行すると、`actool`、Swift Releaseコンパイル、CoreSimulatorのイベントループが競合した。共有ビルド後にiPhone 2レーンだけを並列化し、Watchを後続にする構成をこのMacの上限とする。

共有キャッシュを使った全体周回は14分46秒だった。その周回で検出した3件も個別修正後に再実行し、すべて成功した。現在の`summary.txt`はGit SHA、dirty/clean、アプリ版・ビルド番号、レーン別と合計の成功・失敗・スキップ数、allowlist判定、総所要時間、最終ゲート判定を自動記録する。

重いアクセシビリティ監査と利用分析テストは、通常の設定テスト後にiPhone Bを再起動してから実行する。各テストは一時的なSimulator起動失敗に備えて失敗時のみ1回再試行する。実行終了時は、このスクリプトが起動した3台を自動停止する。画面確認のため残す場合だけ`BODYMODE_KEEP_SIMULATORS_RUNNING=1`を指定する。

## 今回検出して修正した内容

- 初回ユーザーで、トレーニングメニュー作成より歩数が優先される導線
- 日次AI処理とWatch起動時の不要な通知権限要求
- 食事入力欄、計画作成、Watch開始ボタンの画面遷移待ち不足
- iOS写真ピッカーの内部アクセシビリティIDへのテスト依存
- テーマ選択と利用分析スイッチの状態確定前に進むUIテスト
- おまかせホームのコーチ状態、提案名、DailyActionタイトルのDynamic Type切れ
- AI接続失敗カードの待機時間不足

## 実行方法

```bash
./scripts/run_parallel_simulator_regression.sh
```

スクリプトは2台の専用iPhone Simulatorを並列実行し、その終了後に専用Watch Simulatorを実行する。共有ビルドを再利用し、ほかのタスクが使うSimulatorは起動・停止しない。通常は終了時に今回の3台だけを停止する。

結果は`.build/parallel-regression/<run-id>/summary.txt`、各グループのログと`xcresult`は同じ実行ディレクトリへ保存される。ビルドキャッシュは`.build/parallel-regression/cache/`で再利用する。

リリース候補では、回帰と本番preflightを1コマンドで続けて実行する。

```bash
./scripts/run_release_candidate_gate.sh
./scripts/run_release_candidate_gate.sh .build/BodyMode.xcarchive
```

第2形式ではArchive内の署名とentitlementも検査する。どちらもArchiveのexport、upload、TestFlight配布は行わない。片方が失敗しても両方を実行し、最後に各statusと全体判定を表示する。

## 残る実機確認

- iPhoneとペアリング済みApple Watch間の計画転送
- HealthKit、触覚、通知、バックグラウンド動作
- Google広告ネットワークを有効にした実通信

これらはSimulator回帰と分け、TestFlight実機受入で確認する。
