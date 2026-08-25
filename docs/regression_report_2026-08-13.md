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

## 2026-08-16 Build 23 リリース回帰

専用iPhoneを1台に制限してL3回帰を実行した。初回ゲートで検出したAI評価、ホームのアクセシビリティ、Watchチュートリアル表示条件を修正し、対象テストはすべて成功した。

最終全体周回は265件成功、1件失敗、許可スキップ2件だった。唯一の失敗は`testWeeklyReportSeparatesConclusionEvidenceAndActions`で、XCTestが30秒間メインスレッドの画面スナップショットを取得できない実行基盤エラーだった。同テストを規定どおり1回だけ個別再実行し成功した。Watchは7件すべて成功し、inventoryの欠落はない。

証跡:

- 全体: `.build/parallel-regression/build23-final-20260816/summary.txt`
- 実行基盤エラーの個別再確認: `.build/regression/build23-targeted/weekly-report-retry.xcresult`
- 単位・AI評価・アクセシビリティ: `.build/regression/build23-targeted/ui-verification.xcresult`
- Watch修正3フロー: `.build/regression/build23-targeted/watch.xcresult`

## 2026-08-14 フィードバック修正回帰

既存の別タスク用iPhone Simulatorを停止しないため、`BODYMODE_REGRESSION_IPHONE_WORKERS=1`を追加した。専用iPhone 1台で2レーンを直列実行し、同時にbootするiPhoneを合計2台以内に保つ。WatchはiPhone終了後に起動する。

```bash
BODYMODE_REGRESSION_IPHONE_WORKERS=1 ./scripts/run_parallel_simulator_regression.sh
```

1回目のL3は193件成功、3件失敗、許可スキップ2件だった。検出した内容は次のとおり。

- 体型写真コンタクトシート化へ追随していない単体テスト期待値
- 食事・写真UIテストプロセスの一時的なsignal kill。対象テストの再実行は成功
- 利用分析トグルで、`UserDefaults`書込みとSwiftUI監視が待ち合うメインスレッド停止

利用分析の同期書込みを修正し、単体2件とUI 1件の対象テストが成功した。

2回目のL3は196件成功、1件失敗、許可スキップ2件だった。残った1件は、旧値を自動消去する数値欄へUIテストが3回タップし、キーボード表示後の2・3回目が数字キーを押すテスト不具合だった。1回タップへ変更後、未登録バーコード商品の対象UIテストは成功した。

2回の`summary.txt`自体はいずれも`Gate: FAIL`のため、新しいL3成功基準点にはしない。コード変更の直接テストはすべて成功しているが、次の外部配布前に完全L3を1回成功させる。

| 証跡 | 結果 |
|---|---|
| `.build/parallel-regression/20260814-142237/summary.txt` | 1回目L3、3件検出 |
| `.build/parallel-regression/20260814-l3-final/summary.txt` | 2回目L3、製品196件成功、テスト入力1件失敗 |
| `.build/regression/l3-failure-fixes-20260814.xcresult` | コンタクトシート・食事写真フロー成功、利用分析修正前失敗 |
| `.build/regression/usage-analytics-fix-20260814.xcresult` | 利用分析の単体2件・UI 1件成功 |
| `.build/regression/barcode-input-fix-20260814.xcresult` | バーコード数値入力UI成功 |

## 2026-08-14 Build 15配布前L3

Git SHA `231f8be67be8`、クリーンな作業ツリー、アプリ`0.1.0 (14)`で配布前L3を実行した。アプリ動作コードはこの結果から変更せず、配布識別子だけをBuild 15へ更新する。

| 領域 | 成功 | 失敗 | スキップ |
|---|---:|---:|---:|
| 単体 | 145 | 0 | 0 |
| iPhone UI | 45 | 0 | 2（固定allowlist） |
| Watch UI | 7 | 0 | 0 |
| 合計 | 197 | 0 | 2 |

iPhoneは期待192件・実行192件、Watchは期待7件・実行7件で、欠落と予定外テストはいずれも0件だった。`Gate: PASS`のため、これを新しいL3成功基準点とする。

証跡: `.build/parallel-regression/20260814-build15-release/summary.txt`

## 2026-08-14 Build 17 コーチキャスト配布確認

目的別12人の担当コーチ、旧保存値移行、アバター表示、AIコンテキスト反映を追加した。iPhone Simulatorは別タスクを含め最大2台に抑えるため、BodyMode側1台でL3を実行した。

全体回帰では202件を列挙・実行し、旧コーチ名を期待していたテスト3件とホームのアクセシビリティ監査1件を除いて成功した。旧名称3件は新しい既定担当`Nia`へ更新後、対象再実行で成功した。Watch 7件、単体全件、主要iPhone UI、食事、設定、利用分析は成功した。

