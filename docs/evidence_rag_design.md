# BodyMode Evidence RAG 設計書

更新日: 2026-08-16
状態: 目的別コーパス、OA本文、対象者適合、版管理、評価・監視まで実装済み

## 1. 目的

AIトレーナーの一般的なトレーニング・栄養・回復の説明へ、追跡できる学術根拠を付ける。ユーザー自身の記録から行う個別判断と、研究参加者の平均的知見を明確に分ける。

医療診断、治療、痛みや疾患の判定には使用しない。文献が見つからない場合や対象者が合わない場合は断定しない。

## 2. 再利用方針

米国モーニングブリーフのRAGから、次の基盤パターンを再利用する。

- SQLiteを検索データの正本にする
- データ同期をオンライン処理、ユーザー検索をローカル処理に分離する
- 語彙検索とベクトル検索を組み合わせる
- 生成結果と出典メタデータを分離して返す
- 取得失敗時も既存機能を止めない

コードとDBは共有しない。ニュース向け固定ハッシュベクトルや時間優先の順位付けは、科学文献の多言語検索と研究品質評価には適さないためである。

## 3. 構成

```text
目的 -> 研究課題 -> 48個の固定検索式
  -> Europe PMC REST API
  -> Europe PMC撤回情報 + Crossref訂正・版関係
  -> 再利用可能なOAライセンスを確認したEurope PMC本文
  -> SQLite documents / chunks / FTS5 / sqlite-vec
  -> Ollama bge-m3埋め込み

ユーザー質問
  -> Mac mini内で埋め込み
  -> FTS5 + cosine similarity + 研究品質 + 新しさ + 対象者適合
  -> 上位3〜5件
  -> gemma4へ根拠コンテキストを追加
  -> 回答 + 使用したevidence_ids
  -> iPhone引用カード
```

## 4. データ源

- Europe PMC: PMID、PMCID、DOI、タイトル、抄録、著者、掲載誌、年、出版種別、キーワード、OA状態
- Europe PMC Full Text XML: 明示的に再利用可能なライセンスを確認できた本文だけをローカル保存
- Crossref: 高品質・新しいDOI付き文献を優先した訂正・撤回・更新関係の補助照合
- PubMed: iPhoneで開く一次リンク

商用利用との衝突を避けるため、`CC BY`、`CC0`、Public Domainだけを本文取得対象とする。`CC BY-NC`、`CC BY-ND`、`CC BY-SA`、OA表示だけでライセンス文が確認できない文献、All rights reserved、XML解析不能な文献は抄録のみとする。本文・抄録はMac mini内の検索と根拠要約にだけ使い、iPhoneへ原文本文を再配布しない。

### 4.1 収集範囲

収集計画は`evidence_collection.py`を正本とする。対象目的は次の7種類である。

- 筋肥大
- 筋力
- 減量
- ボディリコンポジション
- 健康維持
- 競技力向上
- トレーニング復帰

目的を週当たりセット数、負荷、失敗への近さ、タンパク質、エネルギー収支、歩数、睡眠、疲労、ピリオダイゼーション、デトレーニングなど48研究課題へ分解する。各課題は全期間の関連度上位、2017年以降、1990〜2016年の3枠で取得する。これにより新しい研究だけへ偏ることを防ぐ。

2026-08-14のローカル構築結果は2,836件、2,836ベクトル、DB約44MiB。目的別件数はタグ重複を含み、筋肥大426、筋力502、減量582、ボディリコンポジション672、健康維持884、競技力572、復帰395である。年代は2022〜2026年1,665件、2017〜2021年179件、2012〜2016年833件、2011年以前159件である。

## 5. 検索と品質

- 日本語の主要語を英語検索語へ展開する
- SQLite FTS5の語彙一致と`sqlite-vec`のcosine KNNを併用する
- 日本語を英語へ展開し、目的タグと研究課題タグを再順位付けへ使う
- ガイドライン、メタ解析、系統的レビュー、RCT、その他の順に基礎品質点を持つ
- 語彙一致、意味類似度、研究品質、新しさ、目的・研究課題一致、ユーザーと研究対象者の適合度で再順位付けする
- 新しさだけで低品質研究を上位にしない
- 撤回文献と訂正版に置き換えられた旧版は候補取得段階で除外する
- 対象者が明確に不一致の候補しかない場合は引用せず`population_mismatch`を返す
- 新旧研究の結論極性が異なる場合は`mixed`とし、古い文献へ新研究の注意を付ける

各文献へpopulation、interventions、outcomes、constraints、conclusionを構造化保存する。構造化は検索・説明補助であり、人手によるRoB評価の代替ではない。確度は`high / moderate / low / insufficient`、適合は`direct / partial / unclear / mismatch`で返す。

