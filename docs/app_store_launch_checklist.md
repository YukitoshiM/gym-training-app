# BodyMode App Store正式公開バックログ

> この文書は詳細確認用の旧チェックリストです。現在の状態・担当・実行順は`production_launch_remaining_tasks.md`を正本としてください。

更新日: 2026-08-21
基準ビルド: TestFlight `1.0.0 (24)`（外部Beta App Review待ち） / 正式公開候補 `1.0 (25)`（App Store Connectで`VALID`、Version 1.0へ選択済み）

本書は、日本でのベータ検証から、日本語と43対象ローカリゼーション対応後のグローバル一般公開へ進むための詳細チェックリストである。現在の状態管理は`production_launch_remaining_tasks.md`、ユーザー報告は`testflight_feedback_ledger.md`を正本とする。

## 1. 初回公開の範囲

- 日本でベータ検証後、日本語と43対象ローカリゼーションを整備して、EU27を除く148地域へ無料公開、アカウント不要。保留6言語は英語へフォールバック
- iPhone、Apple Watch、Watch Widget
- 手動記録、HealthKit、トレーニング、食事、身体・写真、AIコーチ
- iPhoneだけに非パーソナライズのAdMobバナー1枠
- AI停止時も手動記録、履歴、Watchを利用可能

初回公開へ入れないもの:

- SNS、コミュニティ、ギフト、ランキング
- サブスクリプション、アプリ内課金
- 全画面、リワード、App Open広告
- 同意なしの外部利用分析送信

これらは正式公開後の利用状況を見るまで無期限保留とする。

## 2. 現在の提出ブロッカー

署名済みIPAの本番preflightで次を確認済み。正式候補Buildでは再実行する。

| ブロッカー | 現在 | 解消条件 |
|---|---|---|
| 公開URL | 解消済み | GitHub Pagesの3つのHTTPS URLを公開し、Release設定と提出原稿へ登録済み |
| AdMob | UMPを含む公開前設定は完了 | App Store公開後のStoreリンクとAdMob審査を完了 |
| 署名 | 解消済み | App Store書き出しIPAでiPhone、Watch、WidgetのApple Distribution署名と`get-task-allow=false`を確認 |
| App Store申告 | 完了 | 年齢4+、輸出免除、コンテンツ権利あり、無料、EU27を除く148地域、App Privacy、医療機器No、DSA非トレーダー申告を確認 |
| ベータ受入 | Build 23 | P0再発なし、AIゲートウェイ・写真・Watch・広告・削除を実機で確認 |
| アクセシビリティ | 実操作領域は48ptへ修正済み | 実機VoiceOver確認。iOS 26.5の対象要素`nil`監査1件を再評価 |

本番preflight証跡:

- Distribution IPA署名: `.build/regression/production-ipa-preflight-build17.log`
- 公開URL・AI・AdMob本番設定: `.build/regression/production-config-after-admob.log` (`PASS`, 2026-08-15)

## 3. Gate A: 利用者の決定・外部設定

ここが終わるまで、正式候補Archiveは確定できない。

| ID | 優先 | 状態 | タスク | 完了条件 |
|---|---:|---|---|---|
| PUB-001 | P0 | 進行中 | 運営者情報を確定 | 規約へ載せる正式名称、連絡先、公開日、必要な表示方法が決まる |
| PUB-002 | P0 | 進行中 | サポート運用を決定 | GitHub Issues受付は開始済み。返信目標と障害告知方法を決める |
| PUB-003 | P0 | 完了 | 法務・サポートページをHTTPS公開 | Privacy Policy、利用規約、Supportの3 URLをGitHub Pagesで公開済み |
| PUB-004 | P0 | 進行中 | AdMobを本番化 | App・Banner ID、支払いプロフィール、`T`上限、カテゴリ制限、Privacy & messagingは完了。公開後のAdMob審査を完了する |
| PUB-005 | P0 | 回答確定・Connect入力待ち | App Privacy回答を確定 | SDK ManifestとAI運用を照合し、AdMob Device IDのみTrackingありとする回答を確定。Connectで入力・Publishする |
| PUB-006 | P0 | 完了 | 年齢レーティングを回答 | Advertisingあり、Health or Wellness Topicsあり、他なしの必須24項目を保存し、4+・未回答0をAPI確認済み |
| PUB-007 | P0 | 完了 | App Store共通申告を確定 | 輸出免除、第三者コンテンツ権利あり、無料、EU27を除く148地域を確認。Account HolderがDSA非トレーダー・EU配信予定なしを保存済み |
| PUB-008 | P0 | 完了 | 公開方式を決定 | 初回は審査承認後に手動でEU27を除く148地域へ公開する。App Store `1.0.x`を安定版、TestFlight `1.1.x beta`を先行版として並行運用する |
| PUB-009 | P1 | 未着手 | 法務原稿を最終確認 | 健康・AI・広告・未成年・免責・準拠法が運営実態と一致する |

