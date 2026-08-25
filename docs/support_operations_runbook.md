# BodyMode サポート運用手順

更新日: 2026-08-23

## 受付と目標

| 優先度 | 例 | 初回確認目標 | 初動 |
|---|---|---:|---|
| P0 | 購入後に残高が増えない、データ消失、全員がAIを利用不能 | 1営業日以内 | 新規販売・AI経路の停止要否を判断し、監視・台帳・App Store通知を確認 |
| P1 | 再現するクラッシュ、Watch同期不能、広告報酬未反映 | 2営業日以内 | バージョン、再現手順、匿名診断ログを確認 |
| P2 | 表示崩れ、改善要望、翻訳 | 5営業日以内 | 台帳へ登録し、次回更新の優先度を判断 |

TestFlightはAppleのベータフィードバック、一般公開後はSupport URLのGitHub Issuesを一次窓口とする。公開Issueには身体・食事・写真・AI会話・氏名・住所・認証情報を書かせない。購入・広告報酬・AIクレジットの調査は、個人情報ではなくアプリに表示する16文字のサポートIDとサーバー台帳で行う。現在の運用では機微情報の送信を依頼しないため、専用メールは本番開始の必須条件にしない。非公開での情報交換が必要な問い合わせ需要が確認された場合に追加する。

## AI・障害

1. `~/Library/Application Support/BodyMode/operations/latest.json`と`~/Library/Logs/BodyMode/operations-report.log`を確認する。
2. `python3 scripts/cloudflare_operations_report.py`でhealth、成功率、p95、日次上限、クレジット整合性、App Store通知拒否を再確認する。
3. 影響が継続する場合はAI kill switchを使い、手動記録を維持する。
4. 直前の正常Workerへロールバックし、必要ならOpenAI・Apple・AdMobの障害情報を確認する。
5. 復旧後24時間は1時間ごとの監視結果を確認する。

## 購入・返金

- 現金の返金判断と処理はAppleが行う。BodyModeからApp Store外で返金しない。
- App Store Server Notifications V2が返金を受信すると、未使用購入クレジットを自動で除き、使用済み分は将来の購入付与から調整する。
- 購入未反映は、アプリの購入復元・署名済み取引の再検証を先に行う。
- ユーザーにはクレジット履歴に表示される16文字のサポートIDを提示してもらう。Apple ID、メール、健康情報は受け取らない。

## クレジット補正

補正は、購入・広告報酬・障害の事実を確認できた場合だけ行う。D1を直接編集しない。

```bash
python3 scripts/adjust_ai_credits.py \
  --support-id 0123456789abcdef \
  --amount 25 \
  --reason purchase_missing \
  --adjustment-id 01234567-89ab-4def-8123-456789abcdef
```

最初はdry runになり、内容を確認後に同じコマンドへ次を追加する。

```bash
--apply --confirm-support-id 0123456789abcdef
```

補正IDは問い合わせごとに一度だけ発行する。同じ補正IDの再実行は二重付与されない。理由は`purchase_missing`、`reward_missing`、`service_recovery`、`other`のいずれかで、自由記述や個人情報をサーバー台帳へ入れない。

## 完了記録

- 発生日、アプリBuild、影響範囲、原因、復旧時刻、再発防止だけを障害台帳へ残す。
- クレジット補正は補正ID、固定理由、付与量、実行結果だけを残す。
- 健康値、写真、食事、AI会話、Apple ID、アクセストークンを運用記録へ転記しない。
