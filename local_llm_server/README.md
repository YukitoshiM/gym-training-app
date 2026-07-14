# Local LLM Server

Mac mini上のOllamaをiPhoneアプリから使うための開発用APIです。

## 起動

```bash
cd local_llm_server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export LOCAL_AI_API_KEY=dev-local-key
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export OLLAMA_MODEL=gemma4:12b
uvicorn main:app --host 0.0.0.0 --port 8765
```

Simulatorからは `http://127.0.0.1:8765` を指定します。
実機からはMacのLAN IPかTailscale名を指定します。

## Ollama

画像解析を使う場合は、画像対応モデルを用意します。

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
- `POST /v1/meals/analyze-image`
- `POST /v1/body-photos/analyze`
- `POST /v1/reports/weekly`
