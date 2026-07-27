# Figma UI Reference

Gym Trainingの現行UIを、Figmaで再設計するための参照スクリーンショットです。
すべてSimulator上のデモデータで撮影しており、個人データは含みません。

## Deliverables

- `screenshots/iphone`: iPhone 17、33画面、`1206 x 2622` PNG
- `screenshots/watch`: Apple Watch Series 11 46mm、13画面、`416 x 496` PNG
- `iphone-overview.png`: iPhone全画面の一覧
- `watch-overview.png`: Watch全画面の一覧

PNGは画面フロー順に連番を付けています。Figmaへ原寸で配置し、ファイル名を
Frame名として使うと整理しやすくなります。

## iPhone Screens

| No. | Area | Screens |
| --- | --- | --- |
| 01-02 | Theme | Royal Cobalt Light、Black Champagne Dark |
| 03-07 | Home / Coach | ホーム、目的選択、コンディション、センサー分析、AI週次レポート |
| 08-14 | Plan / Exercise | 計画一覧、計画作成、テンプレート、種目選択、種目ライブラリ、詳細、カスタム種目 |
| 15-18 | Daily Record / Body | 記録ハブ、体重推移、体重入力、記録後グラフ |
| 19-23 | Meal / Photo | 食事一覧、手動PFC入力、記録後一覧、体型写真一覧、写真記録 |
| 24-26 | Workout | セッション、休憩タイマー、完了サマリー |
| 27-31 | History / Analytics | カレンダー、履歴詳細、週次ボリューム、種目別履歴、種目推移 |
| 32-33 | Settings | プロフィール・外観、Health・ローカルAI・データ管理 |

## Watch Screens

| No. | Area | Screen |
| --- | --- | --- |
| 01 | Menu | 今日のメニュー選択 |
| 02 | Plan | メニュー詳細と開始 |
| 03 | Exercise | 種目・セット目標 |
| 04 | Workout | 記録中トップ |
| 05 | Set | セット実行中 |
| 06 | Input | 重量リール |
| 07 | Input | 回数リール |
| 08 | Rest | セット間休憩と次セット提案 |
| 09 | Rest | 休憩時間リール |
| 10 | History | 完了セットアーカイブ |
| 11 | Sensors | 心拍、ゾーン、経過時間、消費エネルギー |
| 12 | Input | RPEリール |
| 13 | Note | 音声・文字メモ |

## Capture Notes

- iPhoneの主セットはRoyal Cobaltのライトモードです。
- `01`と`02`でB/Dテーマとライト・ダークの代表表示を比較できます。
- `23-iphone-body-photo-editor.png`は手入力状態を示すため、キーボード表示を残しています。
- AI画面は未接続状態のUIです。AI生成結果ではなく、接続・生成導線の設計資料として扱います。
- 撮影テストは `GymTrainingAppUITests/FigmaReferenceScreenshots.swift` と
  `GymTrainingWatchAppUITests/FigmaReferenceScreenshots.swift` にあります。
