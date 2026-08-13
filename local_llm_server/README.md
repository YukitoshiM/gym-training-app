# Local AI Server

Mac mini上のCalorieCLIPとOllamaをiPhoneアプリから使うためのAPIです。

## 起動

```bash
cd local_llm_server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
chmod +x install_calorie_clip.sh
./install_calorie_clip.sh
export LOCAL_AI_API_KEY=dev-local-key
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export OLLAMA_MODEL=gemma4:12b
uvicorn main:app --host 0.0.0.0 --port 8765
```

Simulatorからは `http://127.0.0.1:8765` を指定します。

## Macログイン時の自動起動

APIキーをGit管理外の`local_llm_server/.api_key`へ保存したうえで、LaunchAgentを登録します。

```bash
chmod +x local_llm_server/run_server.sh scripts/install_local_ai_launch_agent.sh
./scripts/install_local_ai_launch_agent.sh
curl -H "Authorization: Bearer $(cat local_llm_server/.api_key)" http://127.0.0.1:8765/v1/health
```

インストーラーは実行環境を`~/Library/Application Support/BodyMode/local_ai_server/`へ同期します。`/tmp`の削除に影響されず、macOSのバックグラウンドプロセスからも安定して読み込めます。サーバーコードを変更した場合はインストーラーを再実行してください。ログは`~/Library/Logs/BodyMode/`へ保存します。

同時に60秒間隔の監視Agentを登録します。`/internal/health`に加え、短命トークンを取得して認証付き`/v1/health`まで確認します。ローカル確認が3回連続で失敗した場合だけAPIを再起動し、5MiBを超えたログを1世代ローテーションします。インストール時に監視スクリプトのSHA-256とLaunchAgentの参照先を検証するため、リポジトリ更新後に古い監視コピーが残りません。

`token_required`では、監視専用の登録キーを次のファイルへ保存してください。登録キーは監査ログへ出力されません。

```bash
printf '%s' 'monitor-enrollment-key' > local_llm_server/.health_enrollment_key
chmod 600 local_llm_server/.health_enrollment_key
```

公開経路も監視する場合は、HTTPSのBase URLを`.public_base_url`へ保存してからインストーラーを再実行します。公開経路だけが失敗した場合、正常なローカルAPIは再起動しません。

```bash
printf '%s' 'https://your-tailnet-name.ts.net' > local_llm_server/.public_base_url
chmod 600 local_llm_server/.public_base_url
./scripts/install_local_ai_launch_agent.sh
```

## 公開時の短命認証

配布ビルドでは共有APIキーを通常リクエストへ送らず、端末ごとの短命トークンへ交換します。

1. `.env.local.example`をGit管理外の`.env.local`へ複製する。
2. `AI_TOKEN_SIGNING_SECRET`へ十分に長い乱数を設定する。
3. テスターごとの登録キーをSHA-256化し、`enrollment_keys.json`へ保存する。
4. 移行中は`AI_AUTH_MODE=compat`、全配布ビルド更新後は`token_required`にする。
5. Releaseの`BODYMODE_AI_USES_SESSION_TOKENS`を`YES`にする。

トークンは端末Keychainへ保存され、期限の60秒前または401受信時に再取得します。`POST /v1/auth/revoke`で個別トークンを失効でき、サーバーは端末・APIごとに1分当たりの要求数を制限します。トークン発行口にも接続元単位の専用上限（既定8回/分）と短い失敗遅延（既定0.25秒、最大2秒）があり、成功・拒否・制限をハッシュ化識別子だけで監査記録します。登録キー、アクセストークン、端末IDの平文は監査ログへ保存しません。

必要な場合は`.env.local`で次を調整できます。上限を無効化する設定はありません。

```bash
AI_TOKEN_ISSUE_RATE_LIMIT_PER_MINUTE=8
AI_TOKEN_FAILURE_DELAY_SECONDS=0.25
```

```bash
cd local_llm_server
python -m unittest test_auth.py
```

## TestFlight開発用の公開URL

開発中は独自ドメインを購入せず、Tailscale Funnelの固定`*.ts.net` URLを使用します。