## 4. Gate B: Codex側の正式候補準備

外部設定の受領後、こちらでまとめて進める。

| ID | 優先 | 状態 | タスク | 完了条件 |
|---|---:|---|---|---|
| PUB-101 | P0 | 完了 | 本番設定を注入 | Legal用Git管理外xcconfigへ公開URL、Ads用Git管理外xcconfigへAdMob本番IDを設定済み |
| PUB-102 | P0 | 完了 | AI本番運用を確定 | 安定HTTPS、短期トークン、設定version、レート制限、再起動、タイムアウト、監視専用資格情報、公開・ローカル・推論ヘルスを確認 |
| PUB-103 | P0 | 完了 | Distribution署名を検証 | `1.0 (25)` ArchiveをAPIキーでIPAへ書き出し、iPhone、Watch、WidgetがApple Distribution署名かつ`get-task-allow=false`であることを確認 |
| PUB-104 | P0 | 完了 | App Privacy回答表を作成 | `app_store_connect/app_privacy_answers_ja.md`へSDK 13.7.0 / UMP 3.1.0とAIサーバー監査ログを反映済み |
| PUB-105 | P0 | Manifest自動監査完了・Organizer確認待ち | Xcode Privacy Reportを確認 | `1.0 (25)` IPA内4 Manifestを集約し回答表と一致。Organizerの公式Privacy Reportを保存して最終照合する |
| PUB-106 | P0 | 完了 | ストア文面を最終化 | 日本語・英語の名前、サブタイトル、説明、キーワード、URL、既存アカウントのCopyrightとBeta Review連絡先をApp Store Connectへ反映済み。英語名は重複回避のため`BodyMode: AI Fitness Coach` |
| PUB-107 | P0 | 完了 | スクリーンショットを更新 | 日本語・英語iPhone各8枚、13インチiPad各1枚、Watch各3枚をApp Store Connectへ反映し、API監査で各言語3セット・12枚を確認 |
| PUB-108 | P0 | 完了 | App Review Notesを更新 | アカウント不要、権限任意、Watch任意、AI停止時、広告、削除場所を説明する英語審査メモをApp Store Connectへ反映済み |
| PUB-109 | P0 | 完了 | 公開バージョンを決定 | `1.0 (25)`を採番し、iPhone、Watch、Widgetで一致 |
| PUB-110 | P0 | 完了 | 正式候補ゲートを実行 | Build 23のL3回帰280件成功・失敗0。英語表示3点を対象テストで確認した`1.0 (25)`の本番preflight、Distribution署名済みIPA、Privacy Manifest基準監査も成功 |
| PUB-111 | P1 | 完了 | サポート用診断手順を確定 | 設定から匿名診断の添付、診断なし送信、再試行、本文コピー、ログ削除を利用でき、秘密・健康情報を除外する対象テスト済み |

2026-08-24 0:01 JST、BodyMode 1.0（Build 30）とAIクレジット3商品を1つの提出物としてApp Reviewへ送信した。App Store Connect画面とAPIで4項目、下書き0件、`WAITING_FOR_REVIEW`を確認済み。EU27を除く148地域へ変更し、DSA非トレーダー・EU配信予定なしを保存済み。銀行と米国税務は公開・入金開始前の残件として継続する。

## 5. Gate C: Build 23ベータ受入

コード実装済みでも、次の条件を満たすまでは「確認待ち」とする。

