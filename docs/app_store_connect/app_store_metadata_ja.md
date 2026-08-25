# BodyMode App Storeメタデータ

更新日: 2026-08-21

Appleの文字数上限に収まる日本語原稿。角括弧だけ運営者が確定する。

## 基本情報

- アプリ名: `BodyMode`
- サブタイトル: `AIコーチと今日の3つを実行`
- 主カテゴリ: `ヘルスケア／フィットネス`
- 副カテゴリ: `ライフスタイル`
- SKU案: `bodymode-ios-001`
- Bundle ID: `com.yukitoshim.gymtrainingapp`
- Copyright: `2026 Murase Yukitoshi`
- Made for Kids: いいえ

## プロモーションテキスト

12人のAIコーチから理想に近い担当を選び、今日やることを最大3つに。食事・身体・運動をiPhoneとApple Watchで迷わず続けられます。

## 説明

BodyModeは、自分の身体について「今日何をすればいいか」を分かりやすくする健康・フィットネスアプリです。

理想の身体や目的に合う12人のコーチから担当を選択。体重、食事、睡眠、疲労、活動、トレーニング履歴をもとに、今日の調子と優先アクションを最大3つに整理します。詳細な記録や分析は必要な時だけ確認できます。

主な機能

・今日の調子と「今日やること」最大3件
・個性と専門性を持つ12人のAIコーチ
・体重、腹囲、体脂肪率、各部位の記録とグラフ
・食事写真のAI推定、手動補正、カロリー・PFC記録
・複数方向の体型写真をまとめたAI参考分析
・豊富な種目から作るトレーニング計画
・セットごとの重量、回数、RPE、休憩時間の記録
・計画と実績の差分、PR、ボリュームの確認
・睡眠、活動、回復状態をまとめたコンディション表示
・Apple Watchでのメニュー選択、セット操作、テンポ触覚、休憩タイマー
・Apple Healthとの任意連携
・ライト／ダークモードと2種類のカラーテーマ
・全記録のJSON書き出しと端末内データ削除

アカウント登録は不要です。記録は主に端末内へ保存され、Apple HealthやAIを使わなくても手動記録を利用できます。

AI機能は通信を必要とします。AIへ送る記録カテゴリは設定で管理でき、写真解析はユーザーの明示操作で実行します。AIが利用できない場合も手動記録、履歴、トレーニング、Apple Watch連携を利用できます。AIの推定や提案は参考情報であり、ユーザーが確認・修正できます。

BodyModeは医療機器ではなく、診断、治療、疾病の判定を行いません。体調に不安がある場合は医療専門家へ相談してください。

## キーワード

`筋トレ,健康管理,体重,腹囲,食事,PFC,ワークアウト,睡眠,体型`

UTF-8で80バイト。Appleの100バイト上限内。

## App Privacy回答案

現在のRelease仕様はiPhoneにGoogle Mobile Ads SDKとUMP SDKを含む。アプリ独自の利用分析は初期オフで、ユーザーが明示同意した場合だけ匿名化した固定区分イベントを送信する。クラッシュ診断は自動送信しない。AIはユーザーが有効化した機能の明示操作で、設定された接続先へ送信する。

回答案:

- 「このAppからデータを収集しますか」: `はい`
- 広告SDK分: 概算位置、端末ID、広告データ、製品との操作、クラッシュ、パフォーマンス、その他の診断を申告
- トラッキング: Google Mobile Ads SDK 13.7.0のManifestがDevice IDをTrackingありと宣言しているため、`app_privacy_answers_ja.md`の残件を確定してから入力
- 利用目的: 第三者広告、開発者の広告・マーケティング、アナリティクス、アプリの機能のうちGoogleの開示に対応する項目

健康・フィットネス、食事、写真、位置履歴は広告リクエストへ入れない。最終回答は、Googleの最新データ開示、AdMob管理画面の有効機能、Xcode OrganizerのPrivacy Reportを照合して確定する。

## 年齢レーティング回答案

詳細は`app_declarations_ja.md`を正本とする。

- Advertising: あり
- Health or Wellness Topics: あり
- Medical or Treatment Information: なし
- UGC、ユーザー同士のMessaging and Chat、Social Media: なし
- ギャンブル、性的表現、暴力、薬物、成人向けコンテンツ: なし
- Made for Kids: いいえ
- 想定レーティング: iOS 26以降で9+

## 審査情報

App Privacyの転記内容は`app_privacy_answers_ja.md`、詳細なReview Notesは`testflight_metadata_ja.md`を使用する。

- Review contact: `[氏名、電話、メール]`
- Privacy Policy URL: `https://yukitoshim.github.io/gym-training-app/privacy/`
- Support URL: `https://yukitoshim.github.io/gym-training-app/support/`
- Terms URL: `https://yukitoshim.github.io/gym-training-app/terms/`
- Support contact: `https://github.com/YukitoshiM/gym-training-app/issues/new`

## スクリーンショット構成

6.9インチiPhone向けに8枚を用意する。

1. ホーム: 今日の調子と今日の3つ
2. AIコーチ: 12人から理想と相性で選択
3. AI機能: チャット、食事写真、体型写真
4. トレーニング: 計画からセット実行まで
5. 履歴: 種類が分かるカレンダーと完了詳細
6. 身体: 体重・腹囲の推移
7. 計画: 種目とセットを組み立てる
8. 記録ハブ: 身体・食事・写真・運動の入口

Apple Watchは、今日のメニュー、セット実行、休憩タイマーが分かる画像を用意する。
