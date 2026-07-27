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
実機からはMacのLAN IPかTailscale名を指定します。

## Ollama

CalorieCLIPがカロリーを推定します。Ollamaは料理名とPFCの補助推定に使います。

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
- `GET /v1/coaches`
- `POST /v1/meals/analyze-image`
- `POST /v1/body-photos/analyze`
- `POST /v1/reports/weekly`

## 目的別コーチ

週次レポートはアプリで選択したコーチの判断基準を使用します。

- `fat_loss`: 減量
- `hypertrophy`: 筋肥大
- `strength`: 筋力向上
- `body_recomposition`: ボディメイク
- `wellness`: 健康維持
- `return_to_training`: 復帰

定義は `coach_profiles.py` に集約しています。各コーチは優先順位、判断ルール、伝え方、禁止事項を持ち、共通の安全ルールも必ず適用されます。
