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
export OLLAMA_MODEL=llava
uvicorn main:app --host 0.0.0.0 --port 8765
```

Simulatorからは `http://127.0.0.1:8765` を指定します。
実機からはMacのLAN IPかTailscale名を指定します。

## Ollama

画像解析を使う場合は、画像対応モデルを用意します。

```bash
ollama pull llava
ollama serve
```

Ollamaに接続できない場合も、アプリ開発を止めないためのフォールバックJSONを返します。

## Endpoints

- `GET /v1/health`
- `POST /v1/meals/analyze-image`
- `POST /v1/body-photos/analyze`
- `POST /v1/reports/weekly`