アクセシビリティ監査は、SwiftUI内部ノードについて`Hit area is too small`を1件報告したが、対象`XCUIElement`は`nil`だった。階層上で44pt未満だった完了、理由、学習リセット操作は、実内容のpaddingを含む48pt以上へ修正した。iOS 26.5監査の要素特定不能判定は残るため、次回Xcode更新時にも再確認する。

配布前preflight、署名付きArchive検証、App Store Connectアップロードは成功した。Build 17は`VALID`、外部グループ`Friends & Family`で`IN_BETA_TESTING`となった。

| 証跡 | 結果 |
|---|---|
| `.build/parallel-regression/coach-cast-build17-final-20260814-205930/summary.txt` | 202件を網羅。旧名称3件と監査1件を検出 |
| `.build/regression/coach-cast-release-targets-20260814-212926.xcresult` | 更新後のAI画面3件成功、監査1件のみ残存 |
| `.build/reports/testflight-preflight.txt` | Build 17 preflight成功 |
| `.build/BodyMode-TestFlight-0.1.0-17.xcarchive` | 署名検証成功、TestFlightアップロード済み |

## 2026-08-15 Wave 2認証・分析変更

認証、利用枠、プライバシー、共通広告表示を横断するため、基準に従いiPhone 1台構成でL3を1回実行した。233件を欠落なく実行し、225件成功、6件失敗、許可スキップ2件だった。

検出した6件のうち、食事UI 3件は遅延生成される数値欄とシート終了を待つようテスト操作を修正し、対象再実行で成功した。Watchチュートリアル2件はUIテスト用リセットを`@AppStorage`へ即時反映し、言語依存のラベル比較を除いて対象再実行で成功した。残る1件はBuild 17から継続しているiOS 26.5の要素特定不能アクセシビリティ監査である。

Wave 2の直接対象である写真推定、匿名送信、同意移行、AI利用枠、オーナー免除、広告設定は対象38件、サーバー32件、Worker 5件が成功した。公開Workerへの匿名イベント登録・削除も実通信で成功した。L3全体の`Gate: FAIL`はアクセシビリティ監査1件が残るため、新しい成功基準点にはしない。

### Build 20 TestFlight配布

- 食事記録画面の時刻入力・時刻表示を削除し、日付表示と内部保存日時を維持した。
- 食事保存UIテスト: 1件成功。
- 署名付きArchive: `.build/BodyMode-TestFlight-20.xcarchive`
- Production preflight: PASS。iPhone、Watch、Widget、Privacy Manifest、広告設定、AI設定、秘密情報検査を確認。
- App Store Connect: Build 20 `VALID`、Friends & Familyへ追加、Beta App Review提出後に`IN_BETA_TESTING`。
- GoogleMobileAdsとUserMessagingPlatformの第三者dSYM不足警告は出たが、アプリ本体のアップロードと処理は成功した。

### Build 22 言語設定・法務フォールバック

- iOSへ44言語を`CFBundleLocalizations`として明示し、Archive内の44個の`.lproj`と一致を確認した。
- 開発言語を`en-US`へ変更し、未対応のOS言語では英語へフォールバックするようにした。日本語は明示ローカライズとして維持する。
- 初回同意、利用規約15節、プライバシーポリシー15節は日本語を維持し、日本語以外では英語を表示する。
- 日本語の同意フローと、未対応言語から英語へフォールバックする同意フローのUIテスト2件に合格した。
- Build 21はアップロードのみで外部グループへ追加せず、修正版Build 22を`VALID`、`IN_BETA_TESTING`まで進めた。

| 証跡 | 結果 |
|---|---|
| `.build/parallel-regression/wave2-20260815/summary.txt` | 233件網羅。225成功、6失敗、2許可skip |
| `.build/regression/wave2-milestones-targeted-20260815.xcresult` | 写真推定・匿名送信・同意移行38件成功 |
| `.build/regression/wave2-watch-tutorial-targeted-20260815.xcresult` | Watchチュートリアル2件成功 |
| `.build/regression/wave2-meals-targeted-20260815.xcresult` | 食事2件成功、MEXT入力1件を追加修正 |
| `.build/regression/wave2-mext-final-20260815.xcresult` | MEXT食品量入力と自動栄養計算成功 |

## 2026-08-21 Build 23 正式候補L3

正式公開候補としてBodyMode専用iPhoneを1台に制限し、単体、スクリーンショット専用を除くiPhone UI、Watch UI、本番設定preflightを一括実行した。初回実行で古い屋外ルート識別子とWatchメニュー順・固定スクロールを検出し、製品のメニュー優先順位とテストを修正して対象テストに合格した後、最終L3を最初から再実行した。

| 領域 | 成功 | 失敗 | スキップ |
|---|---:|---:|---:|
| 単体 | 222 | 0 | 0 |
| iPhone UI | 49 | 0 | 2（固定allowlist） |
| Watch UI | 9 | 0 | 0 |
| 合計 | 280 | 0 | 2 |

