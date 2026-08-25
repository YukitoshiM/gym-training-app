# BodyMode 本番公開までの残タスク

更新日: 2026-08-24

この文書を、本番提出、審査、公開直後の残タスクに関する正本とする。完了済みの実装履歴は`release_readiness_plan.md`、TestFlight報告は`testflight_feedback_ledger.md`を参照する。

## 1. 現在地

| 領域 | 現在 | 根拠 |
|---|---|---|
| iPhone / Watch | Build 31審査修正版を準備中 | Build 30は却下。Build 31へATTと常設HealthKit説明を追加し、対象テスト6件と44言語検証がPASS |
| Cloudflare本番 | 稼働中 | Worker、D1 schema 5、Vectorize 2,844件、認証、クレジット、購入、広告報酬、RAGの本番preflightがPASS |
| OpenAI本番 | 開通済み | `gpt-5.6-luna`で食事テキスト・画像、体型写真、計画、日次提案、週次レポートが6/6成功。4,119 input / 1,858 output tokens |
| AI利用ログ | 修正・本番配備済み | 無制限ownerもクレジットを消費せず、成功・失敗・トークン数・処理時間を記録する。Gateway 49テスト成功 |
| Cloudflare staging | 任意の開発環境 | `OPENAI_API_KEY`だけ未登録。本番申請版はproduction Workerを使うため提出を妨げない |
| 公開法務ページ | 同期済み | Privacy、Terms、Supportの日英6ページを8月23日版へ公開し、自動検査PASS |
| App Store商品ページ | 却下対応中 | Build 30はATT未要求、IAP購入エラー、HealthKit UI説明不足の3件で却下。Build 31でアプリ側2件を修正済み |
| AIクレジット商品 | 契約ブロック | 50 / 150 / 500クレジットの商品は、Paid Apps Agreementが銀行・税務情報待ちのため購入できず却下 |

## 2. 残件サマリー

| 区分 | グループ数 | 主な内容 |
|---|---:|---|
| P0 提出前必須 | 10 | AI残経路、法務同期、Apple申告、対応言語、候補Build、実機受入、最終ゲート、提出 |
| P1 審査中 | 3 | 翻訳品質、運用体制、審査対応 |
| P2 公開後 | 4 | AdMob審査、初動監視、KPI・採算評価、EU再評価 |

## 3. P0 提出前必須

| 順番 | ID | 状態 | 担当 | 残タスク | 完了条件 |
|---:|---|---|---|---|---|
| 1 | P0-01 | 公開後対応可 | 利用者 + Codex | staging専用OpenAIキーを登録する | staging healthでproviderの設定、認証、到達性がすべてPASS |
| 2 | P0-02 | 完了 | Codex | 本番AI生成経路を確認する | 本番6経路が成功し、成功時のトークン利用記録がD1へ残る |
| 3 | P0-03 | 完了 | Codex | 日英6法務ページを現行原稿へ同期して公開する | `release_prerequisites.sh`がCloudflareと公開ページの両方でPASS |
| 4 | P0-04 | ブロック | 利用者 | Paid Apps Agreementを有効化する | App Store Connectで銀行口座と米国税務を完了し、`ユーザ情報を保留中`が消えて契約が有効になる |
| 5 | P0-05 | Build 31再確認待ち | Codex | App PrivacyとATTを一致させる | Device ID Tracking=`はい`を維持し、Build 31のATT利用目的、Privacy Manifest、公開法務文面を照合する |
| 6 | P0-06 | 完了 | Codex | 対応言語を最新Archiveと申請物で照合する | 商品ページは日英2言語、アプリ本体は日本語を含む44言語、未対応6言語は英語フォールバック。iPhone・Watch・WidgetのArchive監査がPASS |
| 7 | P0-07 | 準備中 | Codex | Build 31をArchive、Upload、Version 1.0へ選択する | ATT、HealthKit UI、体型写真送信修正を含むBuild 31をUploadし、Version 1.0へ選択する |
| 8 | P0-08 | 未実施 | 利用者 + Codex | 最新候補を実機受入する | 下記の実機受入表がすべてPASS |
| 9 | P0-09 | Build 31待ち | Codex + 利用者 | 正式候補ゲートを1回実行する | 契約有効化後、Build 31でProduction preflight、44言語、Distribution署名、ATT、Privacy Manifest監査がPASS |
| 10 | P0-10 | 再提出待ち | 利用者 + Codex | Version 1.0と3 IAPを再提出する | Build 31、3 IAP、更新した審査メモを同じ提出物へ追加し、`WAITING_FOR_REVIEW`を確認する |

