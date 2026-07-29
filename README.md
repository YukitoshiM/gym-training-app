# BodyMode

iPhone・Apple Watch向けAI健康管理アプリの企画・設計・実装リポジトリです。

**Your body. Your mode.**

体重・腹囲・体型写真・食事・運動・睡眠・コンディションをつなぎ、ダイエット、筋肥大、健康維持、体型改善、競技力向上を一つの体験で管理します。

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
- [AIコーチ・SNS・収益化 統合設計](docs/ai_coach_social_monetization_design.md)
- [S59以降 AIコーチ・成長機能 実装台帳](docs/s59_growth_implementation_backlog.md)
- [TestFlight公開計画](docs/testflight_release_plan.md)
- [TestFlight登録用メタデータ](docs/app_store_connect/testflight_metadata_ja.md)
- [App Storeローンチチェックリスト](docs/app_store_launch_checklist.md)
- [プライバシーポリシー](docs/legal/privacy-policy-ja.md)
- [利用規約](docs/legal/terms-of-use-ja.md)
- [MVP要件整理](docs/mvp_requirements.md)
- [アルファ版スコープ定義](docs/alpha_scope.md)
- [MVP設計書](docs/gym_training_app_design_mvp.md)
- [競合アプリ参考メモ](docs/competitive_research.md)
- [Apple Watch連携 W1設計](docs/apple_watch_workout_plan.md)
- [iOS開発環境セットアップ](docs/ios_environment_setup.md)

## Development

このプロジェクトはXcodeGenでXcodeプロジェクトを生成します。

```sh
brew install xcodegen
xcodegen generate
open GymTrainingApp.xcodeproj
```