```bash
brew install tailscale
chmod +x scripts/install_tailscale_funnel_launch_agent.sh
./scripts/install_tailscale_funnel_launch_agent.sh

SOCKET="$HOME/Library/Application Support/BodyMode/tailscale/tailscaled.socket"
tailscale --socket="$SOCKET" up
tailscale --socket="$SOCKET" funnel --bg --yes 8765
tailscale --socket="$SOCKET" funnel status
```

Tailscale Funnelは開発・TestFlight検証に限定します。正式リリース前には独自ドメインを取得し、Cloudflare Named Tunnelへ移行します。

## Web画面

サーバー起動後、ブラウザで次を開くと食事画像をアップロードして推定結果を手動補正できます。

- Mac mini自身: `http://127.0.0.1:8765`
- 同じWi-Fiの端末: `http://<Mac miniのLAN IP>:8765`

インターネットへ公開する場合は、推測されにくい `LOCAL_AI_API_KEY` を設定し、Cloudflare TunnelやTailscaleなど認証・暗号化された経路を利用してください。開発用の `dev-local-key` のまま公開しないでください。
実機からはMacのLAN IPかTailscale名を指定します。

## Ollama

写真ありの場合はCalorieCLIPがカロリーを推定し、Ollamaは料理名とPFCの補助推定に使います。写真なしの場合は、ユーザーが入力した食品名と量をOllamaが構造化し、食品ごとのカロリーとPFCを下書きします。

```bash
ollama pull gemma4:12b
ollama serve
```

Ollamaに接続できない場合も、アプリ開発を止めないためのフォールバックJSONを返します。

## 接続確認

アプリの設定画面で「接続確認」を押すと、次の3段階を確認します。

- `local_llm_server` が起動しているか
- `OLLAMA_BASE_URL` のOllamaに接続できるか
- `OLLAMA_MODEL` で指定したモデルが取得済みか

よくある失敗:

- `ローカルLLMサーバーに接続できません`: `uvicorn main:app --host 0.0.0.0 --port 8765` を起動します。
- `Ollama未接続`: `ollama serve` を起動し、`OLLAMA_BASE_URL` を確認します。
- `モデル未取得`: `ollama pull $OLLAMA_MODEL` を実行するか、利用中のモデル名を `OLLAMA_MODEL` に指定します。

## Endpoints

- `GET /v1/health`
- `POST /v1/auth/token`
- `POST /v1/auth/revoke`
- `GET /v1/coaches`
- `POST /v1/agents/chat`
- `POST /v1/meals/analyze-image`
- `POST /v1/meals/analyze-text`
- `POST /v1/body-photos/analyze`
- `POST /v1/body-photos/analyze-set`
- `POST /v1/reports/weekly`

`analyze-set`は同じ日の正面・横・背面・腹部アップを最大4枚受け取り、角度を区別した1つの分析結果を返します。アプリは写真追加後に同じ撮影セットを再送でき、サーバーは画像や分析履歴を保存しません。

`analyze-text`は食べたものを最大20件受け取ります。量が書かれていない食品は一般的な1食分を仮定して信頼度を下げ、厳格なJSON Schemaで食品別の推定値を返します。サーバーはモデルが返した食品別数値を合計し直して、食事全体のカロリーとPFCを確定します。

現行MVPでは`gemma4:12b`を食品名・量の解釈と推定に利用します。次段階では文部科学省の日本食品標準成分表をローカルDB化し、Ollamaは食品名の正規化とDB候補選択だけを担当、栄養値はDBから決定的に計算する構成へ移行します。

## 目的別コーチ

週次レポートはアプリで選択したコーチの判断基準を使用します。

- `fat_loss`: 減量
- `hypertrophy`: 筋肥大
- `strength`: 筋力向上
- `body_recomposition`: ボディメイク
- `wellness`: 健康維持
- `return_to_training`: 復帰

定義は `coach_profiles.py` に集約しています。各コーチは優先順位、判断ルール、伝え方、禁止事項を持ち、共通の安全ルールも必ず適用されます。

## AIトレーナーチャット

`POST /v1/agents/chat` はステートレスです。会話履歴、集計済みコンテキスト、確認済みの長期記憶はアプリからリクエストごとに送信します。サーバーは回答と最大3件の記憶候補を返し、履歴やコンテキストを保存しません。
