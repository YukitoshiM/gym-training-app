# Gym Training App

iPhone向けトレーニング記録アプリの企画・設計リポジトリです。

MVPでは、トレーニング計画、セットごとの実績記録、目標との差分、身体KPI、オフライン記録、クラウド同期を中心に設計しています。

## Documents

- [アルファ版スコープ定義](docs/alpha_scope.md)
- [MVP設計書](docs/gym_training_app_design_mvp.md)
- [iOS開発環境セットアップ](docs/ios_environment_setup.md)

## Development

このプロジェクトはXcodeGenでXcodeプロジェクトを生成します。

```sh
brew install xcodegen
xcodegen generate
open GymTrainingApp.xcodeproj
```
