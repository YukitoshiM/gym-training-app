# BodyMode リリース準備ボード

更新日: 2026-08-13

この文書をリリース準備の正本とする。状態は `完了`、`進行中`、`未着手`、`ブロック` の4種類だけを使う。

## 1. リリース方針

- 初回は日本向けの無料アプリとして公開する。
- アカウント、課金、SNS、コミュニティ、ギフトは初回に入れない。
- iPhoneの共通ルート上部に非パーソナライズバナーを1枠固定し、主要タブと配下画面で継続表示する。Watch・Widget・通知には入れない。
- AIへ送るデータはユーザーが選択し、AIなしでも全ての手動記録を使えるようにする。
- 利用分析に体重、腹囲、写真、食事内容、心拍、睡眠、位置、自由記述を含めない。

## 2. P0: 提出を止める項目

| ID | 状態 | 担当 | 項目 | 完了条件 |
|---|---|---|---|---|
| R-001 | 完了 | Codex | 見やすいUI | 小さい文字を減らし、主要操作を大きな文字・アイコン・44pt以上のタップ領域にする |
| R-002 | 完了 | Codex | 自動アクセシビリティ監査 | 最大アクセシビリティ文字、構造監査、ライト・ダーク、2テーマのコントラスト検査に合格する。実機VoiceOver受入はR-014で行う |
| R-003 | 完了 | Codex | 版管理された法務同意 | 初回起動で利用規約とプライバシーポリシーを確認・同意でき、版を保存する |
| R-004 | 進行中 | 利用者 | 法務文書の確定 | 運営者名、住所または適法な表示方法、連絡先、公開日を確定し、必要に応じ専門家が確認する |
| R-005 | ブロック | 利用者 | 公開URL | Privacy Policy URL、Support URL、利用規約URLをHTTPSで公開する |
| R-006 | 完了 | Codex | 利用分析の同意と設定 | 初期オフ、収集項目の説明、書き出し、削除、いつでも停止を実装する |
| R-007 | 未着手 | 利用者/Codex | 外部分析方式の決定 | 送信先、保存地域、保持期間、委託先、費用を決めてから外部送信を有効化する |
| R-008 | 完了 | Codex | データマッピング | 権限、端末保存、AI送信、分析送信、保持、削除を1表にし、App Privacy回答と一致させる |
| R-009 | 完了 | 利用者 | Apple Developer Program | Personal Teamではなく有料メンバーシップを有効化する |
| R-010 | 完了 | 利用者 | App Store Connectアプリ | Bundle ID、SKU、Health & Fitnessカテゴリ、連絡先を登録する |
| R-011 | 未着手 | 利用者 | App Store申告 | App Privacy、年齢レーティング、規制対象医療機器、輸出、DSA事業者状態を回答する |
| R-012 | 進行中 | Codex/利用者 | Release提出物 | Build 12のアップロード・外部配布は完了。次回候補で必須自動回帰、本番preflight、Distribution署名Archive、Xcode Privacy Reportを確定する |
| R-013 | 進行中 | Codex/利用者 | ストア素材 | 説明文、キーワード、審査メモ、iPhone 6枚、Watch 3枚は完成。運営者情報と公開URLを入れる |
| R-014 | 進行中 | Codex/利用者 | TestFlight受入 | Build 12を外部TestFlightへ配布済み。iPhoneとWatchで主要フローを一周し、外部テスター5〜10人の受入を完了する |
| R-015 | 完了 | Codex | 秘密情報の保護 | AI APIキーをKeychainへ移行し、既存値を安全に移行・削除する |
| R-016 | 完了 | Codex | ローカルデータ保護 | 写真を含む記録を保護ファイルへ移行し、バックアップ対象外と保持方針を適用する |
| R-017 | 完了 | Codex | 診断ログ管理 | 14日・1,000件・2MiBの保持上限、ファイル保護、アプリ内削除を実装する |
| R-018 | 完了 | Codex | 広告の安全な実装 | iPhone共通固定AdMobバナー、60秒再試行、UMP同意、非パーソナライズ、健康データ分離、報告導線を実装する |
| R-019 | ブロック | 利用者 | AdMob本番化 | AdMobアプリ・広告ユニット・Privacy & messagingを作成し、本番IDをGit管理外設定へ入れる |

## 3. P1: 公開直後までに必要な項目

