# BodyMode リリース準備ボード

更新日: 2026-08-23

この文書は完了済みの実装履歴とリリース基準を保持する。本番提出・公開・初期運用の現在の残タスクは `production_launch_remaining_tasks.md` を正本とする。フィードバックを含む実装履歴は `beta_release_implementation_backlog.md`を参照する。

## 1. リリース方針

- 初回正式版から、日本語と43対象ローカリゼーションの公開ゲートを満たしたうえで、App StoreとAdMobで許可される全ての国・地域へ同時に無料公開する。国別の段階配信は行わない。保留6言語は英語へフォールバックする。
- 集客先を事前に一地域へ限定せず、公開後の国・言語別インストール、継続率、主要行動完了率、AI成功率、広告収益から需要の強い市場を特定する。
- アカウント、課金、SNS、コミュニティ、ギフトは初回に入れない。
- iPhoneの共通ルート上部に非パーソナライズバナーを1枠固定する。トレーニング中、入力中、撮影中、Watchライブ管理、Watch、Widget、通知には入れない。
- AIへ送るデータはユーザーが選択し、AIなしでも全ての手動記録を使えるようにする。
- 利用分析に体重、腹囲、写真、食事内容、心拍、睡眠、位置、自由記述を含めない。

## 2. P0: 提出を止める項目

