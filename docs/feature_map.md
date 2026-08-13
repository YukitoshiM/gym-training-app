# BodyMode 機能マップ

更新日: 2026-08-13

| 機能 | 主な画面 | 状態・サービス | モデル | 自動テスト |
|---|---|---|---|---|
| 初回設定・目標・利用器具 | `Features/Onboarding`, `Features/Settings/ProfileSettingsView` | `InitialSetupStateStore`, `AppStore+ProfileAndRecovery` | `UserProfile`, `OutcomeStyle`, `Equipment`, `BodyMetricModels` | `InitialSetupTests`, `InitialSetupUITests` |
| おまかせホーム・今日の3つ | `Features/Home/OmakaseHomeView`, `Features/Home/HomeView` | `DailyRecommendationEngine`, `AppStore+DailyRecommendation`, `AITrainerBackgroundService`, `DailyRecommendationNotificationManager`, `DailyRecommendationPersonalizationStore` | `DailyRecommendation`, `DailyAction`, `DailyReadiness`, `DailyReview`, `RecommendationRevision` | `DailyRecommendationEngineTests`, `DailyRecommendationPersonalizationTests`, `OmakaseModeUITests` |
| 詳細ホーム・今日の状態 | `Features/Home`, `Features/Health` | `AppStore+ProfileAndRecovery`, `HealthDataManager` | `SensorModels`, `UserProfile` | `IntegrationAndHealthUITests` |
| 計画・種目・フォーム画像 | `Features/Plans`, `Features/Exercises` | `AppStore+Workout`, `PresetExerciseStore` | `Exercise`, `TrainingModels` | `WorkoutFlowUITests`, `ExercisePhotoCatalogTests` |
| AIトレーニング計画 | `Features/Plans/AIPlanCoachView`, `Features/Plans/PlanEditorView`, `Features/Reports/AIHubView` | `AIAPIClient`, `CoachContextBuilder`, `AppStore+Workout` | `AITrainingPlanDraft`, `TrainingModels` | `AITrainingPlanDraftTests`, `AITrainerUITests` |
| iPhoneワークアウト | `Features/Workout` | `AppStore+Workout` | `TrainingModels` | `WorkoutFlowUITests` |
| Watchワークアウト | `GymTrainingWatchApp/Views` | `WatchWorkoutStore*`, `WatchWorkoutSessionReducer` | `Shared/WatchWorkout*` | `GymTrainingWatchAppUITests`, `WatchWorkoutSessionReducerTests` |
| 履歴・分析 | `Features/History` | `AppStore+Workout` | `TrainingModels`, `SensorModels` | `IntegrationAndHealthUITests` |
| 体重・腹囲 | `Features/BodyMetrics` | `AppStore+BodyAndNutrition` | `BodyMetricModels` | `BodyAndNutritionUITests` |
| 食事・食品DB・バーコード | `Features/Meals` | `AppStore+BodyAndNutrition`, `AIAPIClient`, `FoodCompositionDatabase`, `BarcodeFoodProductStore`, `DailyMealSuggestionEngine` | `MealModels`, `FoodCompositionModels` | `FoodCompositionTests`, `BodyAndNutritionUITests`, `AIAPIClientTests` |
| 体型写真 | `Features/BodyPhotos` | `AppStore+BodyAndNutrition` | `BodyPhotoModels` | `BodyAndNutritionUITests` |
| 週次・月次AIレポート | `Features/Reports` | `AIAPIClient`, `AppStore+ProfileAndRecovery` | `AIModels` | `AITrainerUITests`, `IntegrationAndHealthUITests`, `AIAPIClientTests` |
| AIトレーナー | `Features/Reports/AITrainerChatView` | `AIAPIClient`, `AITrainerBackgroundService`, `CoachContextBuilder`, `AppStore+ProfileAndRecovery` | `CoachModels` | `AITrainerUITests`, `AIAPIClientTests`, `CoachContextBuilderTests` |
| 広告・同意・報告 | `Advertising` | `AdvertisingManager`, Google UMP | `AdvertisingConfiguration` | `AdvertisingConfigurationTests`, `SettingsAndAccessibilityUITests` |
| 設定・法務・分析同意 | `Features/Settings` | `AppStore+ProfileAndRecovery`, `UsageAnalytics` | `UserProfile`, `AIModels` | `SettingsAndAccessibilityUITests` |
| 保存・書き出し・削除 | `Features/Settings` | `Data/Persistence`, `AppStore+DataManagement` | `GymDataExport` | `SettingsAndAccessibilityUITests` |

UI回帰テストの共通操作は`GymTrainingAppUITests/GymTrainingAppUITests.swift`にあり、機能別テストは同ディレクトリの各テストクラスへ分かれている。
