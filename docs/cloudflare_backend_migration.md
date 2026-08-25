# BodyMode Cloudflareバックエンド移行

更新日: 2026-08-22

## 1. 目的

一般公開版のAI機能からMac miniの稼働依存をなくす。iPhoneとApple Watchは現在の`/v1/*`契約を維持し、Cloudflare側の機能フラグでAPI単位に移行する。

移行中も次を守る。

- 記録、写真、会話はローカルファーストとする。
- AIクレジットを予約してから外部AIを呼び、失敗時は返却する。
- 写真、健康値、会話本文をアクセスログや分析DBへ保存しない。
- Mac miniへ戻せる経路は移行確認中だけ保持し、アプリには直接URLを含めない。
- 栄養値はAIの推定を正本にせず、食品成分DBから決定的に計算する。

## 2. 配置方針

| 機能 | 現在 | 移行先 | 方針 |
|---|---|---|---|
| 公開API、許可ルート、サイズ制限 | Cloudflare Worker | Cloudflare Worker | 維持・拡張 |
| Luna呼び出し | 未実装 | WorkerからOpenAI Responses API | 移行する |
| 食事画像の料理・量推定 | Mac mini CalorieCLIP/Ollama | Luna Vision | 移行する |
| 食品リストの構造化 | Mac mini Ollama | Luna | 移行する |
| 体型写真コメント | Mac mini Ollama | Luna Vision | 移行する |
| AIチャット、計画、週次・月次レポート | Mac mini Ollama | Luna | 移行する |
| Apple認証、短命トークン、失効 | Mac mini | Worker + D1 | 段階移行する |
| AIクレジット、購入、広告報酬 | Mac mini SQLite | Worker + D1 | 台帳移行後に切替 |
| 匿名利用分析 | Mac mini SQLite | Worker + D1 | 本文を含めず移行 |
| 論文メタデータ | Mac mini SQLite | D1 | 移行する |
| 論文ベクトル検索 | Mac mini sqlite-vec | Vectorize | 検索評価後に移行 |
| 多言語埋め込み | Mac mini Ollama bge-m3 | Workers AI bge-m3 | 移行する |
| 日本食品標準成分表2,538食品 | iPhone同梱 | iPhone同梱 | 移行しない |
| 栄養値の計算 | iPhone | iPhone | 移行しない |
| ユーザー登録バーコード商品 | iPhone | iPhone | 初期公開では移行しない |
| 世界向け公開食品カタログ | 未実装 | D1、必要ならR2 | 新設する |
| HealthKit、運動、身体、食事の記録 | iPhone | iPhone | 移行しない |

## 3. Mac miniに残すもの

Mac miniは本番リクエストの必須経路にしない。次のオフライン・運用処理に限定する。

- Europe PMC等からの論文収集、ライセンス確認、重複排除
- RAG評価セットの実行と検索品質比較
- D1、Vectorizeへ投入する成果物の生成と検証
- CalorieCLIPとOllamaによるモデル比較、回帰評価
- Cloudflare障害時の開発用互換API
- ローカルバックアップと運用レポート生成

Mac mini停止中でも、アプリの手動記録、食品DB計算、Cloudflare経由のLuna、既に同期済みのRAGが動く状態を完了条件とする。

## 4. 目標構成

```text
iPhone / Apple Watch
  -> Cloudflare Worker
       -> Apple認証 / レート制限
       -> D1 認証・クレジット・冪等性・食品・論文メタデータ
       -> Workers AI bge-m3 -> Vectorize
       -> OpenAI Responses API -> gpt-5.6-luna

Mac mini
  -> 論文収集・評価・索引成果物
  -> D1 / Vectorizeへ定期同期
```

## 5. データ境界

### D1へ保存する

- 復元不能なアカウントキー
- トークン失効IDと期限
- AIクレジットの付与、予約、消費、返却履歴
- StoreKit取引ID、AdMob取引IDと冪等性状態
- AI機能種別、所要時間、トークン数、成功・失敗コード
- 公開食品カタログと出典・版
- 論文メタデータ、チャンクID、引用情報
- 同意済み匿名イベント

### 保存しない

- 食事・体型写真の画像本体
- 会話本文、自由記述、AI回答本文
- 体重、腹囲、心拍、睡眠、位置
- ユーザーの食事・運動履歴
- OpenAI APIキーやApple秘密鍵の平文

## 6. 段階移行

