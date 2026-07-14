# Apple Watch連携 W1設計

作成日: 2026-07-14
対象: Apple Watchでのジム中トレーニング管理
前提: iPhoneアプリのMVP Core/G1〜G5が完了している状態

## 1. 方針

Apple Watch連携では、iPhoneアプリを置き換えない。役割を分ける。

| デバイス | 主な役割 |
|---|---|
| iPhone | 計画作成、種目編集、履歴確認、身体/食事/写真、AI分析 |
| Apple Watch | ジム中のセット完了、重量/回数微修正、RPE入力、休憩タイマー、終了操作 |

Apple Watch側の価値は「ジム中にiPhoneを触らず、迷わず記録できること」である。

最初からApple標準ワークアウトアプリを置き換えない。まず筋トレ記録体験を作り、その後HealthKit連携を追加する。

## 2. 実装順

### W1: 設計

- Apple Watchの画面構成を決める
- iPhone/Watchの責務を分ける
- 同期方式を決める
- 既存モデルへの差分を決める
- W2以降の受け入れ基準を決める

### W2: Watch Appターゲット追加

- watchOS Appターゲットを追加する
- WatchConnectivityの接続層を作る
- iPhoneから今日の計画をWatchへ送る
- Watchで計画名、種目、セット目標を表示する

### W3: Watch記録MVP

- Watchでセット完了できる
- 重量/回数を微修正できる
- RPEを入力できる
- 休憩タイマーを開始/停止できる
- Watchで終了した実績をiPhoneへ戻せる

### W4: Apple連携

- HealthKit権限を追加する
- 必要に応じてHKWorkoutSessionを開始する
- 心拍、運動時間、消費カロリーを取得または保存する
- Apple標準ワークアウトアプリとの共存方針を確定する

## 3. W1で決めるMVP体験

### 3.1 ジム前

1. iPhoneでトレーニング計画を作る
2. iPhoneの「記録」または「計画」からWatchへ送る
3. Watchに今日のメニューが表示される

### 3.2 ジム中

1. Watchで種目を見る
2. 現在セットの目標重量/回数を見る
3. 必要なら重量/回数を微修正する
4. セット完了を押す
5. RPEを選ぶ
6. 休憩タイマーが始まる
7. 次セットへ進む

### 3.3 ジム後

1. Watchでワークアウト終了
2. 実績をiPhoneへ送る
3. iPhoneの履歴に保存される
4. 既存の履歴、日別ジャーナル、週次分析、AIレポートに反映される

## 4. Watch画面構成

| 画面 | 目的 | 主なUI |
|---|---|---|
| 今日のメニュー | 開始前の確認 | 計画名、種目数、セット数、開始ボタン |
| 種目一覧 | 全体把握 | 種目名、完了セット数、残りセット数 |
| セット記録 | 中核画面 | 種目名、セット番号、目標、実績、完了ボタン |
| 数値調整 | 重量/回数修正 | StepperまたはDigital Crown、+/-ボタン |
| RPE入力 | 体感強度の記録 | 6〜10の選択、スキップ可 |
| 休憩タイマー | セット間管理 | 残り秒数、一時停止、スキップ |
| 完了確認 | 保存前確認 | 達成セット数、総ボリューム、終了ボタン |

## 5. Watch記録画面の操作原則

- 一番大きい操作は「セット完了」にする
- 重量/回数は目標値を初期値にする
- 微修正は1〜2タップでできるようにする
- RPEは必須にしない
- 休憩タイマーは自動開始するが、停止/スキップできるようにする
- 種目追加や計画編集はWatchでは扱わない
- 入力ミス修正は最低限、詳細編集はiPhone側に任せる

## 6. 同期方式

### 6.1 採用方針

W2/W3ではWatchConnectivityを使う。

| 用途 | API方針 | 理由 |
|---|---|---|
| 直近状態の即時送信 | `sendMessage` | iPhone/Watchが両方起動中なら即時性が高い |
| 確実に届けたい実績 | `transferUserInfo` | バックグラウンド転送のキューに載せられる |
| 画像や大きいデータ | 対象外 | Watch MVPでは扱わない |

Apple公式ドキュメントでは、WatchConnectivityの `transferUserInfo(_:)` は辞書をキューに入れて相手側へ届ける用途に使える。ただしSimulatorではこの転送の検証に制限があるため、実機ペアでの確認をW3の完了条件に入れる。

### 6.2 同期イベント

| イベント | 方向 | 内容 |
|---|---|---|
| `watch_plan_push` | iPhone -> Watch | 今日の計画、種目、セット目標、休憩秒数 |
| `watch_session_started` | Watch -> iPhone | Watchで開始した時刻 |
| `watch_set_updated` | Watch -> iPhone | セットの重量、回数、完了、RPE |
| `watch_rest_timer_changed` | Watch内部 | 原則ローカル。iPhone同期は不要 |
| `watch_session_finished` | Watch -> iPhone | 完了したWorkoutSession |
| `watch_session_cancelled` | Watch -> iPhone | 保存せず終了したこと |

### 6.3 競合方針

MVPでは「Watchで実行中のセッション」を主とする。

- Watch実行中はiPhone側で同じセッションを編集しない
- iPhone側には「Watchで記録中」の状態表示だけ出す
- Watchから完了実績を受け取ったらiPhoneの履歴へ保存する
- 受信済みイベントは `sessionID + eventID` で重複排除する
- Watch側に未送信実績がある場合、次回起動時に再送する

## 7. データモデル差分

現行モデルは以下の形でWatchに渡しやすい。

- `TrainingPlan`
- `PlanExercise`
- `PlanSetTarget`
- `WorkoutSession`
- `WorkoutExercise`
- `WorkoutSet`

