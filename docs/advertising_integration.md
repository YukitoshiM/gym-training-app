# BodyMode 広告連携設計

更新日: 2026-08-11

## 方針

- 広告はiPhoneアプリの共通ルート上部に1枠だけ固定し、主要タブとその配下画面で継続表示する。
- Apple Watch、Widget、通知、利用規約への同意前、広告同意が得られていない状態には表示しない。
- 全画面、リワード、App Open、折りたたみ広告は使用しない。
- パーソナライズを無効化し、First-party IDとクロスアプリ追跡を使用しない。
- HealthKit、身体値、食事、写真、トレーニング、睡眠、心拍、疲労、目標、位置を広告リクエストへ入れない。

## 構成

| 要素 | 実装 |
|---|---|
| 配信 | Google Mobile Ads SDK 13.7.0 |
| 同意 | Google User Messaging Platform 3.1.0 |
| 広告形式 | Anchored adaptive banner |
| 表示位置 | iPhoneの共通ルート上部。主要タブとその配下画面で固定 |
| 起動タイミング | BodyMode利用規約へ同意後 |
| 失敗時 | 固定枠を維持して60秒後に再試行し、記録機能は継続 |
| 報告 | 設定画面から報告文を送信 |

`AdvertisingManager` は起動ごとにUMPの同意情報を更新する。`canRequestAds`が`true`になるまでGoogle Mobile Ads SDKを初期化せず、広告をリクエストしない。

固定バナーはタブ切替で再生成せず、同じ広告ビューを維持する。画面遷移ごとの過剰なリクエストを避け、読み込み失敗時の再試行間隔は60秒以上とする。誤タップを避けるため、広告をタブバーや入力ボタンの間に挟まず、境界線でアプリの操作領域と分離する。

## 収益運用

初期目標は、広告収益でBodyModeの保守・配布・サーバー運用費の一部または全部を賄うこととする。AdMobで広告リクエスト数、マッチ率、表示回数、1日利用者あたり表示回数、eCPM、推定収益を週次確認し、月間運用費と比較する。広告クリックを促す表示や文言は使用せず、収益不足時は利用体験を損なう広告増量より、任意の広告非表示課金や有料AI機能を別途検討する。

## データ

Google Mobile Ads SDKは広告配信のため、IPアドレスからの概算位置、SDKのクラッシュ・パフォーマンス情報、端末識別子、広告表示情報、広告との操作を取得する場合がある。実際のReleaseビルドのPrivacy ReportとGoogleの最新データ開示資料を照合し、App Store ConnectのApp Privacyへ反映する。

BodyModeは`publisherPrivacyPersonalizationState = .disabled`、`setPublisherFirstPartyIDEnabled(false)`、`npa=1`を設定する。ATTは要求せず、`NSUserTrackingUsageDescription`も追加しない。

## 設定

DebugはGoogle公式デモIDを`Config/App.Debug.xcconfig`から読み込む。ReleaseはGit管理外の`Config/Ads.local.xcconfig`を使用する。

```sh
cp Config/Ads.local.xcconfig.example Config/Ads.local.xcconfig
```

必要な値:

```text
BODYMODE_ADMOB_APP_ID = ca-app-pub-...~...
BODYMODE_ADMOB_BANNER_AD_UNIT_ID = ca-app-pub-.../$()...
```

`/$()`は`xcconfig`が`//`以降をコメントと解釈するのを防ぐ。本番提出でGoogleのデモIDを使用しない。

## AdMob側の残作業

1. AdMobに`com.yukitoshim.gymtrainingapp`をiOSアプリとして登録する。
2. アンカーアダプティブバナーの広告ユニットを作る。
3. Privacy & messagingでEEA、UK、スイス等の同意メッセージを公開する。
4. アプリの年齢レーティングに適合するブロックコントロールを設定する。
5. 実機をテストデバイス登録し、本番広告を自分でクリックしない。
6. App Store提出用ArchiveのPrivacy ReportとApp Privacy回答を一致させる。

## 公式参照

- https://developers.google.com/admob/ios/quick-start
- https://developers.google.com/admob/ios/banner
- https://developers.google.com/admob/ios/privacy
- https://developers.google.com/admob/ios/privacy/data-disclosure
- https://developer.apple.com/app-store/review/guidelines/