| Wave | 内容 | 切替条件 |
|---|---|---|
| C0 | Worker分割、D1スキーマ、Luna Provider | 単体テスト成功。公開動作は変えない |
| C1 | ステージングD1、秘密情報、Cloudflare health | 秘密値が応答・ログへ出ない |
| C2 | 認証・クレジット台帳の複製と照合 | Mac mini台帳との残高差ゼロ |
| C3 | 食事画像・食品リストをLunaへ移行 | JSON契約、失敗時返却、手動補正が成功 |
| C4 | 体型写真、チャット、計画、レポート | RAGなしでも安全に継続できる |
| C5 | D1 + Vectorize RAG | 引用品質が現行sqlite-vec以上 |
| C6 | 匿名分析、購入、広告報酬を移行 | 冪等性、返金、削除テスト成功 |
| C7 | Mac miniを本番経路から除外 | 7日間のAI成功率と台帳整合性を確認 |

### TestFlight先行移行

Build 28では、TestFlight専用の`bodymode-ai-gateway-staging`で次のAPIをCloudflare実行へ切り替える。

- `GET /v1/coaches`: Worker内の固定カタログ
- `GET /v1/evidence/status`: D1へ同期済みの論文索引状態
- `POST /v1/analytics/events`: 許可リスト方式の匿名イベントをD1へ90日保存
- `DELETE /v1/analytics/events`: 同じ匿名インストールキーのイベントを削除

WorkerはMac mini発行済みの短命トークンを同じHMAC署名鍵で検証する。生のApple ID、端末ID、アクセストークンはD1へ保存しない。生成AI、認証発行、Appleアカウント削除、AIクレジット、購入検証、広告報酬は台帳分裂を避けるため引き続きMac miniを正本とする。

## 7. ステージング資源

2026-08-22に本番と分離した次の資源を作成した。

- D1: `bodymode-staging`、APAC、schema version 1
- Vectorize: `bodymode-evidence-staging`、1,024 dimensions、cosine
- Worker環境: `staging` bindingのみ設定。公開Workerのルートは未変更
- 初回同期: D1文献2,844件、D1チャンク2,844件、Vectorize 2,844件で一致

既存RAGは`scripts/export_cloudflare_evidence.py`で読み取り専用SQLiteからD1 SQLとVectorize NDJSONへ変換する。会話、健康記録、写真は出力対象に含めない。

```bash
local_llm_server/.venv/bin/python scripts/export_cloudflare_evidence.py \
  --output /tmp/bodymode-cloudflare-evidence
```

Vectorizeの反映は非同期である。CLIの受付件数では完了とせず、`wrangler vectorize info bodymode-evidence-staging`の`vectorCount`がmanifestの件数と一致するまで確認する。大きなNDJSONは500件程度へ分割してupsertする。

## 8. ロールバック

API単位の`BODYMODE_CLOUD_ROUTES`で切り替える。C2以降は移行期間中だけ台帳イベントを両方へ記録し、Cloudflareを正本にするまではMac mini側の書き込みを止めない。残高差、認証失敗、OpenAI異常率のいずれかが基準を超えた場合は該当APIだけ中継へ戻す。

## 9. AI入出力予算

アプリの表示制限だけに依存せず、WorkerとAI Providerでも再検証する。上限超過はAIへ送信せず`413 input_limit_exceeded`とし、クレジットを消費しない。

| 機能 | ユーザー入力・画像 | AIへ渡す文字数 | Luna最大出力 |
|---|---:|---:|---:|
| 通常チャット | 300文字 | 10,000文字 | 800 tokens |
| 計画生成 | アプリ生成文4,000文字 | 16,000文字 | 1,600 tokens |
| 今日の提案 | アプリ生成文4,000文字 | 12,000文字 | 900 tokens |
| 食事画像 | メモ300文字、Base64 8,000,000文字 | 1,500文字 | 900 tokens |
| 体型写真 | メモ300文字、最大4枚、各Base64 8,000,000文字 | 2,000文字 | 1,200 tokens |
| 週次レポート | 手入力なし | 16,000文字 | 1,400 tokens |
| 月次レポート | 手入力なし | 18,000文字 | 1,600 tokens |

共通の絶対上限は本文24,000文字、Luna出力2,000 tokensとする。写真Base64は文字コンテキストへ数えず、画像用の個別上限で検証する。Mac mini互換APIも通常チャット300文字、会話1件1,000文字、コンテキスト合計24,000文字に揃える。Ollama出力は既存の`OLLAMA_NUM_PREDICT`既定512、最大2,048 tokensを維持する。