### P0-08 実機受入

| グループ | 確認内容 |
|---|---|
| アカウント・収益 | Sign in with Apple、初回クレジット、Sandbox購入、重複・保留・返金、報酬広告SSV、AI消費、アカウント削除 |
| AI | チャット、食事画像、体型写真、計画作成・見直し、週次レポート。エラー後の再試行と写真推定値の保存も確認 |
| iPhone | 新規・更新インストール、今日の3つ、計画、実績、履歴、食事、身体、写真セット保持、コンディション、データ書き出し・削除 |
| Apple Watch | 計画転送、目標重量、種目変更、セット、テンポ触覚、休憩、完了同期、再開、チュートリアル |
| Health・OS | HealthKit許可・拒否・データなし、睡眠日付、通知、バックグラウンド復帰、ライト・ダーク、最大文字、VoiceOver |
| 広告・法務 | UMP、バナー、報酬広告、オフライン再試行、広告報告、アプリ内日英文面と公開URLの一致 |
| 安定性 | P0/P1クラッシュ、フリーズ、記録消失が0件。既知のAI・写真・計画問題が再発しない |

## 4. P1 審査中に行う

| ID | 担当 | タスク | 完了条件 |
|---|---|---|---|
| P1-01 | 利用者 + Codex | 主要市場の翻訳品質を確認する | 法務、健康、AI、課金の重要文言を優先し、未確認言語は英語フォールバックへ戻せる |
| P1-02 | 利用者 | サポート運用を確定する | GitHub Issuesの返信目標、障害告知、返金・クレジット補正の判断者を明示する |
| P1-03 | Codex + 利用者 | 審査・TestFlightを監視する | 最新候補で新規重大クラッシュ0、Appleの質問・リジェクトを台帳化して回答する |

## 5. P2 公開直後

| ID | 担当 | タスク | 完了条件 |
|---|---|---|---|
| P2-01 | 利用者 + Codex | AdMobを公開Storeへ接続する | Store URL登録、AdMob審査、`app-ads.txt`認証、支払い受取設定を完了する |
| P2-02 | Codex | 24時間・7日監視を行う | AI成功率・p95・原価、購入、広告報酬、クラッシュ、サポートURLに異常がない |
| P2-03 | 利用者 + Codex | 7日・30日で需要と採算を評価する | D1/D7/D30、DailyAction、AI利用、購入率、広告収益、AI原価、国別指標から次の投資を決める |
| P2-04 | 利用者 + Codex | EU配信を再評価する | 収益で専用の事業者住所・電話・メールを維持できる段階だけ、DSA Trader対応とEU27追加を再検討する |

## 6. Codexだけで先行できる作業

1. 公開法務6ページを同期し、公開前提ゲートをPASSさせる。
2. 本番の残りAI生成smokeを最小回数で実施し、トークンと費用を記録する。
3. 最新ArchiveでiPhone・Watch・Widgetの44言語宣言と英語フォールバックを監査する。
4. Apple側の手動申告が終わり次第、最新BuildのArchive、Upload、選択を行う。
5. 実機受入後に正式候補ゲートを一度だけ実行する。

## 7. 利用者の操作が必要な作業

1. [App Store Connectの契約・税務・口座](https://appstoreconnect.apple.com/business)で銀行口座と米国税務を入力し、Paid Apps Agreementを有効化する。IAP審査前の必須ブロッカーであり、機密情報なので利用者本人が操作する。
2. 実機でApple購入、Watch、HealthKit、VoiceOverを操作する。Codexはログ取得と判定を担当する。
3. 主要市場の法務・健康・課金翻訳を確認する。
4. stagingを継続利用する場合のみ、専用OpenAIキーを発行する。

## 8. 今回の公開対象外

次は正式公開後の反応を見るまで期限を設けず保留する。

- SNS直接連携、アプリ内コミュニティ、ギフト
- ゲーミフィケーションのマップ、ボス、報酬
- サブスクリプション
- 全画面動画広告、App Open広告、高頻度広告
- スポンサー、アフィリエイト、法人プラン
- Garmin、スマート体重計、トレーナーマッチング
- AI動画フォーム解析、医療診断
- EU27でのApp Store配信（専用の事業者連絡先を維持できる収益段階まで保留）

## 9. 次の一手

まず銀行口座と米国税務を完了し、Paid Apps Agreementを有効化する。その後、CodexがBuild 31の正式候補ゲート、Archive、Upload、審査メモ反映を行い、Version 1.0と3 IAPを同じ提出物で再申請する。
