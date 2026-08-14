# BodyMode ドキュメント索引

更新日: 2026-08-14

迷った場合は、この順に確認する。

1. `current_product_specification.md`: 次回配布向け現行ソースのプロダクト仕様
2. `omakase_mode_specification_v2.md`: 今日の3つを中心にした最上位UXの正本
3. `master_task_list_2026-08-13_draft.md`: 全要望、状態、完了条件の統合台帳
4. `testflight_feedback_ledger.md`: 全フィードバック、重複、再発、解決済みアーカイブの正本
5. `implementation_execution_plan_2026-08-13.md`: 実装順、ビルド、担当、テスト、公開ゲート
6. `release_readiness_plan.md`: リリース状態、残作業、担当の正本
7. `mvp_requirements.md`: 要件と受け入れ条件の詳細
8. `architecture.md`: コードの責務、依存方向、変更先の正本
9. `feature_map.md`: 機能から実装・テストを探す索引
10. `privacy_data_inventory.md`: 保存・送信・保持・削除の正本
11. `testflight_release_plan.md`: TestFlight提出手順
12. `ai_server_integration.md`: AI APIの通信、画像前処理、設定、エラー処理
13. `ai_trainer_integration.md`: AIトレーナーの会話、文脈、記憶、保持設計
14. `coach_character_reference_2026-08-13.md`: AIトレーナーの人物、話し方、専門性の設計
15. `advertising_integration.md`: 広告配信、同意、データ分離、AdMob設定
16. `regression_testing_policy.md`: L0〜L3の回帰範囲を決める強制条件と判定スコア
17. `regression_report_2026-08-13.md`: iPhone最大2台と後続Watchによる複数エージェント回帰の結果と運用方法
18. `evidence_rag_design.md`: 目的別学術文献収集、sqlite-vec検索、引用、安全境界の正本
19. `device_log_analysis_2026-08-14.md`: Build 14実機ログ、AI失敗、体型写真保存、クラッシュの解析結果

リファクタリングの行数とコンテキスト削減効果は`refactor_impact_2026-08-03.md`に記録している。

## プロダクト

- `ai_bodymake_manager_product_plan.md`: 中長期の製品方針
- `ai_coach_social_monetization_design.md`: AI、SNS、収益化の将来設計
- `s59_growth_implementation_backlog.md`: S59以降の成長機能候補
- `apple_watch_sensor_user_stories.md`: Watchセンサー活用のユーザーストーリー
- `competitive_research.md`: 競合調査メモ。仕様の正本ではない

## リリース

- `app_store_launch_checklist.md`: App Store公開チェック
- `app_store_connect/`: ストア説明文とTestFlightメタデータ
- `app-store/`: 提出用スクリーンショット
- `legal/`: 利用規約、プライバシーポリシー、サポート原稿
- `ios_environment_setup.md`: 開発環境と実機導入
- `third_party_notices.md`: ローカルAIサーバーを含む第三者OSSの告知

## Archive

`archive/`は実装済みフェーズの判断経緯を残す場所であり、現行仕様ではない。新しい実装判断に使う場合は、上記の正本と現在のコードを優先する。
