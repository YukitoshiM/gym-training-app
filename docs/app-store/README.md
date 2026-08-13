# BodyMode ストア画像

更新日: 2026-08-03

## iPhone

`screenshots/`に6.9インチ向け画像を6枚保存する。

- 1320 x 2868 px
- PNG、アルファチャンネルなし
- iPhone 17 Pro Max Simulator / iOS 26.5
- ライトモード、Royal Cobaltテーマ

表示順:

1. ホーム
2. 記録ハブ
3. トレーニング完了
4. 履歴カレンダー
5. 身体指標
6. コンディション

## Apple Watch

`watch-screenshots/`にSeries 11向け画像を3枚保存する。

- 416 x 496 px
- PNG、アルファチャンネルなし
- Apple Watch Series 11 (46mm) Simulator / watchOS 26.5

表示順:

1. 今日のメニュー
2. セット実行
3. ライブ指標

## 再生成

iPhoneは`GymTrainingAppUITests/FigmaReferenceScreenshots`、Watchは`GymTrainingWatchAppUITests/WatchFigmaReferenceScreenshots`を実行し、`xcresulttool export attachments`で書き出す。

`scripts/testflight_preflight.sh`は画像枚数、寸法、アルファチャンネルを検査する。

Apple仕様: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