| ID | 優先 | 状態 | テスト | 完了条件 |
|---|---:|---|---|---|
| PUB-201 | P0 | 進行中 | AI 3経路 | チャット、食事写真、体型写真を各3回成功。失敗後の再試行も成功 |
| PUB-202 | P0 | 進行中 | 写真セット保持 | 追加、削除、再編集、保存、再起動後も4方向写真が消えない |
| PUB-203 | P0 | 未着手 | 新規・更新インストール | 新規導入と直前TestFlight Build→23更新の両方で初期設定・保存値移行が成功 |
| PUB-204 | P0 | 未着手 | iPhone主要フロー | 今日の3つ、計画、実績、履歴、食事、身体、コンディションを一周 |
| PUB-205 | P0 | 未着手 | Watch実機 | メニュー転送、種目変更、セット、テンポ触覚、休憩、完了同期を確認 |
| PUB-206 | P0 | 未着手 | HealthKit・通知 | 許可、拒否、データなし、バックグラウンド復帰でクラッシュしない |
| PUB-207 | P0 | 未着手 | 広告・同意 | UMP選択、非パーソナライズ広告、オフライン、再試行、報告導線を確認 |
| PUB-208 | P0 | 未着手 | データ権利 | JSON書き出し、診断ログ削除、全データ削除、再起動後の消去を確認 |
| PUB-209 | P0 | 未着手 | 法務リンク | アプリ内の3ページと外部URLが一致し、オフライン時も原稿を読める |
| PUB-210 | P0 | 進行中 | クラッシュ監視 | 7日間または十分な利用回数でP0/P1クラッシュとデータ損失が0件 |
| PUB-211 | P1 | 未着手 | 実機VoiceOver | 読み上げ順、ボタン名、48pt操作、最大文字、ライト・ダークを確認 |
| PUB-212 | P1 | 進行中 | 外部テスター受入 | 5〜10人が参加し、最低1人がAIコーチの違いと主要操作を説明できる |

## 6. Gate D: App Store Connect提出

| ID | 優先 | 状態 | タスク | 完了条件 |
|---|---:|---|---|---|
| PUB-301 | P0 | 進行中 | App Store商品ページを完成 | 必須メタデータ、URL、画像、Health & Fitnessカテゴリ、著作権、IDFA使用、価格、配信地域を保存。Build 31のATT実装とApp Privacy回答を一致させる |
| PUB-302 | P0 | 未着手 | App Privacyを公開 | 第三者SDKを含む回答をPublishし、商品ページ表示を確認 |
| PUB-303 | P0 | 完了 | 年齢・各種申告を完了 | 年齢、輸出、権利、医療機器No、EU27除外、Account HolderのDSA非トレーダー申告に未回答がない |
| PUB-304 | P0 | 完了 | 正式候補Buildを選択 | `1.0 (25)`をVersionへ紐付け、審査情報を完成 |
| PUB-305 | P0 | 未着手 | 提出前レビュー | アプリ内表示、Store文面、法務、プライバシー、ビルド番号を相互確認 |
| PUB-306 | P0 | 未着手 | App Reviewへ提出 | Add for Review後、Draft SubmissionからSubmit for Reviewを実行 |
| PUB-307 | P0 | 未着手 | 審査応答 | 質問・リジェクトを記録し、必要なら修正版を提出 |
| PUB-308 | P0 | 未着手 | 一般公開 | 承認後、PUB-008で決めた方式でEU27を除く148地域へ公開する |

## 7. Gate E: 公開後7日

- クラッシュ、AI失敗、広告、問い合わせを毎日確認する。
- 公開24時間後と7日後に、インストール、今日の1件以上完了率、記録成功率を確認する。
- AIサーバーの稼働、応答時間、401・413・503・タイムアウトを確認する。
- プライバシー、SDK、データ送信が変わった場合はApp Privacyと公開文書を同時更新する。
- SNS、課金、追加広告は、この期間の結果だけでは追加しない。継続率と要望が十分に集まってから別判断する。

## 8. 次に進める順番

1. 利用者: PUB-001〜008の決定と外部設定
2. Codex: PUB-101〜110の本番候補作成
3. 共同: PUB-201〜212をBuild 23で受入
4. Codex: `1.0.0`候補Archiveと提出物の最終検査
5. 利用者: App Store Connect申告を確認し、審査提出

## 9. Apple公式確認先

- App提出: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- 年齢レーティング: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- 必須メタデータ: https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