iPhoneは期待273件・実行273件、Watchは期待9件・実行9件で、欠落・予定外テスト・想定外skipは0件だった。本番設定preflightも成功し、正式候補ゲートは`PASS`。署名済みArchiveは未指定のため、Distribution署名とPrivacy ReportはArchive作成時の残確認とする。

証跡: `.build/parallel-regression/release-candidate-20260820-final/summary.txt`

Build 23 ArchiveをApp Store Connect APIキーでIPAへ書き出し、iPhone、Watch、WidgetのDistribution署名、`get-task-allow=false`、本番URL・AI・広告設定を検証した。IPA内のアプリ、Watch、Google Mobile Ads、UMPのPrivacy Manifest 4件も構造化集約し、7データ種別と3 Required-Reason APIが固定基準に一致した。

追加証跡:

- `.build/AppStoreExport-23-20260821/GymTrainingApp.ipa`
- `.build/reports/privacy-manifest-audit-build23.md`
- `.build/reports/testflight-preflight.txt`

### 1.0.0 (24) 正式公開候補

Build 23のL3成功後、アプリ動作コードを変更せず、公開versionだけを`1.0.0 (24)`へ更新した。App Store Connect APIキーを使ってArchiveとIPAを作成し、全3バンドルのDistribution署名、`get-task-allow=false`、本番設定、Privacy Manifest基準を再検証した。

- Archive: `.build/BodyMode-AppStore-1.0.0-24.xcarchive`
- IPA: `.build/AppStoreExport-1.0.0-24/GymTrainingApp.ipa`
- Privacy監査: `.build/reports/privacy-manifest-audit-1.0.0-24.md`
- Production preflight: `PASS`
- App Store Connect: Build 24 `VALID`、`Friends & Family`と`Reddit Beta`へ追加、外部Beta App Review待ち
- ストア画像: `1.0.0 (24)`相当のiPhone 8枚を1320x2868、アルファなしで再取得し、コンタクトシートで視認確認
- 画像生成安定化: 写真フローとホーム画像の対象テストを修正し、各対象ケースが成功。通常回帰とは分離して維持

英語圏向けには日本語版と同じ構成のiPhone 8画面を`en-US`で再生成した。英語撮影テスト1件は成功し、8画像すべて1320x2868、アルファなし、日本語残存なしを確認した。スクリーンショットの提出漏れを防ぐため、preflightへ日本語8枚・英語8枚・Watch 3枚の厳密な枚数検査を追加した。

- 英語画像: `docs/app-store/screenshots-en/`
- 連絡シート: `docs/app-store/screenshots-en-contact-sheet.png`
- 対象テスト: `.build/regression/english-store-screenshots-final3-1.0.0-24.xcresult`（1件成功、失敗0）

### 1.0 (25) 英語表示修正版

英語ストア画像の確認で見つけた主要ラベル3点を自然な英語へ修正し、同じ英語撮影テストを再実行した。製品ロジックには変更がないためL3全体は再実行せず、ローカライズ構造検査、英語撮影テスト、本番Releaseビルド、署名済みIPA検査へ限定した。

- ローカライズ検査: 44 release locales、欠落・空値・プレースホルダー不整合0
- 英語撮影テスト: `.build/regression/english-store-screenshots-final3-1.0.0-24.xcresult`、1件成功、失敗0
- Archive: `.build/BodyMode-AppStore-1.0-25-final.xcarchive`
- IPA: `.build/AppStoreExport-1.0-25-final/GymTrainingApp.ipa`
- Privacy監査: `.build/reports/privacy-manifest-audit.md`
- Production preflight: `PASS`
- Watch英語撮影テスト: `.build/WatchEnglishStoreScreenshots-20260821-final2.xcresult`、1件成功、失敗0
- App Store Connect: Build 25は`VALID`、Version 1.0へ選択済み。Build 24の外部Beta App Reviewは維持

## 2026-08-25 Build 33 AIトレーナー共通契約L3

選択したトレーナーの人格、話し方、目的別専門性を、会話、計画、今日の提案、食事、体型写真、週次・月次レポートで共通化した。健康管理、睡眠、回復、活動量、体調、HealthKit傾向を対象に含め、医療診断との境界をサーバー共通契約へ追加した。共通通信モデルと6機能以上へ波及する外部TestFlight更新のため、BodyMode専用iPhoneを1台に制限してL3を実行した。

| 領域 | 成功 | 失敗 | スキップ |
|---|---:|---:|---:|
| 単体 | 239 | 0 | 0 |
| iPhone UI | 50 | 0 | 2（固定allowlist） |
| Watch UI | 10 | 0 | 0 |
| 合計 | 299 | 0 | 2 |

iPhoneは期待291件・実行291件、Watchは期待10件・実行10件で、欠落・予定外テスト・想定外skipは0件だった。バックエンド57件とCloudflare production preflightも成功した。実行時Git SHAは`5de3b38a2800`、作業ツリーはBuild 33配布候補の未コミット変更を含む状態だった。

証跡: `.build/parallel-regression/build33-coach-consistency/summary.txt`
