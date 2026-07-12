# AI Bodymake Manager

iPhone向けAIボディメイクマネージャーの企画・設計・実装リポジトリです。

現在の実装は筋トレ記録を中核にしています。今後は体重・腹囲・体型写真・食事写真・筋トレ記録を接続し、AIが次にやることを提案する改善管理アプリへ拡張します。

## Local LLM

開発中はMac上のローカルLLMサーバーを使います。

```sh
cd local_llm_server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export LOCAL_AI_API_KEY=dev-local-key
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export OLLAMA_MODEL=gemma4:12b
uvicorn main:app --host 0.0.0.0 --port 8765
```

Simulatorではアプリ設定のローカルLLM URLを `http://127.0.0.1:8765` にします。実機ではMacのLAN IPまたはTailscale名を指定します。

## Documents

- [AIボディメイクマネージャー プロダクト方針](docs/ai_bodymake_manager_product_plan.md)
- [MVP要件整理](docs/mvp_requirements.md)
- [アルファ版スコープ定義](docs/alpha_scope.md)
- [MVP設計書](docs/gym_training_app_design_mvp.md)
- [競合アプリ参考メモ](docs/competitive_research.md)
- [iOS開発環境セットアップ](docs/ios_environment_setup.md)

## Development

このプロジェクトはXcodeGenでXcodeプロジェクトを生成します。

```sh
brew install xcodegen
xcodegen generate
open GymTrainingApp.xcodeproj
```
