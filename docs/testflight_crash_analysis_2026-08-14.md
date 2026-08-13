# TestFlightクラッシュ調査 2026-08-14

## 結論

TestFlight Build 13のおまかせホームで、通知最適化データの読み書きが循環待ちになり、iOSのwatchdogに強制終了されていた。通知計測をMainActorへ統一し、通知登録の完了コールバックもMainActorへ戻してから保存するよう修正した。

## 取得結果

- App Store Connect API: スクリーンショットフィードバック14件、クラッシュ提出0件
- 実機端末内MetricKit: 同一原因のクラッシュ2件
- アプリ: BodyMode 0.1.0 (13)、TestFlight
- 端末: iPhone 14 (`iPhone14,7`)、iOS 26.5.2
- 終了理由: `0x8BADF00D`、`scene-update watchdog transgression`、deadlock
- 発生時刻: 2026-08-14 00:55、00:56（端末時刻）

## シンボル化結果

メインスレッドは次の経路で通知計測用キューの完了を待っていた。

```text
HomeView.refreshDailyRecommendation(force:)
DailyRecommendationNotificationManager.schedule(recommendation:)
DailyRecommendationNotificationManager.shouldScheduleEvening
DispatchQueue.sync
```

同時に通知登録の完了コールバックは、同じ計測用キュー上で`appendRecord`から`UserDefaults`を更新していた。`UserDefaults`の変更通知がSwiftUI側の処理を必要としたため、メインスレッドとの循環待ちになった。

## 修正

- `DailyRecommendationNotificationManager`を`@MainActor`へ分離
- 通知計測用の同期DispatchQueueを廃止
- `UNUserNotificationCenter.add`の完了コールバックをMainActorへ戻して保存
- 通知計測テストをMainActor上で実行
- おまかせホームUIテストを通知有効状態で起動

## 検証

| 対象 | 結果 | 件数 |
|---|---|---:|
| `DailyRecommendationPersonalizationTests` | 成功 | 7/7 |
| 通知有効のおまかせホームUI | 成功 | 1/1 |

TestFlight Build 14で同じ操作を行い、端末内MetricKitとApp Store Connectのクラッシュ提出に再発がないことを確認する。
