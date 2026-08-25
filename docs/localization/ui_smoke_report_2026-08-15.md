# BodyMode 代表言語UIスモーク結果

実施日: 2026-08-15

## 対象

| 端末 | 言語 | 結果 |
|---|---|---|
| iPhone | 日本語 | 合格 |
| iPhone | 英語（米国） | 合格 |
| iPhone | 中国語（簡体字） | 合格 |
| iPhone | ドイツ語 | 合格 |
| iPhone | アラビア語 | 合格 |
| Apple Watch | 日本語 | 合格 |
| Apple Watch | 英語（米国） | 合格 |
| Apple Watch | ドイツ語 | 合格 |
| Apple Watch | アラビア語 | 合格 |

確認画像は`docs/localization/ui-smoke/`に保存する。

## 検出・修正した問題

- 英語・ドイツ語のホームで、担当コーチ名と操作が横方向に密集していたため、操作を次の行へ分離した。
- RTL言語で進捗値`0 / 3`の順序が反転したため、数値部分をLTRとして独立表示した。
- Watchチュートリアルのナビゲーションタイトルが時刻・アイコンと重なるため、画面上のタイトルを除きアクセシビリティ名を維持した。
- AI計画UIテストでDEBUG用JSONへローカライズ呼び出しが文字列として混入していたため、`JSONSerialization`による構造化生成へ変更した。

## 残る人手確認

- 健康・法務・権限説明は対象言語話者または専門家が確認する。
- 実機のDynamic Type最大サイズ、VoiceOver、Watchの長文表示はRelease Candidate受入で確認する。
- 機械翻訳の地域差がある英語、フランス語、ポルトガル語の地域版は公開前に確認する。

## 補足

Watchアプリは生成済みSchemeから実行するとiPhone用AdMob依存をwatchOS向けに解決しようとして失敗するため、現時点のCI・ローカル検証では`GymTrainingWatchApp` targetを直接指定する。アプリ本体のWatchビルドは成功している。
