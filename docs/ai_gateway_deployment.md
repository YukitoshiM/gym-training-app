# BodyMode AIゲートウェイ配備手順

更新日: 2026-08-15

## 目的

正式配布アプリからMac miniのTailscaleホスト名を除き、Cloudflare Workerの中立な`workers.dev` URLだけを公開する。初期構成はCloudflare Workers Freeを使い、独自ドメイン費用を発生させない。

現在の公開ゲートウェイ:

`https://bodymode-ai-gateway.bodymode-ai.workers.dev`

```text
iPhone / Watch
    -> Cloudflare Worker (公開URL、API許可リスト、秘密ヘッダー付与)
    -> Tailscale Funnel (配布バイナリには含めない)
    -> Mac mini / BodyMode AI API / Ollama
```

Workerは許可済みの`/v1/*`だけを中継し、12MBを超えるリクエスト、未許可メソッド、内部ヘルスAPIを拒否する。Mac mini側では共有秘密を有効化するとWorker以外からの`/v1/*`をHTTP 403にする。

## 制約

- Workers Freeは1日100,000リクエストまで。BodyMode側のAI利用枠の方を十分小さくし、Mac miniの推論能力を先に保護する。
- Cloudflareプロキシの既定読み取りタイムアウトは125秒。公開判定ではAI処理のp95を100秒未満にする。超える処理は将来ジョブ受付とポーリングへ変更する。
- `workers.dev`は初期検証用とする。利用が伸び、可用性やブランド要件が上がった時点で独自ドメインを検討する。
- Workerの秘密値、Mac miniの直接URL、アプリ用認証情報はGitへ保存しない。

## 初回配備

1. Cloudflare CLIへ一度ログインする。

```bash
cd cloudflare_ai_gateway
npx wrangler login
```

2. リポジトリ直下で配備する。

```bash
./scripts/deploy_cloudflare_ai_gateway.sh
```

Cloudflareアカウントで`workers.dev`サブドメインが未登録の場合は、最初に`cloudflare_ai_gateway`で`npx wrangler deploy`を直接実行し、対話画面でサブドメインを登録する。その後、上記スクリプトを再実行する。

このスクリプトは次を行う。

- 現在のTailscale Funnel URLをWorkerの暗号化されたsecretへ登録
- 256-bitのゲートウェイ共有秘密を端末内に生成
- Workerを配備し、トークン発行と`/v1/health`を確認
- Worker URLをGit管理外の設定へ保存
- `Config/AIService.local.xcconfig`のRelease接続先をWorkerへ変更
- AI設定バージョンを増加

この段階では旧TestFlightビルドを止めないため、Mac miniの直通拒否はまだ有効化しない。

## 段階移行

1. Worker URLを使う新しいTestFlightビルドを配布する。
2. AIチャット、食事画像、体型写真、利用残数を実機で確認する。
3. 全アクティブテスターが新ビルドへ更新したことを確認する。
4. 直通拒否を有効化する。

```bash
./scripts/activate_ai_gateway_only_mode.sh \
  --confirm-all-active-builds-use-gateway
```

成功条件は、Tailscale直通がHTTP 403、Worker経由がHTTP 200になること。

Build 18配布後の2026-08-15にゲートウェイ専用モードを有効化し、上記のHTTP 403 / 200を確認済み。

## ロールバック

新ビルドで問題が出た場合は、直通拒否を有効化せずにWorker設定またはアプリ設定を修正する。直通拒否後に緊急解除する場合は、`local_llm_server/.gateway_shared_secret`を別の安全な場所へ退避し、`scripts/install_local_ai_launch_agent.sh`を再実行する。解除中は旧直通URLを公開し続けない。

## 運用確認

- CloudflareのWorkerエラー率とリクエスト数
- Mac miniのAI機能別件数、推論時間、混雑率
- `origin_unreachable`、HTTP 429、HTTP 503、タイムアウトの比率
- 推論p95が100秒を超えていないこと

広告データとAI利用データは個人単位で結合しない。

## 公式資料

- Cloudflare Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- workers.dev routing: https://developers.cloudflare.com/workers/configuration/routing/workers-dev/
- Worker secrets: https://developers.cloudflare.com/workers/configuration/secrets/
- Error 524 and proxy timeout: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/
