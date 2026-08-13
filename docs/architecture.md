# BodyMode アーキテクチャ

更新日: 2026-08-13

## 方針

- ローカルファーストで、AIやネットワークがなくても記録を完結できる。
- SwiftUI Viewは表示とユーザー操作に集中し、保存処理を直接持たない。
- `AppStore`は画面向けのFacadeとし、永続化は`AppDataRepository`経由で行う。
- 日次提案は`DailyRecommendationEngine`が純粋なローカル判断と完了判定を担い、`AppStore+DailyRecommendation`が安定化、履歴、AI補正を調停する。
- 食事栄養は、同梱した文科省食品成分表と端末内バーコード商品辞書からローカル計算し、AI推定を栄養値の唯一の根拠にしない。
- Watchのセット状態遷移は`WatchWorkoutSessionReducer`、HealthKitや通信などの副作用は`WatchWorkoutStore`が担当する。
- iPhoneとWatchで共有する転送モデルだけを`Shared/`へ置く。

## iPhone

| 層 | 場所 | 責務 |
|---|---|---|
| App | `GymTrainingApp/App` | 起動、依存生成、タブ構成 |
| Features | `GymTrainingApp/Features` | 機能別の画面と画面ロジック |
| State Facade | `GymTrainingApp/Data/AppStore*.swift` | 画面状態、ユースケース、保存の調停 |
| Repository | `GymTrainingApp/Data/Persistence` | 永続化契約、保護JSONストレージ |
| Services | `GymTrainingApp/Data` | HealthKit、WatchConnectivity、AI、位置情報 |
| Domain | `GymTrainingApp/Domain` | iPhone固有の値・集計モデル |
| Support | `GymTrainingApp/Support` | 診断、テーマ、入力部品、保護ファイル |

`AppStore.swift`は初期ロードと状態定義だけを持つ。処理の追加先は、身体・食事、ワークアウト、プロフィール・回復、データ管理の各拡張ファイルから選ぶ。

## Apple Watch

| ファイル | 責務 |
|---|---|
| `WatchWorkoutStore.swift` | 公開状態、初期化、ワークアウト操作 |
| `WatchWorkoutStore+HealthKit.swift` | HealthKitワークアウトの開始・終了・保存 |
| `WatchWorkoutStore+Sensors.swift` | 心拍、モーション、回復、提案 |
| `WatchWorkoutStore+Persistence.swift` | 復元、保存、休憩タイマー |
| `WatchWorkoutStore+Connectivity.swift` | iPhone同期、ライブ更新、コマンド受信 |
| `WatchDiagnostics.swift` | ワークアウト操作・HealthKit・通信ログの14日間キュー |
| `WatchWorkoutSessionReducer.swift` | セット状態の純粋な遷移 |
| `Views/` | 実行画面、セット操作、数値エディタ |

## データフロー

```text
SwiftUI View -> AppStore / WatchWorkoutStore -> Repository / Service
                                             -> Published state -> SwiftUI View

iPhone WatchPlanSyncService <-> WatchConnectivity <-> WatchWorkoutStore
WatchWorkoutStore -> HealthKit / Motion -> session snapshot -> iPhone history
WatchDiagnostics -> WatchConnectivity queued transfer -> iPhone AppDiagnostics -> user export/share
```

AIトレーナーは`AITrainerBackgroundService`のバックグラウンド`URLSession`で送信し、完了結果を端末内へ一時保存して`AppStore`へ反映する。画面のライフサイクルから通信を分離している。

おまかせモードの日次フロー:

```text
Local records + HealthKit + Profile
                -> DailyRecommendationEngine
                -> DailyRecommendation (max 3 actions)
                -> Home / Watch
                -> AITrainerBackgroundService
                -> meaningful-change gate
                -> RecommendationRevision + updated Home / Watch
```

ローカル提案が先に表示されるため、AI通信はホーム表示の依存条件ではない。記録追加時は既存アクションの進捗を同期し、安全上重要な変化または明示的なユーザー変更がある場合だけアクションを再構成する。

食事の栄養計算:

```text
MEXT bundled catalog / Local barcode product
                -> MealCompositionItem x actual grams
                -> deterministic NutritionAmount total
                -> editable MealEntry
```

食品成分表の未測定値はゼロの実測値へ変換せず、品質メタデータと注意表示を保持する。バーコード商品辞書は保護領域へ保存し、全データ削除とJSON書き出しの対象にする。

## 変更ルール

1. 新しい保存項目はDomainモデル、Repository契約、LocalJSONStorage、データ書き出し、プライバシー台帳を同時に確認する。
2. セットの状態変更はReducerへ追加し、Storeにはハプティクス・HealthKit・通信などの副作用だけを残す。
3. 共有モデルへUI文言やView状態を入れない。
4. 機能追加時は該当するUIテストクラスへ追加し、純粋な状態遷移は単体テストへ追加する。
5. リリース判断は`release_readiness_plan.md`だけを更新し、完了済み台帳を現行仕様へ戻さない。
