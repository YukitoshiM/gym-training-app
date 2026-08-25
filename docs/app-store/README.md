# BodyMode ストア画像

更新日: 2026-08-23

## iPhone

`screenshots/`に日本語、`screenshots-en/`に英語の6.9インチ向け画像を各8枚保存する。

- 1320 x 2868 px
- PNG、アルファチャンネルなし
- iPhone 17 Pro Max Simulator / iOS 26.5
- ライトモード、Royal Cobaltテーマ

表示順:

1. おまかせホーム「今日の3つ」
2. 12人のAIコーチとAIハブ
3. AIコーチのチャット
4. トレーニング完了
5. 履歴カレンダー
6. 身体指標
7. トレーニング計画
8. 記録ハブ

2026-08-21時点で、日本語・英語のiPhone各8枚は正式公開候補`1.0 (25)`相当の実画面から再生成済み。英語版は日本語版と同じ8画面を同じ順序で収録し、日本語の残存がないことを連絡シートで確認した。画像生成ケースは提出画面ごとに独立させ、提案内容の変化で別画面の撮影まで連鎖して失敗しないようにした。

## iPad

`ipad-screenshots/`に日本語、`ipad-screenshots-en/`に英語の13インチ向け画像を各1枚保存する。

- 2064 x 2752 px
- PNG、アルファチャンネルなし
- iPad Pro 13-inch (M5) Simulator / iOS 26.5
- おまかせホーム「今日の3つ」

2026-08-23時点で、Build 30の実画面から日英を生成済み。英語版はSimulatorのシステム言語と地域も英語（アメリカ）へ切り替え、ステータスバーを含めて日本語が残らないことを確認した。

## Apple Watch

`watch-screenshots/`に日本語、`watch-screenshots-en/`に英語のSeries 11向け画像を各3枚保存する。

- 416 x 496 px
- PNG、アルファチャンネルなし
- Apple Watch Series 11 (46mm) Simulator / watchOS 26.5

表示順:

1. 今日のメニュー
2. セット実行
3. 計画詳細（英語版。日本語版はライブ指標）

2026-08-14時点で、Watch 3枚もBuild 17相当の実画面から再生成済み。追加機能用のRPE画像ロケータに1件の残件があるが、提出3枚の取得には影響しない。

## 再生成

iPhone/iPadは`GymTrainingAppUITests/FigmaReferenceScreenshots`、Watch日本語版は`GymTrainingWatchAppUITests/WatchFigmaReferenceScreenshots`を実行し、`xcresulttool export attachments`で書き出す。英語版iPadは13インチSimulatorのシステム言語と地域を英語（アメリカ）へ切り替えてから`test08EnglishSocialPromoScreenshots`を実行する。Watch英語版は`GymTrainingWatchAppUITests/GymTrainingWatchAppUITests/testEnglishAppStoreScreenshots`が`/tmp/bodymode-watch-app-store-en`へ直接書き出す。

`scripts/testflight_preflight.sh`は日本語・英語iPhone各8枚、日本語・英語iPad各1枚、日本語・英語Watch各3枚の画像枚数、寸法、アルファチャンネルを検査する。

Apple仕様: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
