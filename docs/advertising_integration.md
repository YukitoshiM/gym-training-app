# BodyMode 広告連携設計

更新日: 2026-08-14

## 方針

- 広告はiPhoneアプリの共通ルート上部に1枠だけ固定し、主要タブとその配下画面で継続表示する。
- Apple Watch、Widget、通知、利用規約への同意前、広告同意が得られていない状態には表示しない。
- 自動表示する全画面広告、App Open、折りたたみ広告は使用しない。ユーザーがAIクレジット獲得を選んだ場合だけ報酬動画を表示する。
- パーソナライズを無効化し、First-party IDとクロスアプリ追跡を使用しない。
- SDKの最大広告コンテンツレーティングを`T`へ制限する。一般的な健康・スポーツ広告を許可しつつ、成人向け広告は配信しない。
- HealthKit、身体値、食事、写真、トレーニング、睡眠、心拍、疲労、目標、位置を広告リクエストへ入れない。

## 構成

| 要素 | 実装 |
|---|---|
| 配信 | Google Mobile Ads SDK 13.7.0 |
| 同意 | Google User Messaging Platform 3.1.0 |
| 広告形式 | Anchored adaptive banner、任意のrewarded video |
| 表示位置 | iPhoneの共通ルート上部。主要タブとその配下画面で固定 |
| 起動タイミング | BodyMode利用規約へ同意後 |
| 失敗時 | 固定枠を維持して60秒後に再試行し、記録機能は継続 |
| 報告 | 設定画面から報告文を送信 |

`AdvertisingManager` は起動ごとにUMPの同意情報を更新する。`canRequestAds`が`true`になるまでGoogle Mobile Ads SDKを初期化せず、広告をリクエストしない。

固定バナーはタブ切替で再生成せず、同じ広告ビューを維持する。画面遷移ごとの過剰なリクエストを避け、読み込み失敗時の再試行間隔は60秒以上とする。誤タップを避けるため、広告をタブバーや入力ボタンの間に挟まず、境界線でアプリの操作領域と分離する。

報酬動画は表示前にサーバーから匿名チャレンジIDを取得し、AdMob Server-Side Verificationの`custom_data`へ設定する。GoogleのECDSA署名、広告ユニットID、時刻、チャレンジ、取引IDをサーバーで検証した後だけ5クレジットを付与する。端末の視聴完了通知だけでは付与しない。1日3回を上限とし、動画を閉じても通常機能を妨げない。

## 収益運用

初期目標は、広告収益でBodyModeの保守・配布・サーバー運用費の一部または全部を賄うこととする。AdMobで広告リクエスト数、マッチ率、表示回数、1日利用者あたり表示回数、eCPM、推定収益を週次確認し、月間運用費と比較する。広告クリックを促す表示や文言は使用せず、収益不足時は利用体験を損なう広告増量より、任意の広告非表示課金や有料AI機能を別途検討する。

AI利用枠、匿名の推論負荷集計、有料AIを検討する条件は`ai_usage_and_monetization_plan.md`を正本とする。広告データとAI利用データを個人単位で結合しない。

## データ

Google Mobile Ads SDKは広告配信のため、IPアドレスからの概算位置、SDKのクラッシュ・パフォーマンス情報、端末識別子、広告表示情報、広告との操作を取得する場合がある。実際のReleaseビルドのPrivacy ReportとGoogleの最新データ開示資料を照合し、App Store ConnectのApp Privacyへ反映する。

BodyModeは`publisherPrivacyPersonalizationState = .disabled`、`setPublisherFirstPartyIDEnabled(false)`、`maxAdContentRating = .teen`、`npa=1`を設定する。ATTは要求せず、`NSUserTrackingUsageDescription`も追加しない。

## 設定

DebugはGoogle公式デモIDを`Config/App.Debug.xcconfig`から読み込む。ReleaseはGit管理外の`Config/Ads.local.xcconfig`を使用する。

```sh
cp Config/Ads.local.xcconfig.example Config/Ads.local.xcconfig
```

必要な値:

```text
BODYMODE_ADMOB_APP_ID = ca-app-pub-...~...
BODYMODE_ADMOB_BANNER_AD_UNIT_ID = ca-app-pub-.../$()...
BODYMODE_ADMOB_REWARDED_AD_UNIT_ID = ca-app-pub-.../$()...
```

`/$()`は`xcconfig`が`//`以降をコメントと解釈するのを防ぐ。本番提出でGoogleのデモIDを使用しない。

## AdMob側の状態

完了:

1. BodyModeを未公開iOSアプリとしてAdMobへ登録した。
2. 常時表示用バナー広告ユニット`BodyMode Persistent Banner`を作成した。
3. 本番App IDとBanner IDをGit管理外の`Config/Ads.local.xcconfig`へ設定した。
4. アプリ個別の最大広告コンテンツレーティングを`T`に設定し、`MA`広告をブロックした。
5. 標準カテゴリは収益性とのバランスを取り、消費者金融、短期収益、性的表現、扇情的表現、ソーシャルカジノの5件だけをブロックした。アルコールと18歳以上のギャンブルは既定のブロックを維持する。
6. AdMobの支払いプロフィールを登録し、未完了警告が消えたことを確認した。
7. EEA、英国、スイス向けのEuropean regulationsメッセージを英語・日本語、同意・拒否・詳細設定の3択で公開した。
8. 報酬動画広告ユニット`BodyMode AI Credits Rewarded`を作成し、報酬を5 AI Creditsに設定した。
9. SSV callback URLを公開ゲートウェイへ設定し、AdMobの検証を完了した。
10. アプリとサーバーへ同じ報酬動画広告ユニットIDを設定し、`verify_rewarded_ad_readiness.sh`が通ることを確認した。

AdMobのURL検証は、固定の検証用広告・取引IDを使い`custom_data`を付けない。ゲートウェイはGoogleの検証用User-Agentと固定値がすべて一致する場合だけ副作用なしでHTTP 200を返す。実広告は従来どおり、オリジンサーバーで署名、広告ユニットID、チャレンジ、取引IDを検証してからクレジットを付与する。

残作業:

1. `app-ads.txt`はリポジトリ直下と`docs/`へ保持し、`https://yukitoshim.github.io/app-ads.txt`へ公開済み。HTTP 200と指定行の完全一致を確認済みで、AdMob側の認証表示は次回クロール後に確認する。
2. App Store公開後、AdMobのアプリをStore掲載情報へリンクして審査を完了する。
3. 実機をテストデバイス登録し、本番広告を自分でクリックしない。
4. App Store提出用ArchiveのPrivacy ReportとApp Privacy回答を一致させる。

## 公式参照

- https://developers.google.com/admob/ios/quick-start
- https://developers.google.com/admob/ios/banner
- https://developers.google.com/admob/ios/rewarded
- https://developers.google.com/admob/ios/ssv
- https://developers.google.com/admob/ios/privacy
- https://developers.google.com/admob/ios/privacy/data-disclosure
- https://developer.apple.com/app-store/review/guidelines/
