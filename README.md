# BodyMode

iPhone・Apple Watch向けAI健康管理アプリの企画・設計・実装リポジトリです。

**Your body. Your mode.**

体重・腹囲・体型写真・食事・運動・睡眠・コンディションをつなぎ、ダイエット、筋肥大、健康維持、体型改善、競技力向上を一つの体験で管理します。

ホームでは端末内ルールが「今日の調子」と「今日やること最大3件」を即時に提示します。AIはバックグラウンドで記録を横断して点検し、必要な場合だけ理由付きで提案を補正します。

## AI API

アプリは、設定画面で指定したHTTPS APIまたはローカルAPIへ接続します。開発・配布ビルドへ初期値を入れる場合は、Git管理外の設定を作成します。

```sh
cp Config/AIService.local.xcconfig.example Config/AIService.local.xcconfig
```

`Config/AIService.local.xcconfig`へBase URLとAPIキーを設定してから`xcodegen generate`を実行します。Base URLとAPIキーはアプリの設定画面でも変更できます。詳細は[AI APIサーバー連携設計](docs/ai_server_integration.md)を参照してください。

## Advertising

DebugはGoogle公式テスト広告を使用します。ReleaseでAdMob IDを設定する場合は、Git管理外の設定を作成します。

```sh
cp Config/Ads.local.xcconfig.example Config/Ads.local.xcconfig
```

健康データを広告選定へ使用しない設計と本番化手順は[広告連携設計](docs/advertising_integration.md)を参照してください。

### Mac miniのローカルAPI

開発中はMac上のローカルLLMサーバーを使います。

```sh
cd local_llm_server
brew install python@3.11
./setup_environment.sh
source .venv/bin/activate
export LOCAL_AI_API_KEY=dev-local-key
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export OLLAMA_MODEL=gemma4:12b
uvicorn main:app --host 0.0.0.0 --port 8765
```

Simulatorではアプリ設定のローカルLLM URLを `http://127.0.0.1:8765` にします。実機ではMacのLAN IPまたはTailscale名を指定します。

## Documents

- [ドキュメント索引](docs/README.md)
- [アーキテクチャ](docs/architecture.md)
- [機能マップ](docs/feature_map.md)
- [おまかせモード仕様書 v2](docs/omakase_mode_specification_v2.md)
- [リリース準備の正本](docs/release_readiness_plan.md)
- [MVP要件の正本](docs/mvp_requirements.md)
- [AIボディメイクマネージャー プロダクト方針](docs/ai_bodymake_manager_product_plan.md)
- [AIコーチ・SNS・収益化 統合設計](docs/ai_coach_social_monetization_design.md)
- [AI APIサーバー連携設計](docs/ai_server_integration.md)
- [AIトレーナー連携設計](docs/ai_trainer_integration.md)
- [広告連携設計](docs/advertising_integration.md)
- [S59以降 AIコーチ・成長機能 実装台帳](docs/s59_growth_implementation_backlog.md)
- [TestFlight公開計画](docs/testflight_release_plan.md)
- [App Storeローンチチェックリスト](docs/app_store_launch_checklist.md)
- [iOS開発環境セットアップ](docs/ios_environment_setup.md)

## Development

このプロジェクトはXcodeGenでXcodeプロジェクトを生成します。

```sh
brew install xcodegen
xcodegen generate
open GymTrainingApp.xcodeproj
```