W3で追加したい最小差分は以下。

| モデル | 追加候補 | 理由 |
|---|---|---|
| `WorkoutSet` | `rpe: Double?` | Watchで体感強度をセット単位で残す |
| `WorkoutSet` | `completedAt: Date?` | セット間隔や実施順の検証に使う |
| `WorkoutSession` | `sourceDevice: WorkoutSourceDevice` | iPhone/Watchどちらで記録したか分かる |
| `WorkoutSession` | `watchSyncState: WatchSyncState?` | 未送信/送信済み/競合などを扱う |

後方互換のため、既存JSON decodeでは追加項目を任意扱いにする。

## 8. HealthKit/Apple標準ワークアウトとの関係

W1〜W3ではHealthKitを必須にしない。理由は、最初に検証したい価値が「筋トレセットの記録しやすさ」だからである。

W4では2案を比較する。

| 案 | 内容 | メリット | 注意点 |
|---|---|---|---|
| A: Apple標準ワークアウト併用 | ユーザーはApple標準ワークアウトで筋トレを開始し、本アプリWatchではセット記録だけ行う | 実装が軽い。Appleの心拍/消費カロリー計測に任せられる | セット単位の心拍紐付けは弱い |
| B: 本アプリがHKWorkoutSession開始 | 本アプリWatch内で筋トレワークアウトを開始し、HealthKitへ保存する | セット記録と心拍/時間を同一体験にできる | HealthKit権限、バックグラウンド、終了復旧、バッテリー配慮が必要 |

Apple公式ドキュメントでは、HKWorkoutSessionはApple Watch上でユーザーの活動を追跡し、セッション中はセンサーを活動に合わせて調整する用途のAPIである。W4ではHKWorkoutSessionとHKLiveWorkoutBuilderを調査・実装対象にする。

## 9. W2実装タスク

1. XcodeプロジェクトにwatchOS Appターゲットを追加
2. 共有モデルの配置方針を決定
3. WatchConnectivity wrapperをiPhone/Watch双方に追加
4. `WatchPlanSnapshot` DTOを作る
5. iPhoneからWatchへ計画を送るボタンまたは自動同期を追加
6. Watchで今日の計画を表示
7. WatchConnectivityの実機検証メモを追加

## 10. W3実装タスク

1. WatchでWorkoutSessionを開始
2. セット記録画面を作る
3. 重量/回数の微修正UIを作る
4. セット完了とRPE入力を作る
5. 休憩タイマーを作る
6. Watch側に未送信セッションを一時保存
7. iPhoneへ完了セッションを送信
8. iPhone側で履歴に保存
9. UIテスト/手動実機テスト手順を追加

## 10.1 W2実装メモ

実装日: 2026-07-14

- `GymTrainingWatchApp` ターゲットを追加した
- iPhone/Watch共通DTOとして `WatchWorkoutPlanSnapshot` を `Shared/` に追加した
- iPhone側に `WatchPlanSyncService` を追加し、`sendMessage` と `transferUserInfo` で計画を送れるようにした
- 記録タブに「Apple Watchへ計画を送信」カードを追加した
- Watch側に受信した計画、種目、セット目標を表示する画面を追加した
- Watch側では最後に受信した計画を `UserDefaults` に保存し、再起動後も表示できるようにした

検証:

- `xcodebuild -project GymTrainingApp.xcodeproj -target GymTrainingWatchApp -sdk watchsimulator26.5 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`
- `xcodebuild -project GymTrainingApp.xcodeproj -scheme GymTrainingApp -destination 'platform=iOS Simulator,id=4008EC67-FCFD-40C4-9202-9D7BEC14E346' build`
- `xcodebuild test -project GymTrainingApp.xcodeproj -scheme GymTrainingApp -destination 'platform=iOS Simulator,id=4008EC67-FCFD-40C4-9202-9D7BEC14E346'`

補足:

- 現在のMacではWatch Simulatorデバイスが `simctl` に出ていないため、Watch Appの起動確認とWatchConnectivityの疎通確認は実機ペアで行う
- XcodeGenではSwiftUI Watch Appとして `type: application` + `platform: watchOS` で生成している
- 配布前にWatch App用の正式なAppIconを追加する

## 11. W4実装タスク

1. HealthKit capabilityを追加
2. HealthKit権限文言をInfo.plistに追加
3. HKWorkoutSessionを使う案Bのプロトタイプを作る
4. Apple標準ワークアウト併用案Aと体験比較する
5. 心拍、時間、消費カロリーをWorkoutSessionに紐付ける設計を追加
6. HealthKit保存/読み取りの失敗UXを作る

## 12. W2受け入れ基準

- Watch Appターゲットがビルドできる
- Watchで今日の計画名が見える
- Watchで種目名とセット目標が見える
- iPhone側の既存テストが通る
- 実機ペアでWatchConnectivityの疎通確認手順がある

## 13. W3受け入れ基準

- Watchだけで計画の全セットを完了できる
- 重量/回数をWatchで修正できる
- RPEを任意入力できる
- 休憩タイマーがWatch上で動く
- 完了したセッションがiPhone履歴に保存される
- オフライン/未到達時に再送できる

## 14. W4受け入れ基準

- HealthKit権限をユーザーが理解できる文言で出せる
- 心拍またはワークアウト時間を取得できる
- Apple標準ワークアウト併用案と本アプリ開始案のどちらで進むか判断できる
- HealthKit連携が失敗しても筋トレ記録自体は失われない

## 15. 参考にしたApple公式情報

- [HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession)
- [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [transferUserInfo(_:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo%28_%3A%29)
- [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