| ID | 状態 | 担当 | 項目 | 完了条件 |
|---|---|---|---|---|
| R-001 | 完了 | Codex | 見やすいUI | 小さい文字を減らし、主要操作を大きな文字・アイコン・44pt以上のタップ領域にする |
| R-002 | 進行中 | Codex | 自動アクセシビリティ監査 | 実操作領域は48pt以上へ修正済み。iOS 26.5が対象要素`nil`のSwiftUI内部ノードを1件報告するため、実機VoiceOverと次回Xcodeで再確認する |
| R-003 | 完了 | Codex | 版管理された法務同意 | 初回起動で利用規約とプライバシーポリシーを確認・同意でき、版を保存する |
| R-004 | 進行中 | 利用者 | 法務文書の確定 | 運営者名、住所または適法な表示方法、連絡先、公開日を確定し、必要に応じ専門家が確認する |
| R-005 | 完了 | Codex | 公開URL | GitHub PagesでPrivacy Policy、Support、利用規約のHTTPS URLを公開する |
| R-006 | 完了 | Codex | 利用分析の同意と設定 | 初期オフ、収集項目の説明、書き出し、削除、いつでも停止を実装する |
| R-007 | 完了 | Codex | 外部分析方式の決定 | 明示同意した匿名イベントだけをBodyMode AIサーバーへ送り、Mac miniのSQLiteに最大90日保持し、アプリから本人分を削除できる |
| R-008 | 完了 | Codex | データマッピング | 権限、端末保存、AI送信、分析送信、保持、削除を1表にし、App Privacy回答と一致させる |
| R-009 | 完了 | 利用者 | Apple Developer Program | Personal Teamではなく有料メンバーシップを有効化する |
| R-010 | 完了 | 利用者 | App Store Connectアプリ | Bundle ID、SKU、Health & Fitnessカテゴリ、連絡先を登録する |
| R-011 | 進行中 | Codex/利用者 | App Store申告 | Health & Fitnessカテゴリ、IDFA使用、年齢4+、輸出免除、コンテンツ権利あり、無料、全175地域は反映済み。App Privacy回答はDevice IDのみTrackingありで確定し、Build 31では広告SDK起動前にATTを要求する。ConnectでのApp Privacy公開と最終申告確認が残る |
| R-012 | 進行中 | Codex/利用者 | Release提出物 | `1.0 (25)`のArchive・IPA、全バンドルのDistribution署名、中立AI URL、AdMob本番ID、Privacy Manifest自動監査はPASS。Organizerの公式Privacy Reportと正式候補の実機受入が残る |
| R-013 | 完了 | Codex | ストア素材 | 日本語・英語の説明文、審査メモ、公開URL、iPhone各8枚・Watch各3枚、既存アカウントのCopyrightとBeta Review連絡先をApp Store Connectへ反映し、API監査で欠落0を確認 |
| R-014 | 進行中 | Codex/利用者 | TestFlight受入 | Build 23を外部TestFlightへ配布済み。フィードバック47件とクラッシュ提出2件を全件台帳化し、新規未整理0件。iPhoneとWatchで主要フローとAI 3経路を確認する |
| R-015 | 完了 | Codex | 秘密情報の保護 | AI APIキーをKeychainへ移行し、既存値を安全に移行・削除する |
| R-016 | 完了 | Codex | ローカルデータ保護 | 写真を含む記録を保護ファイルへ移行し、バックアップ対象外と保持方針を適用する |
| R-017 | 完了 | Codex | 診断ログ管理 | 14日・1,000件・2MiBの保持上限、ファイル保護、アプリ内削除を実装する |
| R-018 | 完了 | Codex | 広告の安全な実装 | iPhone共通固定AdMobバナー、60秒再試行、UMP同意、非パーソナライズ、健康データ分離、報告導線を実装する |
| R-019 | 進行中 | Codex/利用者 | AdMob本番化 | 公開前設定は完了。App Store公開後にStoreリンクとAdMob審査を完了する |
| R-020 | 完了（法務レビュー除く） | Codex | 多言語化基盤 | 日本語正本2,333件と43翻訳言語をString Catalogへ実装し、明示キー欠落、空値、プレースホルダー、英語フォールバックを検査済み。地域別単位・日時・数値表示、AI言語指定も接続した。法務本文の人手レビューはR-011、保留6言語は公開対象外とする |
| R-021 | 英語圏準備済み・全言語レビュー待ち | Codex/利用者 | 全地域一斉配信 | 日本語・英語の法務、サポート、ストア素材は公開可能。残る対象言語の法務・ストア文面レビューと地域別同意確認後、許可される全てのApp Store地域を同時に有効化する |
| R-022 | 完了 | Codex | AI接続先の秘匿 | 中立な`workers.dev` URLへ切替済み。Mac miniはWorker共有秘密を必須とし、監視専用の短期トークン資格情報でWorker経由、ローカル認証、推論準備を確認した |
| R-023 | 完了 | Codex | AI公平利用枠 | 機能別の日次・期間上限、SQLite永続台帳、成功時確定、構造化された制限・混雑表示、リクエストID冪等化を実装した。App Storeは通常枠、TestFlightは2倍枠、ownerだけ利用枠免除。手動機能は制限対象外 |
| R-024 | 完了 | Codex | オーナー専用AI無制限 | 一般配布キーと分離した失効可能なオーナー登録キーを作成し、`owner` subjectだけ日次・期間上限を免除した。短時間レート制限、同時実行数、待機タイムアウトは維持する |
| R-025 | 完了 | Codex | トレーニング中の広告除外 | iPhoneセッションの全画面表示に加え、Watchライブ管理中は共通固定バナーを非表示にし、終了後に復帰する |
| R-026 | 完了 | Codex | 公開KPIの匿名集計 | 明示同意した利用者から健康値・本文・写真・位置・広告IDを含まないイベントだけを送信し、D1/D7/D30、DailyAction完了とNorth Starを集計する。端末・サーバー双方から削除できる |

## 3. P1: 公開直後までに必要な項目

| ID | 状態 | 担当 | 項目 | 完了条件 |
|---|---|---|---|---|
| R-101 | 完了 | Codex | クラッシュ分析 | MetricKit、端末内ログ、削除・書き出しを実装。Build 13は通知計測、Build 15はAI回答評価のwatchdogデッドロックと特定し、修正・再現テスト済み。2026-08-20取得で新規クラッシュ提出0件 |
| R-102 | 進行中 | 利用者 | サポート運用 | GitHub Issues受付は開始済み。返信目標と障害時の告知方法を決める |
| R-103 | 完了 | Codex | リリースチェック自動化 | `scripts/run_release_candidate_gate.sh`で全単体・iPhone・Watch回帰と本番preflightを連続実行し、失敗・想定外skip・本番設定・任意の書き出しIPA署名を検査する |
| R-104 | 進行中 | Codex/利用者 | アクセシビリティ表示 | 自動実測は完了。実機VoiceOver受入後にApp Store Connectへ回答する |
| R-105 | 完了（基盤） | Codex | KPI運用 | 匿名台帳からD1/D7/D30、アクティブ日、初回設定、初回運動、DailyAction、North Starを1コマンドで集計できる。公開後の週次確認は利用者が行う |
| R-106 | 完了（基盤） | Codex | 収益・AI運用評価 | AdMob収益の手動入力、AI成功・失敗・処理時間、運用費を個人単位で結合せず比較する週次レポートを追加した |
| R-107 | 完了 | Codex | AI運用指標の補完 | 機能別の成功・失敗・上限到達・p95時間を本文なしで集計し、週次レポートを1コマンドで出せる |
| R-108 | 完了 | Codex | `app-ads.txt`公開 | `https://yukitoshim.github.io/app-ads.txt`へHTTPS公開し、HTTP 200と指定内容の完全一致を確認した |

