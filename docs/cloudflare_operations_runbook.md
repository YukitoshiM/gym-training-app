# BodyMode Cloudflare運用・復旧手順

更新日: 2026-08-23

## 日常監視

1時間ごとに本番healthと24時間集計を確認し、最新JSONを次へ保存する。状態変化時、warning/criticalが6時間継続した時、復旧時にはmacOS通知も表示する。

`~/Library/Application Support/BodyMode/operations/latest.json`

手動確認:

```bash
./scripts/cloudflare_operations_report.py
```

判定基準:

| 状態 | 条件 | 初動 |
|---|---|---|
| Critical | AI成功率90%未満、p95 100秒超、日次上限到達、15分超の未確定クレジット、残高不整合 | AIを停止または直前Workerへ戻し、クレジットを確認 |
| Warning | AI成功率95%未満、p95 60秒超、日次上限80%超、App Store通知拒否 | 当日中にCloudflare Logsと通知payloadを確認 |
| OK | 上記なし | 継続監視 |

healthはOpenAIの無料モデル情報APIへ実際に接続し、キーの認証と設定モデルの参照可否を確認する。生成リクエストやトークン消費は行わない。`OPENAI_API_KEY`未設定、無効、モデル参照権限不足、モデル不在の場合はdegradedとなる。開発中だけは次で他の指標を確認できる。

```bash
./scripts/cloudflare_operations_report.py --allow-ai-degraded
```

### OpenAI APIキーの登録とローカル保管

本番とステージングは別のOpenAIサービスアカウントキーを使用する。キーをチャット、`.env`、xcconfig、ソース、シェル履歴へ保存しない。次のスクリプトは文字数制限のない表示入力からmacOS Keychainへ保存し、入力値と保存値が完全一致することを確認してから、Cloudflare Worker Secretへ登録する。入力中はキーがTerminalに表示されるため、画面共有やスクリーンショットを停止して実行する。

```bash
./scripts/configure_openai_api_key.sh production
./scripts/configure_openai_api_key.sh staging
```

Keychainではservice `com.bodymode.openai-api-key`、account `bodymode-production`または`bodymode-staging`として保持する。キーを紛失した場合は値を再利用しようとせず、OpenAIで新しいキーを作成して上記スクリプトで差し替え、疎通確認後に旧キーを失効する。

ローカルのKeychainコピーを平文で確認する場合は、Terminalで直接次を実行する。

```bash
./scripts/show_openai_api_key.sh production
```

`REVEAL`の入力が必要で、リダイレクトやパイプへの出力は拒否する。Cloudflareへ登録したSecretそのものは読み戻せない。

## バックアップ

D1、Worker配備履歴、secret名一覧、Vectorize情報、Wrangler設定を毎日3:20に保存し、14日保持する。秘密値そのものは出力しない。

```bash
./scripts/backup_cloudflare_backend.sh
```

RAGを更新した日には、再投入用D1 SQLとVectorize NDJSONも保存する。

```bash
./scripts/backup_cloudflare_backend.sh --with-evidence
```

保存先:

`~/Library/Application Support/BodyMode/backups/cloudflare/production/`

定期実行の導入:

```bash
./scripts/install_cloudflare_operations_launch_agents.sh
```

macOSのLaunchAgentは`Documents`配下へアクセスできないため、インストーラは実行に必要なスクリプトと`wrangler.jsonc`だけを`Application Support/BodyMode/operations/runtime`へ複製する。ソース更新後はインストーラを再実行する。

## Workerロールバック

1. `deployments.json`または次のコマンドで正常だったVersion IDを特定する。
2. ロールバックする。
3. preflightと実機AIを確認する。

```bash
cd cloudflare_ai_gateway
npx wrangler deployments list --env production --name bodymode-ai-gateway-production --json
npx wrangler rollback VERSION_ID --env production --name bodymode-ai-gateway-production \
  --message "incident rollback" --yes
../scripts/cloudflare_production_preflight.sh
```

## D1復旧

D1の復旧は既存本番DBへ即時上書きしない。新しい復旧用DBを作り、バックアップSQLを投入して件数と整合性を確認してからbindingを切り替える。

```bash
cd cloudflare_ai_gateway
npx wrangler d1 create bodymode-production-restore-YYYYMMDD
npx wrangler d1 execute bodymode-production-restore-YYYYMMDD --remote \
  --file "/path/to/backup/d1.sql" --yes
```

確認項目はschema version、accounts、credit lots、credit reservations、AI requests、evidence documents/chunks。binding切替前にクレジット残高とlot残量の一致をSQLで確認する。

## Vectorize再構築

`--with-evidence`バックアップの`evidence/vectors.ndjson`を新規indexへ投入する。既存indexを先に削除しない。

```bash
cd cloudflare_ai_gateway
npx wrangler vectorize create bodymode-evidence-production-restore \
  --dimensions 1024 --metric cosine
npx wrangler vectorize insert bodymode-evidence-production-restore \
  --file "/path/to/backup/evidence/vectors.ndjson" --batch-size 200
```

件数一致を確認後、`wrangler.jsonc`のbindingを復旧indexへ切り替えて配備する。

## 鍵の失効・更新

漏えいが疑われた鍵だけをローテーションし、旧鍵を先に削除しない。新鍵設定、staging確認、本番確認、旧鍵削除の順に行う。

対象:

- `OPENAI_API_KEY`
- `BODYMODE_TOKEN_SIGNING_SECRET`
- `APPLE_PRIVATE_KEY_P8`
- `APPLE_REFRESH_TOKEN_ENCRYPTION_KEY`
- `BODYMODE_ENROLLMENT_KEY_HASHES`

Worker secret値はバックアップへ含めない。復旧可能性はApple、OpenAI、Cloudflare各管理画面と安全なローカル保管物で担保する。

## 障害記録

発生時刻、影響機能、status/alert code、直前のWorker Version ID、対応、復旧時刻を`docs/incidents/`へ残す。健康・写真・食事内容やApple subjectは記録しない。
