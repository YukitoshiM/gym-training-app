# 競合アプリ参考メモ

作成日: 2026-07-04  
対象: トレーニング記録アプリ MVP / V1

## 1. 目的

既存の筋トレ記録アプリから、MVPに取り込むべき機能と後回しにする機能を整理する。

本アプリは、初期段階では「多機能な総合フィットネスアプリ」ではなく、ジム中の記録負荷を下げ、前回実績を見ながら継続的に重量・回数を伸ばすアプリとして設計する。

## 2. 参考アプリ

| アプリ | 確認できる主な機能 | 本アプリへの示唆 |
|---|---|---|
| 筋トレMEMO | 重量/回数記録、グラフ分析、有酸素記録、種目別履歴、RM計算、セット間タイマー、前回履歴コピー | ジム中の入力負荷削減と履歴再利用が重要 |
| Strong | シンプルな記録UI、ルーティン作成、Apple Watch、統計、1RM、休憩タイマー、セット種別、スーパーセット、グラフ、Cloud Sync、プレート計算、CSV出力 | 上級者向け機能は多いが、MVPでは前回値、タイマー、グラフが優先 |
| Hevy | ルーティン、カレンダー、動画、友人フォロー、カスタム種目、セット種別、種目別休憩、筋群グラフ、1RM、Health連携 | カレンダー、種目別分析、種目別タイマーは採用価値が高い |
| FitNotes / Fitnotes X | シンプルな記録、カレンダー、進捗グラフ、休憩タイマー、1RM計算、PR検出、動画デモ | 軽量な記録体験とPR検出はV1候補 |
| JEFIT | 記録、計画、既成ルーティン、コミュニティ、トレーナー、筋持久力/筋力評価、Wear OS | 既成ルーティンとコミュニティはMVPでは不要 |
| Fitbod | 目標・経験・器具に合わせたAI生成、回復状態、漸進性過負荷、動画、Apple Health/Strava/Fitbit連携 | AI提案は後回し。まず履歴ベースの次回判断を作る |
| StrongLifts | 5x5プログラム、重量/セット/レップス自動計画、迷わないワークアウト | 初心者向けには「次に何をやるか」の明確化が重要 |
| Burnfit | 簡単入力、自動グラフ、トレーニングプラン自動生成、動画、継続/習慣化 | 入力を邪魔しないUIと自動分析を重視する |

## 3. 横断して重要な機能

| 優先 | 機能 | 理由 | MVP判断 |
|---|---|---|---|
| 1 | 前回実績表示 | 次の重量/回数判断に直結する | 実装済み |
| 2 | 前回値コピー | ジム中の入力負荷を下げる | 実装済み |
| 3 | 種目別履歴 | 履歴一覧だけでは次回判断に弱い | 追加すべき |
| 4 | 週次ボリューム分析 | 疲労管理と成長実感につながる | 追加すべき |
| 5 | セット間タイマー | 記録アプリとして利用頻度が高い | 追加すべき |
| 6 | 自己ベスト/PR検出 | 成長実感を作れる | V1候補 |
| 7 | 1RM/RM計算 | 中上級者には有用 | V1候補 |
| 8 | カレンダー | 継続状況が一目で分かる | 実装済み |
| 9 | カスタム種目 | 種目DB不足を補える | 追加すべき |
| 10 | kg/lb切替 | 国際化・器具単位差に対応 | V1候補 |

## 4. 後回しにする機能

| 機能 | 理由 |
|---|---|
| 友人フォロー/コミュニティ | 初期MVPの価値に直結しない |
| SNS共有 | 記録体験が固まってからでよい |
| AIメニュー生成 | データ量と安全設計が必要。履歴ベース提案の後に検討 |
| Apple Watch / Wear OS | 価値は高いが実装コストが大きい |
| 動画デモ | 種目DB整備後でよい |
| 既成プログラム大量投入 | メンテナンス負荷が高い |
| Cloud Sync | ローカルMVP安定後に実装する |

## 5. 次に実装する順番

1. 種目別履歴
2. 週次ボリューム分析
3. セット間タイマー
4. カスタム種目
5. 自己ベスト/PR検出
6. 1RM/RM計算
7. 目標値コピー

## 6. 参照URL

- 筋トレMEMO: https://apps.apple.com/jp/app/id1109688815
- Strong: https://apps.apple.com/id/app/strong-workout-tracker-gym-log/id464254577
- Strong Google Play: https://play.google.com/store/apps/details?id=io.strongapp.strong
- Hevy: https://www.hevyapp.com/
- Hevy App Store: https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350
- FitNotes: https://www.fitnotesapp.com/
- FitNotes Quick Start: https://www.fitnotesapp.com/quick_start/
- Fitnotes X: https://fitnotesx.com/
- JEFIT: https://www.jefit.com/
- JEFIT Google Play: https://play.google.com/store/apps/details?id=je.fit
- Fitbod: https://fitbod.me/
- Fitbod App Store: https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543
- StrongLifts: https://stronglifts.com/app/
- Burnfit App Store: https://apps.apple.com/jp/app/id1503464984
