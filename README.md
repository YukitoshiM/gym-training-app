# AI Bodymake Manager

iPhone向けAIボディメイクマネージャーの企画・設計・実装リポジトリです。

現在の実装は筋トレ記録を中核にしています。今後は体重・腹囲・体型写真・食事写真・筋トレ記録を接続し、AIが次にやることを提案する改善管理アプリへ拡張します。

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