## 4. P2: 初回公開後に判断する項目

| ID | 状態 | 項目 | 判断条件 |
|---|---|---|---|
| R-201 | 保留 | 追加広告フォーマット | バナー1枠のUXと継続率を確認するまで、全画面・リワード・App Open広告は追加しない |
| R-202 | 保留 | SNS・ギフト・コミュニティ | モデレーション、通報、ブロック、年齢対応、運用担当を用意できる |
| R-203 | 保留 | 課金・有料AI枠 | 正式公開後30日以上の利用実績、AI負荷、広告収益、支払意思を確認し、有料価値、復元、解約説明、Paid Apps Agreement、税務情報を準備できる |

## 5. 利用分析の最小仕様

利用分析は初期オフとし、更新後に明示同意した端末だけ、次の粗いイベントをBodyMode AIサーバーへ送る。以前の「端末内のみ」への同意は外部送信へ引き継がない。広告SDKのデータは別系統であり、BodyModeの利用分析イベントや健康記録を広告リクエストに入れない。

| イベント | 記録する情報 |
|---|---|
| `app_opened` | 日時、アプリバージョン |
| `initial_setup_completed` | 初回設定が完了済みという事実だけ |
| `first_workout_completed` | 1回以上の運動が完了した事実だけ |
| `tab_selected` | 固定されたタブID |
| `plan_saved` | 成功した事実だけ |
| `workout_completed` | 完了した事実だけ |
| `body_metric_saved` | 種類だけ。数値は保存しない |
| `meal_saved` | 保存した事実だけ。料理名・栄養値は保存しない |
| `body_photo_saved` | 保存した事実だけ。画像・角度・解析値は保存しない |
| `coach_recommendation_accepted` | 推薦した専門タイプを選んだ事実と専門タイプIDだけ |
| `coach_selection_changed` | 人物・専門性・話し方のどの分類を変更したかだけ |
| `coach_response_helpful` | AI回答が役立ったという評価と専門タイプIDだけ |
| `coach_response_needs_improvement` | AI回答に改善が必要という評価と専門タイプIDだけ |

端末側は90日または1,000件の早い方、サーバー側は最大90日とする。設定から端末内の書き出し、端末内とサーバー上の本人分の削除、以後の送信停止ができる。

次の情報は分析イベントへ絶対に含めない。

- 体重、腹囲、体脂肪率、目標値
- 写真、料理名、食材、PFC、カロリー
- 種目名、重量、回数、RPE、メモ
- 心拍、睡眠、位置、モーション、生年月、性別
- AIへ送った内容、AIサーバーURL、APIキー
- 氏名、メール、端末広告ID、自由記述

送信先はCloudflare Worker経由のBodyMode AIサーバーで、イベント本文はMac miniのSQLiteに保持する。Cloudflareを保存先として使用しない。

## 6. 法務文書の残作業

現在の原稿は健康・AI・HealthKit・端末保存・削除を説明している。正式公開前に次を確定する。

- 運営者の正式名称と問い合わせ先
- 公開URLと改定履歴
- 利用分析の取得項目、利用目的、保持期間、外部送信の有無
- Google AdMobの本番設定、同意メッセージ、送信項目、サポートの報告受付方法
- 未成年者の利用条件
- 免責条項が日本の消費者契約法などに反しないこと
- 独自利用規約をApp Store ConnectのCustom EULAに設定するか、Apple標準EULAと併用するか

