# BodyMode 翻訳ハンドオフ

更新日: 2026-08-21

## 今回のリリース規模

- App Storeローカリゼーション: 44件
- 日本語原文: 1件
- 翻訳先: 43件
- アプリ内翻訳レコード: 2,388件
- 翻訳パック: 18ファイル、各250件以下
- RTL検査対象: アラビア語、ヘブライ語

ベンガル語（`bn`）、カンナダ語（`kn`）、マラヤーラム語（`ml`）、オディア語（`or`）、パンジャブ語（`pa`）、ウルドゥー語（`ur`）は、自動翻訳の文字体系・意味品質が公開基準に届かなかったため今回対象外とする。生成済みファイルは検証資料として保管するが、リリース成果物には含めない。

## ファイル

| ファイル | 内容 |
|---|---|
| `target_locales.csv` | 対象ロケール、公開・保留戦略、アプリ内リソース名、RTL、QA順 |
| `translation_packs/index.json` | 既存18パックの索引と件数 |
| `translation_packs/*.jsonl` | チャットへ1ファイルずつ渡す日本語原文 |
| `chat_translation_prompt.md` | そのまま貼れる翻訳依頼文 |
| `chat_translation_prompt_all_locales.md` | 43公開対象言語を1ファイルで受け取る一括翻訳依頼文 |
| `chat_translation_prompt_all_remaining.md` | 残り11パックを43公開対象言語へ一括翻訳する依頼文 |
| `translation_documents_ja.md` | 法務・ストア文書の日本語正本一覧 |
| `translations/<locale>/*.jsonl` | 検証済みの言語別翻訳 |
| `../../scripts/import_localization_translation_bundle.py` | 全言語一括JSONLの検証・分割取り込み |
| `../../scripts/connect_static_localizations.py` | プレースホルダーなし文言をSwiftへ接続 |
| `../../scripts/connect_interpolated_localizations.py` | 補間式を保持したままプレースホルダー文言をSwiftへ接続 |
| `../../scripts/translate_release_delta_with_ollama.py` | 新規UI差分を43言語へ翻訳し、プレースホルダーを検証 |
| `../../scripts/translate_store_legal_documents_with_ollama.py` | ストア・法務文書の機械翻訳下書きを生成・再開 |
| `interpolated_connection_report.txt` | 補間文言の接続件数と要確認参照 |

## 翻訳進捗

- 生成アーカイブ: 631ファイル、105,831件（既存49言語と新規差分43言語）
- 今回の公開対象: 774ファイル、102,684件（18パック × 43言語）
- `translation_strategy=deferred` の6言語は、統合・完全性検証の対象外
- 公開対象の構造QA: 欠落、重複、空欄、プレースホルダー不整合、RTL制御文字は0件
- 公開対象の文字体系QA: 他言語文字の混入は0件
- String Catalog接続: iPhone 2,163キー、Watch 236キー、Widget 2キー、権限説明10件
- 補間文言の要確認19参照は用途を確認し、既存IDへ明示接続済み
- 代表UIスモーク: `ui-smoke/`にiPhone 5言語、Watch 4言語の確認画像を保存
- 代表UIスモーク結果: `ui_smoke_report_2026-08-15.md`

`core_ui_01`のSwift文字列補間断片2件と、残りパックの抽出断片13件は、IDを維持したまま原文とプレースホルダーを修復済み。文字体系の混入があった公開対象125件はNLLBフォールバックで再翻訳し、`review_note`へ人手確認対象として記録している。

残り11パックでは、英語、フランス語、ポルトガル語、スペイン語の一部地域版を基準ロケールから展開している。対象行は`review_note`に地域レビュー必須として記録済み。公開前に、地域差、権限説明、健康表現、Watchの表示幅を対象言語話者が確認する。

## 依頼手順

1. 最初は`en-US`を対象にする。
2. `chat_translation_prompt.md`の`TARGET_LOCALE`を置き換える。
3. `translation_packs/index.json`の順に、JSONLを1ファイルだけ添付する。
4. 出力を`translations/<locale>/<入力ファイル名からtranslation_source_ja_を除いた名前>`として保存する。
5. 同じロケールの12パックが揃ったら、まとめてCodexへ渡す。
6. CodexでID、欠落、重複、プレースホルダー、表示幅を検査してString Catalogへ取り込む。

出力例:

`translations/en-US/core_ui_01.jsonl`

全43公開対象言語を1ファイルにまとめて受け取った場合は、次のコマンドで対象言語、件数、ID、重複、空欄、プレースホルダーを検証してから言語別に保存する。

```bash
python3 scripts/import_localization_translation_bundle.py \
  /path/to/translation_core_ui_01_all_43_locales.jsonl
```

書き込まず検証だけ行う場合は`--validate-only`を付ける。

## 品質順

`qa_wave`は公開地域を絞る指定ではない。全地域公開の前に、画面崩れを効率よく見つけるための確認順である。

- Wave 1: 主要言語と中国語・韓国語の文字幅を確認
- Wave 2: 欧州・東南アジアの追加言語を確認
- Wave 3: RTLとインド系文字のレイアウト・フォントを重点確認

機械翻訳後も、権限説明、健康表現、法務、ストア名・サブタイトルは対象言語話者による確認を推奨する。