## 6. 生成ルール

- 検索結果には`E1`から`E5`までの一時IDを付ける
- モデルは実際に使ったIDだけを`evidence_ids`へ返す
- 回答内の`[E1]`をサーバーで主張文へ対応付け、`evidence_claims`として返す
- サーバーは検索候補に存在しないIDを破棄する
- 科学的主張には`[E1]`のような参照を付ける
- ユーザー記録と文献知見を混同しない
- 根拠外の数値、因果関係、確実性を作らない

## 7. APIとiPhone

`POST /v1/agents/chat`へ次を追加する。

- `evidence`: 従来項目に加え、`source_scope`、`evidence_summary`、PICO、limits、適合度、版状態、結論整合性、新研究の注意
- `evidence_claims`: 回答の主張と実際に使ったPMIDの対応
- `evidence_status`: `ready / no_match / population_mismatch / empty / disabled / unavailable`、理由、検索対象数、一致数

iPhoneは回答下部に「科学的根拠 N件」を表示する。必要なユーザーだけ、結論要約、対象者、介入、制約、適合度、新研究の注意を展開し、PubMedへ移動できる。追加フィールドのない古い保存データは既定値で互換読込する。

## 8. プライバシーと障害時動作

- 外部データ源へ送るのは固定トピック検索式だけ
- 氏名、写真、自由記述、身体値、会話履歴は文献APIへ送らない
- ユーザー質問の埋め込みと検索はMac mini内だけ
- RAG無効、DB空、Ollama埋め込み失敗、SQLite障害時も通常チャットを返す
- サーバーは会話、ユーザー文脈、長期記憶を保存しない

## 9. 運用

初回環境構築。macOS付属/Xcode付属PythonはSQLite拡張読み込みが無効なため使用しない。

```bash
brew install python@3.11
cd local_llm_server
./setup_environment.sh
```

初回および手動更新:

```bash
ollama pull bge-m3
cd local_llm_server
./sync_evidence.sh --limit-per-query 160
```

状態確認:

```bash
curl -H "Authorization: Bearer $LOCAL_AI_API_KEY" \
  http://127.0.0.1:8765/v1/evidence/status
```

評価:

```bash
./.venv/bin/python evidence_evaluation.py \
  --database "$EVIDENCE_RAG_DB_PATH" \
  --cases evidence_evaluation_set.json --k 5 \
  --output .build/evidence-evaluation.json
```

評価セットは`chat / daily_recommendation / plan_generation / safety`を分け、Recall@K、関連適合率、撤回・旧版除外率、対象者適合率を出す。ケースは目的別タグと研究課題タグから正解集合を作るため、同期ごとの文献入替にも追従する。

運用監視:

```bash
curl -H "Authorization: Bearer $LOCAL_AI_API_KEY" \
  "http://127.0.0.1:8765/v1/evidence/metrics?days=7"
```

埋め込み・検索・総遅延、検索成功率、失敗種別、入力文字数、推定費用を目的別に保存する。ローカルOllamaは既定費用0ドルで、外部モデルへ切り替える場合のみ`EVIDENCE_COST_PER_MILLION_CHARACTERS`を設定する。会話本文や健康値は監視DBへ保存しない。

`scripts/install_local_ai_launch_agent.sh`は毎週月曜03:15の同期をLaunchAgentへ登録する。同期時は既存ベクトルをPMID単位で再利用し、全文献と全ベクトルが揃った場合だけ1トランザクションでコーパスを置換する。旧`vector_json`は初回接続時に`sqlite-vec 0.1.9`へ移行し、移行後は削除する。

同期・検索・APIの詳細契約はこの文書と`local_llm_server/evidence_evaluation_set.json`を正本とする。本文構造化と結論極性は決定的ヒューリスティックなので、評価結果が悪化した場合は生成回答ではなく構造化器・評価セットを先に更新する。

## 10. 2026-08-14検証結果

- Pythonバックエンド全20テスト成功
- SQLite `integrity_check`成功
- 文献2,836件、チャンク2,836件、`sqlite-vec`ベクトル2,836件、旧JSONベクトル0件
- 撤回フラグ付き1件を検索対象から除外
- 実APIチャットで、筋肥大の週セット数にメタ解析2件とRCT2件を引用
- Apple L3回帰は188成功、2許可済みスキップ、利用分析UIテスト1件のみ並列時に失敗
- 失敗したUIテストは座標タップを標準Switchタップへ変更し、単独再実行に成功

L3全体は1件失敗のため成功基準点にはしない。Evidence RAGのAPI契約とiPhone表示に失敗はなく、残るリスクは上記UIテストの並列実行安定性である。