法務原稿は製品仕様の記録であり、個別の法的助言ではない。正式公開前に事業形態と配信地域に応じて専門家へ確認する。

## 7. 残タスク実施計画

### Wave 1: コードだけで完了する公開前修正

状態: **完了**

1. `R-023`: TestFlight専用のAI無制限分岐を撤去し、全配布版で通常制限を常時有効化する。
2. `R-024`: オーナー専用登録キー、利用枠免除、失効・再発行を実装する。
3. `R-025`: iPhoneセッションとWatchライブ管理中の広告を除外する。
4. `R-107`: AIの失敗・上限到達・混雑拒否を週次集計へ追加する。

このWaveは変更箇所の単体・API・対象UIテストだけを行い、全回帰はまだ実施しない。

### Wave 2: 公開後の判断材料を取れる状態にする

状態: **コード・サーバー配備、`app-ads.txt`公開完了**。AdMob管理画面への認証反映にはクロール待ち時間が発生する場合がある。

1. `R-007`と`R-026`: 匿名分析の送信先、保存地域、保持期間、削除方法を決め、同意済み端末だけ外部送信する。
2. `R-105`: D1/D7/D30、DailyAction、初回設定・初回運動、AI提案行動率の週次集計を用意する。
3. `R-106`: AdMob収益、AI負荷、月間実費を個人単位で結合せず比較する。
4. `R-108`: 完了。Developer Websiteと同一ホストのルートへ`app-ads.txt`を公開した。

匿名分析は更新後の明示同意だけを有効とし、以前の端末内分析への同意は引き継がない。プライバシーポリシー、データ台帳、App Privacy回答案を同じ仕様へ更新済み。

### Wave 3: 利用者判断と公開情報

1. `R-004`、`R-102`: 運営者名、問い合わせ先、返信目標、障害告知方法を確定する。
2. `R-011`: App PrivacyをConnectへ入力・Publishし、医療機器画面とAccount HolderのDSA Trader情報を完了する。
3. `R-013`: 12人のコーチと現行UIを使ったストア素材を確定する。
4. `BR-405`: 対象言語話者または専門家による法務・健康表現レビューを完了する。
5. 公開方式は全地域同時・手動公開、正式版`1.0.0`候補として確定する。

### Wave 4: 実機受入と正式候補ゲート

1. `BR-004`、`BR-005`: 写真セット保持とAI主要3経路を実機確認する。
2. 新規インストール、更新インストール、iPhone主要フロー、Watch、HealthKit、通知、広告同意、データ削除、法務リンク、VoiceOverを確認する。
3. Xcode OrganizerのPrivacy ReportとApp Privacy回答を照合する。
4. ここで初めて`./scripts/run_release_candidate_gate.sh <exported.ipa>`によるL3全回帰、production preflight、Distribution署名確認を1回実行する。

### Wave 5: 提出と公開

1. App Store商品ページ、審査メモ、公開URL、正式候補Buildを完成させる。
2. App Reviewへ提出し、質問・リジェクトを台帳へ残して対応する。
3. 承認後、許可される全地域へ手動公開する。
4. 公開後30日間は固定バナーと通常AI制限だけで運用し、実データからProと動画広告の要否を判断する。

過去の主要画面監査とコントラスト検査は合格済み。Build 17では実操作領域を48ptへ修正したが、iOS 26.5が対象要素を返さない監査1件が残るため、実機VoiceOverの読み上げ順序と合わせて受入確認する。

## 8. 現在のブロック

