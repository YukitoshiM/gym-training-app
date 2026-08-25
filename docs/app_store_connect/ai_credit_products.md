# AIクレジット商品登録仕様

更新日: 2026-08-23

App Store Connect登録状態: 3商品とも商品、日英ローカリゼーション、米国基準価格、175地域、審査用スクリーンショットを登録済み。Production / SandboxのApp Store Server Notifications V2 URLも登録済み。

更新日: 2026-08-21

商品種別はすべて消耗型IAPとする。サブスクリプション、自動更新、無料の日次補充は行わない。

| 商品ID | 表示名（日本語） | 表示名（英語） | 米国価格案 | 日本価格案 | 1クレジット単価 |
|---|---|---|---:|---:|---:|
| `com.yukitoshim.gymtrainingapp.credits50` | AIクレジット 50 | 50 AI Credits | $1.99 | ¥300 | 約¥6.0 |
| `com.yukitoshim.gymtrainingapp.credits150` | AIクレジット 150 | 150 AI Credits | $4.99 | ¥700 | 約¥4.7 |
| `com.yukitoshim.gymtrainingapp.credits500` | AIクレジット 500 | 500 AI Credits | $12.99 | ¥1,800 | 約¥3.6 |

初回登録の20クレジットは、最小商品を基準に約¥120相当となる。ただしアプリ内では現金価値を主表示せず、「初回20 AIクレジット」と表示する。

## 説明文

### 50クレジット

- 日本語: AIトレーナーの相談、食事・写真分析、計画作成などに使えます。
- 英語: AI coaching, meal photos, body photos, and plans.

### 150クレジット

- 日本語: AIトレーナーを継続的に活用できる150クレジットです。
- 英語: Use AI coaching and analysis more often.

### 500クレジット

- 日本語: AIトレーナーと各種分析を多く利用する方向けの500クレジットです。
- 英語: For frequent AI coaching and analysis.

## 登録・審査条件

1. 3商品を消耗型として作成する。
2. 日本語と英語の表示名・説明を登録する。
3. 全公開地域を販売対象にする。
4. 税カテゴリと価格ポイントを確認する。
5. 完了。AIクレジット購入画面の英語スクリーンショットを各商品へ登録し、Apple側の処理状態`COMPLETE`を確認する。
6. Sandboxで成功、取消、保留、重複送信、通信失敗を確認する。消耗型商品自体の「購入を復元」は行わず、再インストール・別端末相当では同じAppleアカウントからサーバー残高を再取得できることを確認する。
7. Server Notifications V2のProduction・Sandbox URLをGatewayの通知エンドポイントへ設定する。

ローカル検証用の商品定義は `Config/BodyMode.storekit` を正本とし、本番登録後はApp Store Connectの設定との差分を確認する。

`scripts/configure_ai_credit_products.py`は同設定から商品ID、参照名、クレジット数、日本語・英語の商品名と説明を読み取る。通常実行は読み取り専用で、`--apply`を明示した場合だけ不足する商品とローカリゼーションを作成する。既存値が異なる場合は上書きせず競合として停止する。

`scripts/test_configure_ai_credit_products.py`でiOS、AIサーバー、本書との不一致とApp Store Connect用ペイロードを検査し、この検査はTestFlight配布前チェックでも実行する。2026-08-21時点の読み取り確認では3商品とも未登録である。