| ID | 状態 | 担当 | 項目 | 完了条件 |
|---|---|---|---|---|
| R-101 | 進行中 | Codex | クラッシュ分析 | MetricKit、端末内ログ、削除・書き出しは完成。TestFlightクラッシュの受信を実機配布後に確認する |
| R-102 | 未着手 | 利用者 | サポート運用 | 問い合わせ用メール、返信目標、障害時の告知方法を決める |
| R-103 | 完了 | Codex | リリースチェック自動化 | `scripts/run_release_candidate_gate.sh`で全単体・iPhone・Watch回帰と本番preflightを連続実行し、失敗・想定外skip・本番設定・任意Archive署名を検査する |
| R-104 | 進行中 | Codex/利用者 | アクセシビリティ表示 | 自動実測は完了。実機VoiceOver受入後にApp Store Connectへ回答する |
| R-105 | 未着手 | 利用者 | KPI運用 | 7日継続、記録日数、主要機能利用率、途中離脱を週次で確認する |

## 4. P2: 初回公開後に判断する項目

| ID | 状態 | 項目 | 判断条件 |
|---|---|---|---|
| R-201 | 保留 | 追加広告フォーマット | バナー1枠のUXと継続率を確認するまで、全画面・リワード・App Open広告は追加しない |
| R-202 | 保留 | SNS・ギフト・コミュニティ | モデレーション、通報、ブロック、年齢対応、運用担当を用意できる |
| R-203 | 保留 | 課金 | 有料価値、復元、解約説明、Paid Apps Agreement、税務情報を準備できる |

## 5. 利用分析の最小仕様

初回TestFlightの利用分析は外部へ送らず、同意した端末内に次のイベントだけを保存する。広告SDKのデータは別系統であり、BodyModeの利用分析イベントや健康記録を広告リクエストに入れない。

| イベント | 記録する情報 |
|---|---|
| `app_opened` | 日時、アプリバージョン |
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

保存上限は90日または1,000件の早い方とする。端末外へ自動送信せず、設定から書き出し・削除できるようにする。

次の情報は分析イベントへ絶対に含めない。

- 体重、腹囲、体脂肪率、目標値
- 写真、料理名、食材、PFC、カロリー
- 種目名、重量、回数、RPE、メモ
- 心拍、睡眠、位置、モーション、生年月、性別
- AIへ送った内容、AIサーバーURL、APIキー
- 氏名、メール、端末広告ID、自由記述

外部送信を追加する場合は、実装前にプライバシーポリシー、App Privacy、同意画面、削除方法、委託先一覧を更新する。

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

## 7. 実施順

1. 利用者がR-004、R-005、R-011、R-019を進め、本番URLと広告IDを確定する。
2. `scripts/run_release_candidate_gate.sh <archive>`を実行し、回帰、本番設定、Distribution署名を1回で確認する。
3. Xcode OrganizerでPrivacy Reportを確認する。
4. iPhone・Watch実機でVoiceOverを含むR-014を行う。
5. 1週間の利用結果で広告の表示体験と外部分析の要否を判断する。

2026年8月3日時点で、iPhone最大アクセシビリティ文字サイズ、主要4画面のXcodeアクセシビリティ監査、ライト・ダーク両テーマのWCAGコントラスト検査に合格。実機VoiceOverの読み上げ順序は内部TestFlight受入で確認する。

## 8. 現在のブロック

- ローカルで実行済みの追加差分回帰は、単体91件、AI UI 5件、Watch UI 7件が失敗0で完了している。強化後のリリース候補ゲートは、本番URLと本番広告IDを設定した候補で改めて実行する。
- Privacy Policy、Terms、SupportのHTTPS URLとサポートメールが未確定。
- App Store ConnectのApp Privacy、年齢レーティング、医療、輸出、DSA等の申告が未確定。
- AdMob本番アプリID、バナーID、Privacy & messagingの公開は利用者の作業が必要。現在のローカルReleaseはGoogle公式デモIDである。
- OrganizerのPrivacy Reportと実機VoiceOver・主要フローを人が確認する。
- 正式な外部公開では、iPhoneのRelease設定をセッショントークンモードに固定し、正の設定versionを付ける。

短命トークン発行、失効、レート制限とiPhone側のKeychainキャッシュは実装・稼働確認済み。既存TestFlight互換のためサーバーは現在`compat`で動かし、全アクティブビルド移行後に`token_required`へ切り替える。

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
| Archive | 指定時は内包する全app/appexがApple Distributionまたは旧iPhone Distribution署名で、`get-task-allow`がfalseまたは不存在 |

回帰summaryはGit SHA、dirty/clean、アプリversion/build、レーン別と合計の件数、許可・想定外skip、所要時間、最終判定を保存する。本番preflightは設定値や署名主体を出力せず、秘密値を含む可能性がある下位preflightの出力もterminalへ流さない。
