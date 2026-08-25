# BodyMode ドキュメント索引

更新日: 2026-08-23

迷った場合は、この順に確認する。

1. `product_requirements.md`: プロダクト、機能、AI、収益化、公開範囲を統合した要件定義の正本
2. `beta_release_implementation_backlog.md`: 要件に対する実装状態、残作業、完了条件の正本
3. `current_product_specification.md`: 次回配布向け現行ソースの詳細仕様
4. `omakase_mode_specification_v2.md`: 今日の3つを中心にした最上位UXの詳細仕様
5. `adult_ux_blueprint_2026-08-14.md`: 大人向けUIの情報階層、状態、信頼表示、受入条件
6. `testflight_feedback_ledger.md`: 全フィードバック、重複、再発、解決済みアーカイブの正本
7. `master_task_list_2026-08-13_draft.md`: 過去要望を含む全件台帳。現行順序はベータ公開統合バックログを優先
8. `implementation_execution_plan_2026-08-13.md`: 実装順、ビルド、担当、テスト、公開ゲート
9. `production_launch_remaining_tasks.md`: 本番提出、公開、初期運用の残作業と担当の正本
10. `release_readiness_plan.md`: 完了済みのリリース実装履歴と候補ゲート基準
11. `app_store_launch_checklist.md`: Build 19から一般公開までの依存順バックログ
12. `mvp_requirements.md`: 過去MVPの要件と受け入れ条件。現行判断には使用しない
13. `architecture.md`: コードの責務、依存方向、変更先の正本
14. `feature_map.md`: 機能から実装・テストを探す索引
15. `privacy_data_inventory.md`: 保存・送信・保持・削除の正本
16. `testflight_release_plan.md`: TestFlight提出手順
17. `ai_server_integration.md`: AI APIの通信、画像前処理、設定、エラー処理
18. `ai_trainer_integration.md`: AIトレーナーの会話、文脈、記憶、保持設計
19. `coach_character_reference_2026-08-13.md`: AIトレーナーの人物、話し方、専門性の設計
   - `ai_agent_contract.md`: 全AI機能で共通する人格、健康管理を含む対象範囲、安全境界、機能別契約の正本
20. `advertising_integration.md`: 広告配信、同意、データ分離、AdMob設定
21. `monetization_strategy_summary.md`: 一般公開、広告、AIクレジット購入を段階導入する収益戦略の正本
22. `ai_credit_monetization_requirements.md`: 初回特典、報酬広告、消耗型IAP、残高台帳、AI消費量の要件定義
23. `ai_usage_and_monetization_plan.md`: AI利用枠、混雑制御、匿名運用指標、広告収益との評価計画
24. `regression_testing_policy.md`: L0〜L3の回帰範囲を決める強制条件と判定スコア
25. `regression_report_2026-08-13.md`: iPhone最大2台と後続Watchによる複数エージェント回帰の結果と運用方法
26. `evidence_rag_design.md`: 目的別学術文献収集、sqlite-vec検索、引用、安全境界の正本
27. `device_log_analysis_2026-08-14.md`: Build 14実機ログ、AI失敗、体型写真保存、クラッシュの解析結果
28. `bodymode_core_experience_research_plan_2026-08-16.md`: コア体験の調査項目、状態、完了ゲート
29. `bodymode_core_experience_research_findings_2026-08-16.md`: 学術・競合・AI評価・CRUD・移行形式の調査結果
30. `bodymode_core_experience_beta_research_protocol_2026-08-16.md`: 未確定事項をTestFlightで測る手順
31. `bodymode_core_experience_implementation_plan_2026-08-16.md`: 調査ゲート通過後に確定する暫定実装計画
32. `research-prototypes/r9_rationale_5_second_test.html`: 根拠表示の5秒理解度テスト用静的プロトタイプ
33. `ai_plan_revision_research_2026-08-16.md`: AI計画変更の8ケース評価、失敗分類、構造化境界
34. `research-prototypes/bodymode_core_research_runner.html`: R5完了画面比較とR9根拠理解度を一続きで実施・JSON出力する実査ツール
35. `../scripts/summarize_core_experience_research.py`: 実査JSONを自由記述抜きで集計し、サンプル数と判定ゲートを出力するツール
36. `../scripts/audit_workout_export.py`: 他アプリのCSV/XML/JSONを実値非表示で形式監査するツール
36. `daily_action_catalog_research_2026-08-16.md`: 今日提示する行動、頻度、相互排他、除外条件、現行エンジンとの差分

コア体験については、27〜29が調査の正本、30は調査完了まで確定しない実装計画である。

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
- `app_store_connect/app_privacy_answers_ja.md`: App Store Connectへ転記するApp Privacy回答表
- `app_store_connect/app_declarations_ja.md`: 年齢、医療機器、輸出、DSA、コンテンツ権利の回答表
- `global_distribution_plan.md`: 全地域配信、多言語化、広告・法務対応の実装計画
- `ai_gateway_deployment.md`: Mac miniの直接ホスト名を隠すCloudflare Worker配備・段階移行手順
- `cloudflare_backend_migration.md`: Luna、D1、Vectorizeへ移す機能とMac miniに残す運用処理
- `cloudflare_operations_runbook.md`: 本番監視、D1バックアップ、Vectorize再構築、Workerロールバック、鍵更新の手順
- `support_operations_runbook.md`: 問い合わせ優先度、障害、返金、監査付きクレジット補正の運用手順
- `legal/`: 利用規約、プライバシーポリシー、サポート原稿
- `../scripts/prepare_public_legal_pages.py`: `legal/`の正本からGitHub Pages用の日英6ページを生成
- `ios_environment_setup.md`: 開発環境と実機導入
- `third_party_notices.md`: ローカルAIサーバーを含む第三者OSSの告知

## Archive

`archive/`は実装済みフェーズの判断経緯を残す場所であり、現行仕様ではない。新しい実装判断に使う場合は、上記の正本と現在のコードを優先する。