- Build 23は外部TestFlightで`IN_BETA_TESTING`。対象要素`nil`のアクセシビリティ監査1件と主要フローを実機で確認する。
- Privacy Policy、Terms、SupportのHTTPS URLは公開済み。GitHub Issuesを一次受付とし、返信目標と障害告知方法を決める。
- App Store ConnectのApp Privacy公開、医療機器画面、Account HolderのDSA申告が未完了。年齢、輸出、権利、価格、地域は完了済み。
- AdMob本番アプリID、バナーID、支払いプロフィール、広告制限、Privacy & messagingは設定済み。App Store公開後のStoreリンクとAdMob審査が残る。
- 書き出しIPAのDistribution署名と最新の本番preflightは確認済み。OrganizerのPrivacy Report、実機VoiceOver・主要フローを確認する。
- 正式な外部公開では、iPhoneのRelease設定をセッショントークンモードに固定し、正の設定versionとCloudflare Worker URLを付ける。
- Cloudflare Workerは中立URLへ配備済み。Mac miniのゲートウェイ専用モードも有効で、直接ホスト経由の`/v1/*`は拒否する。監視専用資格情報による公開・ローカル・推論ヘルスは2026-08-20に成功した。
- AI公平利用枠は全配布版で有効化済み。失効可能なオーナー専用登録キーの`owner` subjectだけ日次・期間上限を免除し、短時間レート制限と同時実行制御は維持する。

短命トークン発行、失効、レート制限とiPhone側のKeychainキャッシュは実装・稼働確認済み。サーバーはゲートウェイ専用かつ短期トークン必須で稼働し、監視も旧共有キーではなく専用登録キーを使う。

## 9. 公式確認先

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
- Privacy Manifest: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- 個人情報保護委員会: https://www.ppc.go.jp/

## 10. 2026-08-03 回帰基準

- iPhone: Reducer単体テスト3本、機能別UIテスト27本、合計30/30成功
- Apple Watch: 通常UIテスト3本、参照スクリーンショットテスト3本、合計6/6成功
- `scripts/testflight_preflight.sh`: 全8段階成功
- Development署名Archive: `.build/BodyMode-Refactor-20260803.xcarchive`作成成功
- Archive内のiPhone、Watch、Watch Widget埋め込みを確認済み

テストとコードの参照先は`docs/feature_map.md`、責務と依存方向は`docs/architecture.md`を正とする。

## 11. リリース候補ゲート

全回帰を実行するかは`docs/regression_testing_policy.md`を正とする。通常のTestFlight更新は変更リスクに応じてL1〜L3を選び、App Store正式公開候補と同文書の強制条件に該当する変更はL3を必須とする。

通常の候補確認は次の1コマンドで行う。

```bash
./scripts/run_release_candidate_gate.sh
```

Distribution Archiveを作成済みの場合は、そのpathを渡す。

```bash
./scripts/run_release_candidate_gate.sh .build/BodyMode.xcarchive
```

このコマンドは次を順に実行し、export、upload、TestFlight配布は行わない。

| ゲート | 必須条件 |
|---|---|
| 回帰 | 単体全件、スクリーンショット専用クラスを除くiPhone UI全件、Watch UI全件が失敗0 |
| skip | ペアリング済みWatch転送と任意のGoogle広告実通信だけを固定allowlistで許可 |
| スクリーンショット | iPhone/Watchの参照画像生成クラスは明示的に非ゲート。誤って通常結果へ混入した場合は失敗 |
| URL | AI、Privacy Policy、Terms、Supportが空でない絶対HTTPS URL |
| AI | 設定versionが正の整数で、セッショントークンモードが有効 |
| 広告 | App IDとBanner IDが有効形式で、GoogleデモID・example placeholderではない |
| 書き出しIPA | 指定時は内包する全app/appexがApple Distributionまたは旧iPhone Distribution署名で、`get-task-allow`がfalseまたは不存在 |

回帰summaryはGit SHA、dirty/clean、アプリversion/build、レーン別と合計の件数、許可・想定外skip、所要時間、最終判定を保存する。本番preflightは設定値や署名主体を出力せず、秘密値を含む可能性がある下位preflightの出力もterminalへ流さない。

2026-08-21にBuild 23の正式候補ゲートをiPhone 1台構成で実行し、単体・iPhone UI・Watch UIの280件が成功、失敗0、固定allowlistのskip 2件で`Gate: PASS`となった。その後、英語表示の対象修正と撮影テスト1件を成功させ、`1.0 (25)`のArchiveとIPAを作成した。全3バンドルのDistribution署名、`get-task-allow=false`、本番設定preflight、4 Privacy Manifestの基準監査も成功した。Xcode Organizerの公式Privacy Reportは提出操作時に保存する。
