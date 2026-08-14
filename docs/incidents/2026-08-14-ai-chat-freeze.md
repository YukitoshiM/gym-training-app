# AIチャット画面フリーズ調査記録

## 概要

- 発生日: 2026-08-14
- 対象: iPhone 14 / iOS 26.5.2 / BodyMode Build 15
- 症状: AIチャット利用後に画面がフリーズし、しばらくするとアプリが終了する
- 判定: AI通信のタイムアウトではなく、メインスレッドと利用分析キュー間のデッドロック

## 根拠

実機から取得した `GymTrainingApp-2026-08-14-180548.ips` は、次の終了理由を示していた。

- `EXC_CRASH / SIGKILL`
- `0x8BADF00D`
- `scene-update watchdog transgression`
- CPU負荷や端末温度による終了ではない

Build 15のdSYMでシンボリケートした結果、メインスレッドは
`AITrainerChatView.responseRating(for:)` から `UsageAnalytics.coachResponseRating(for:)`
を呼び、利用分析キューの `queue.sync` を待っていた。

同時に利用分析キューは `UserDefaults.set` の変更通知からSwiftUIの更新ロックを待っていた。

1. SwiftUIの描画中にメインスレッドが更新ロックを保持する
2. メインスレッドが利用分析キューを同期的に待つ
3. 利用分析キューが `UserDefaults` の通知処理でSwiftUIの更新ロックを待つ
4. 相互待機となり、watchdogがアプリを終了する

## 修正

- 評価値と利用イベントをメモリキャッシュから読み取るように変更
- SwiftUIのView描画中に永続化キューを同期的に待たないように変更
- AIメッセージの評価値をViewの `.task` で一括復元し、描画処理はViewの状態だけを参照
- `UserDefaults`への書き込みを専用シリアルキューへ流し、ロック保持中には実行しない
- 並行してイベントを書き込んでも評価値の読み取りが停止しない単体テストを追加

## 検証

- `UsageAnalyticsTests`: 3件成功
- `AITrainerUITests/testChatReplyAndExplicitMemoryApproval`: 1件成功
- UIテストではAI回答表示、記憶候補の承認、回答評価、画面遷移まで完走

Build 15には修正が含まれないため、実機での最終確認には修正版ビルドの配布が必要。
