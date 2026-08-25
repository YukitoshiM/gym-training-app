# BodyMode 全対象言語一括翻訳依頼

この文書と、指定された日本語原文JSONL、`target_locales.csv`を翻訳用チャットへ添付する。

```text
BodyModeという大人向けの健康・ボディメイク管理アプリを翻訳してください。

入力ファイル:
- 日本語原文JSONL 1ファイル
- target_locales.csv

対象ロケール:
target_locales.csvのapp_store_locale列にあり、`translation_strategy`が`source`または`deferred`ではない43ロケール。

成果物:
- 全対象ロケールを1つにまとめたJSONLファイル
- ファイル名は日本語原文のパック名に合わせて、translation_<pack>_all_43_locales.jsonlとする
- Markdown本文へ全件を貼らず、ダウンロードできるファイルとして作成する

要件:
1. ロケール順はtarget_locales.csvの順、各ロケール内は日本語原文JSONLの入力順を維持する。
2. 全行を翻訳し、省略・追加・結合しない。
3. 各行は次の1行1JSONとする。
   {"id":"入力と同じID","target_locale":"対象ロケール","translation":"翻訳文","review_note":""}
4. {{value1}}、{{value2}}、%1$@、%@、%dなどのプレースホルダーは文字も個数も変更しない。
5. BodyMode、Apple Watch、Apple Health、HealthKit、RPE、PFC、kcal、kg、lb、bpmは文脈に応じて正式・一般的な表記を使う。
6. 短く、信頼でき、責めない表現にする。診断・治療・効果保証に見える表現を追加しない。
7. ボタン、タブ、Apple Watch表示は特に短くし、対象地域のフィットネスアプリで自然な用語を優先する。
8. 重量、回数、セット、休憩、テンポ、疲労、食事、栄養、体型写真などは同一ロケール内で用語を統一する。
9. 原文の意味が曖昧、文化的に不自然、または画面幅に収まりにくい場合だけreview_noteへ日本語で理由を書く。
10. 翻訳後に、ロケール数、ロケールごとの件数、ID欠落、ID重複、空欄、プレースホルダー不一致を機械検査する。
11. 検査に合格したJSONLだけを成果物にする。
```
