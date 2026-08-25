# BodyMode コア体験 調査結果

更新日: 2026-08-16
対象: おまかせホーム、AI計画変更、完了画面、記録保全、他アプリ移行、根拠表示
結論区分: `採用` / `小規模実験` / `未検証` / `不採用`

## 1. 結論一覧

| ID | 結論 | 判定 | 実装判断 |
| --- | --- | --- | --- |
| R1 | 今日の行動は最大3件を維持するが、目的別の最適な組み合わせは実利用データ不足 | 小規模実験 | 行動候補を固定せず、カテゴリ別の表示・開始・完了・差替えを計測する |
| R2 | 筋トレ、タンパク質、歩数、睡眠、体重・腹囲記録には根拠がある。ただし一律の数値目標やHRV単独判断は避ける | 採用 | 個人基準と目的を優先し、根拠の確度と適用限界を保持する |
| R3 | 朝の提案は安定させ、開始後の計画は固定し、重要変更はユーザー承認を取る方式が妥当 | 採用 | 日次の微調整と週次・イベント時の計画改訂を分離する |
| R4 | 現行の自由文AIに計画を直接更新させる方式は、ケース混同と欠落があり不合格 | 不採用 | ルールで変更候補を構造化し、AIは説明と候補選択に限定する |
| R5 | 完了直後は達成内容を先に見せ、次回提案は簡潔な仮案に留めるのが妥当 | 小規模実験 | A/B/C案の実利用比較が終わるまで最終順序は確定しない |
| R6 | 主要データは編集・削除できるが、Undo、ゴミ箱、インポートが全体的に不足 | 採用 | 変更履歴と復旧をP0データ保全として扱う |
| R7 | Watchは中断復帰可能だが、iPhoneは未完了セッションを破棄する | 採用 | iPhone/Watch共通の保存状態と競合規則を設ける |
| R8 | Strong 2件・Hevy 3件の公開標本から版差とパーサー要件を抽出したが、現行公式出力によるfixture検証は未完了 | 未検証 | 匿名化した現行公式出力を取得するまでインポーターを実装しない |
| R9 | 理由は「一文、判断材料、文献」の3層表示が最も情報量を制御しやすい | 小規模実験 | 信頼度、データ不足、更新時刻、出典を段階表示する |

## 2. R1 今日の行動ニーズ

### 現在得られた証拠

- 2026-08-16にApp Store Connect APIから再取得したTestFlightフィードバックは40件、クラッシュ提出は2件、最新Buildは22でVALIDだった。新着2件を含めても、DailyActionの候補・件数・優先順位を直接比較できる回答はない。
- 2026-08-16 13:33 JST時点でも、仮名化利用分析DBの直近90日は`active_users = 0`、`event_counts = {}`だった。
- 2026-08-16 14:09 JSTにApp Store Connect APIで全グループを再確認した。`Reddit Beta`は公開リンク有効、上限50、Build 22が有効だが参加者0人。`Friends & Family`はBuild 22をインストール済み3人、内部グループは1人だった。AppleのAPI仕様どおりグループのテスター関係から件数だけを取得し、氏名・メールは要求・出力していない。
- API根拠: [List all beta testers in a beta group](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-betagroups-_id_-betatesters)
- アプリには`daily_recommendation_generated`、`daily_action_impression`、`daily_action_completed`、`daily_action_dismissed`、`home_primary_action_started`、`daily_action_reason_opened`、`daily_action_replaced`の計測点を実装した。
- 利用分析は任意同意であり、新しい外部送信同意バージョンのため、現在のTestFlight利用を代表するデータはまだ集まっていない。

### 利用分析経路の監査

- 公開Cloudflare Gatewayの`GET /v1/health`、`POST /v1/analytics/events`、`DELETE /v1/analytics/events`を実送信し、すべてHTTP 200を確認した。
- 調査probeは1件受理後、同じクライアントキーで1件削除し、DBへ残していない。
- 設定画面の`利用分析に協力`は初期オフで、同意バージョン更新時にも再度オフになる。
- 従来の40文字以内の`dimension`に加え、目的、経験、readiness、表示位置、差替え先、差替え理由、完了方法を許可された列挙値だけで保持する。
- サーバーは未知キー、自由文、許可外の値をHTTP 422で拒否する。
- AppleのApp Privacy定義に合わせ、利用分析は`Product Interaction`と`Fitness`のアナリティクス収集として申告案へ反映した。
- 収集項目変更に合わせて同意文を改訂し、旧同意を自動流用しないバージョンへ更新した。
- iOS対象テスト17件、サーバー側29件が成功した。実利用DBは0件のままで、テストイベントは残していない。
- 集計監査で、旧North Starが完了イベント数を分子にしており1日複数完了時に100%を超え得る不具合を発見した。分子を`1件以上完了したユーザー日`へ修正し、目的・経験・カテゴリ別ファネルも表示ユーザー日を分母に統一した。修正後のサーバー側31テストが成功した。

したがって、通信障害と計測設計の不足は解消した。残る不足は、改訂版の配布、参加者の獲得、テスターの任意同意、7日以上の利用期間であり、ここから先は実利用データを待って判断する。Build 22のデータだけで新しい計測結果を評価してはならない。

### 暫定候補

| 目的 | 主行動候補 | 補助行動候補 | 原則表示しない条件 |
| --- | --- | --- | --- |
| 筋肥大 | 今日のトレーニング | タンパク質、睡眠、回復 | 同部位の強い疲労、当日完了済み |
| 筋力 | 主要リフトまたは軽減セッション | 睡眠、回復 | 高疲労、復帰直後、器具なし |
| 減量 | トレーニングまたは歩数 | 食事目安、タンパク質、体重 | 体重記録の強制が不適切な設定時 |
| 体型改善 | トレーニング | タンパク質、腹囲、週次写真 | 同日の写真・計測済み |
| 健康維持 | 歩数または軽負荷活動 | 睡眠、体重、回復 | 体調不良を示す自己申告時 |
| 復帰 | 軽減セッション | 回復、睡眠 | 痛みや中止条件を申告した時 |

### 未確定事項

- 3件が適量か。
- 食事、歩数、回復のどれが目的別に実行へつながるか。
- 「差し替え」と「無視」の理由。

これらは机上調査では決めず、次のベータ計測で判断する。

### 公開コミュニティ定性調査

初心者向けフィットネス、Apple Watch、TestFlight関連の公開投稿を確認した。投稿数と回答者属性が限定されるため市場規模の推定には使わないが、問題仮説の補強には使える。

| 繰り返し見られた課題 | BodyModeへの示唆 |
| --- | --- |
| 既存アプリは指標・設定・入力が多く、初心者が開始地点を判断できない | ホームは主行動1件を最も強くし、補助行動は0〜2件に制限する |
| 組込みメニューは欲しいが、自由なルーティン編集も失いたくない | 推奨メニューと詳細編集を同じ計画へ合流させる |
| 重量・回数・感覚だけを素早く残したい | 前回値を初期値にし、主要セットは最短操作で完了させる |
| 体調や利用可能時間、器具に合わせて当日変更したい | `時間がない`、`器具が空いていない`、`疲れている`を差替え理由として直接選べるようにする |
| ワークアウト中にスマートフォンを何度も見たくない | Watchを実行端末にし、操作回数と画面注視時間を測る |
| 休憩開始・再開を忘れ、記録時間が欠ける | 自動保存、再開通知、休憩タイマーの復元を優先する |
| 追跡、プログラム、カスタマイズのどれかが欠ける | おまかせと詳細を別製品にせず、同一データへ接続する |
| 高額課金や基本機能の強い制限を嫌う | ベータでは主要フローを制限せず、正式版の制限は価値確認後に設計する |

参照した公開投稿:

- [Beginner-friendly tracker request](https://www.reddit.com/r/beginnerfitness/comments/1lcslcg)
- [Why workout apps feel overwhelming](https://www.reddit.com/r/beginnerfitness/comments/1r7vdx6/why_do_so_many_workout_apps_feel_overwhelming_for/)
- [Why people do not use workout apps](https://www.reddit.com/r/beginnerfitness/comments/1v7x913/whyd_you_guys_not_use_workout_apps_i_just_started/)
- [Simple app that tells beginners what to do](https://www.reddit.com/r/beginnerfitness/comments/1spn5ms/whats_a_good_or_best_fitness_app_for_complete/)
- [Apple Watch rest timer request](https://www.reddit.com/r/AppleWatch/comments/1u3by42/auto_rest_timer_for_strength_workouts/)
- [Resume reminder request](https://www.reddit.com/r/AppleWatchFitness/comments/15tka88)

### R1で採用する行動選定の骨格

1. 主行動は、その日に実行できるトレーニング、回復、歩行のいずれか1件。
2. 補助行動は主目的への寄与が高く、その日まだ未完了のものだけ0〜2件。
3. 記録のためだけの行動は、予定頻度を満たした日には出さない。
4. 同じカテゴリを連日出す場合は、前日未達だけを理由にせず、目的と予定を確認する。
5. 差替えは自由文より先に、時間、器具、疲労、痛み、予定変更、既に実施を選べるようにする。

行動カテゴリごとの提示条件、頻度、完了条件、相互排他、時間帯、現行エンジンとの差分は`daily_action_catalog_research_2026-08-16.md`を正本とする。机上調査では常時3件表示を支持する直接根拠は確認できなかったため、1〜3件の可変表示を実利用比較の候補とする。

## 3. R2 DailyAction根拠表

| 行動 | 調査結果 | 確度 | BodyModeでの扱い |
| --- | --- | --- | --- |
| 筋トレを行う | 多様なレジスタンストレーニング処方で筋力・筋肥大が改善する。高負荷は筋力、複数セットは筋肥大に有利 | 高 | 目的、経験、利用器具からメニュー化する |
| 重量を上げる | 1回の好調だけでなく、計画セット完遂と余力の反復を条件にするのが妥当 | 中 | 連続達成、RPE/RIR、フォーム自己評価を条件にする |
| 重量を下げる | 連続未達、高RPE、復帰直後は候補。単日の失敗だけで自動確定しない | 中 | 変更候補として提示し承認を取る |
| 限界まで追い込む | 筋肥大で常に瞬間的失敗まで行う優位性は確認されていない | 中 | 毎回の失敗到達を推奨しない |
| タンパク質を取る | 筋トレ中の健康な成人では総摂取量約1.6 g/kg/日付近で除脂肪量効果が頭打ちになる分析がある | 中 | 一律150gではなく体重・目的・食事状況から範囲提示する |
| 歩く | 2025年の用量反応レビューでは約7,000歩/日でも2,000歩/日より有意な健康便益と関連 | 中 | 10,000歩固定ではなく最近の基準から段階設定する |
| 睡眠を確保する | 成人は継続的に7時間以上が推奨され、睡眠不足は運動能力へ平均的な悪影響 | 高 | 睡眠不足時は強度・量の軽減候補。ただし自動休養に直結させない |
| HRVで調整する | HRV誘導は固定計画より小さい改善傾向だが、効果と手法に不確実性がある | 低〜中 | HRV単独で休養・減量を決めず、個人基準と複数要因で使う |
| 休止後に復帰する | 休止による低下量は休止期間、年齢、種目、直前のトレーニング歴で異なる。競技者向け合意文書は最初の2〜4週間の段階的復帰を支持するが、一般成人へ一律の重量比を指定する直接根拠にはならない | 中 | 前回重量の固定90%などを自動採用しない。休止期間、直近実績、痛み、活動状況を確認し、初回は暫定負荷・量を提示して実績後に再評価する |
| 体重を記録する | 毎日または週次の自己計測は行動プログラム内で体重管理を支援しうるが、毎日が週次より常に優れる証拠は弱い | 中 | 目的・嗜好に応じて頻度を選べるようにする |
| 腹囲を記録する | 自己測定は可能だが、臨床的に意味のある誤差が起こりうる。標準手順と反復で信頼性が上がる | 中 | 週次傾向として扱い、診断や単回値の断定に使わない |

### 参照した一次情報

- [Resistance training prescription network meta-analysis](https://pubmed.ncbi.nlm.nih.gov/37414459/)
- [Resistance training variables umbrella review](https://pubmed.ncbi.nlm.nih.gov/37385345/)
- [Proximity to failure systematic review](https://pubmed.ncbi.nlm.nih.gov/36334240/)
- [Proximity to failure meta-regression](https://pubmed.ncbi.nlm.nih.gov/38970765/)
- [Protein supplementation meta-analysis](https://pubmed.ncbi.nlm.nih.gov/28698222/)
- [Daily steps dose-response review](https://pubmed.ncbi.nlm.nih.gov/40713949/)
- [HRV-guided training meta-analysis](https://pubmed.ncbi.nlm.nih.gov/34639599/)
- [Sleep loss and physical performance](https://pubmed.ncbi.nlm.nih.gov/35708888/)
- [Adult sleep duration consensus](https://aasm.org/resources/pdf/adultsleepdurationconsensus.pdf)
- [Self-weighing systematic review](https://pubmed.ncbi.nlm.nih.gov/26293454/)
- [Self-weighing meta-analysis](https://pubmed.ncbi.nlm.nih.gov/26896865/)
- [Waist self-measurement accuracy](https://pubmed.ncbi.nlm.nih.gov/27184997/)
- [Standardized waist measurement reliability](https://pubmed.ncbi.nlm.nih.gov/27145829/)
- [Detraining in recreationally strength-trained men](https://pubmed.ncbi.nlm.nih.gov/12173951/)
- [Resistance training cessation and muscle size in older adults](https://pubmed.ncbi.nlm.nih.gov/36360927/)
- [Detraining duration and lower-limb strength maintenance](https://pubmed.ncbi.nlm.nih.gov/34510028/)
- [Periodic resistance training and retraining](https://pubmed.ncbi.nlm.nih.gov/39364857/)
- [CSCCa/NSCA safe return to training consensus](https://www.nsca.com/about-us/position-statements/safe-return-to-training/)

### 休止後復帰の判断境界

- 6週間の休止でも、レクリエーション経験者では1RMが大きく変わらない研究がある一方、パワーや一部筋力は低下している。休止期間だけから前回重量の何%と断定できない。
- 中高年・高齢者の研究では、休止期間とそれ以前のトレーニング期間によって保持される効果が異なる。若年一般ユーザーへ数値を直接転用しない。
- CSCCa/NSCAは、2週間以上の休止後に戻る大学競技者について、最初の2〜4週間は量・強度・休憩を段階調整する枠組みを示す。これは安全側の上限設計には使えるが、BodyMode一般利用者の処方を一意に決めるものではない。
- BodyModeは初回復帰案を`暫定`として扱い、セッション中の痛み、完遂率、RPE/RIR、翌日の回復を確認して次回案を更新する。
- 病気、けが、胸痛、失神、強い息切れ、医療者から運動制限を受けている場合はAIで復帰負荷を決定せず、専門家への相談を案内する。

### Evidence RAG監査

- 文献数: 2,836件、利用可能2,835件、ベクトル2,836件。
- 目的別件数は十分だが、検索上位に対象集団や目的が不一致の文献が混ざった。
- `quality_score`とトピックタグだけでは、DailyActionの直接根拠として安全に使えない。
- 実装前にPICO適合性、対象集団、介入、アウトカム、研究種別を判定する再ランキングが必要。

## 4. R3 競合方式

| 製品 | 確認した方式 | 採用する点 | 採用しない点 |
| --- | --- | --- | --- |
| Apple Training Load | 直近7日と過去28日を比較 | 個人の相対基準 | 単一指標で筋トレ計画を確定しない |
| Apple Vitals | 個人の通常範囲を作り、複数指標の逸脱を通知 | 個人基準、複数要因 | 医療判断への転用 |
| Fitbod | 履歴、回復、器具、目標で生成。開始後はワークアウトを固定 | 開始後の安定、手動回復調整 | 小変化ごとの再生成 |
| StrongLifts | 全セット完遂後に増量、複数回失敗後にデロード | 単日の失敗に過反応しない | 全種目への一律ルール |
| MacroFactor | 定期チェックインで変更案を提示し、承認・拒否可能 | 重要変更の明示的承認 | 毎日の目標変動 |
| Hevy | 前回値表示とルーティン更新を分離 | 実績参照と計画変更の分離 | 保存時の暗黙更新 |

参照:

- [Apple Training Load](https://support.apple.com/en-ie/guide/watch/apde4c07a6cf/watchos)
- [Apple Vitals](https://support.apple.com/en-us/120142)
- [Fitbod: How Fitbod Works](https://help.fitbod.me/hc/en-us/sections/360001078993-How-Fitbod-Works)
- [StrongLifts progression](https://support.stronglifts.com/article/71-progression)
- [MacroFactor check-ins](https://help.macrofactorapp.com/en/articles/247-introduction-to-check-ins-and-coaching-modules)
- [Hevy previous values vs routine values](https://help.hevyapp.com/hc/en-us/articles/34105442929943-Previous-Workout-Values-Vs-Routine-Values-How-to-Adjust-in-Settings)

## 5. R4 AI計画改訂評価

### 評価ケース

1. ベンチプレスを3回連続完遂、RPE 7
2. ベンチプレスを2回連続未達、RPE 9
3. スクワット完遂、RPE 10
4. 睡眠4.5時間、疲労5/5
5. 6週間休止から復帰
6. バーベルが利用不可
7. セッション時間が25分だけ
8. 4週間停滞

### 結果

- ケース1と2を同じ状況として混同した。
- ケース6と7を回答から欠落させた。
- 8入力を5提案へ圧縮し、入力と出力を1対1で検証できなかった。
- 理由と変更対象の構造がなく、既存計画への安全な差分適用ができない。

### 採用する境界

AIへ計画本体を書き換えさせない。以下の順にする。

1. ローカルルールで変更候補を抽出する。
2. `exerciseID`、変更前、変更後、理由、確度、根拠を持つ構造化候補にする。
3. AIは候補の説明、優先順位、代替案を返す。
4. スキーマ検証と安全境界を通す。
5. ユーザーが「新しい計画を作る」または「既存計画を更新」を選ぶ。
6. 適用前スナップショットを保存し、取り消せるようにする。

個別送信でも8件中、合格候補は一時調整の2件だけだった。詳細は`ai_plan_revision_research_2026-08-16.md`を正本とする。

## 6. R5 完了画面

### 暫定判断

主CTAは「完了」に対する肯定的な確認とし、情報順は次を暫定採用する。

1. 完了セット、PR、達成率
2. 次回への短い仮提案
3. ボリューム、種目別差分などの詳細
4. 計画変更は別の確認フロー

完了直後に計画を頻繁に変更すると、単日の調子へ過反応しやすい。次回提案は表示しても、永続的な計画更新は週次または連続達成・連続未達などのイベント時に分離する。

### 未検証

A: 次回提案、B: 達成・PR、C: 数値詳細のどれを最上部にすると理解と継続へ効くかは、テスター比較が必要。

## 7. R6 データCRUD・復旧監査

`○`: 可能、`△`: 限定的、`×`: 不可、`外部`: HealthKit等が正本

| データ | 作成 | 閲覧 | 編集 | 削除 | Undo/ゴミ箱 | Export | Import |
| --- | --- | --- | --- | --- | --- | --- | --- |
| トレーニング計画 | ○ | ○ | ○ | ○ | × | ○ | × |
| 完了トレーニング | ○ | ○ | ○ | ○ | × | ○ | × |
| 進行中iPhoneセッション | ○ | ○ | △ | 破棄のみ | × | × | × |
| 進行中Watchセッション | ○ | ○ | ○ | ○ | 再起動復元のみ | 同期 | 同期 |
| 食事 | ○ | ○ | ○ | ○ | × | ○ | × |
| 体型写真セット | ○ | ○ | ○ | ○ | × | ○ | × |
| 身体数値 | ○ | ○ | 保存APIのみ | ○ | × | ○ | × |
| ジム訪問 | ○ | ○ | 当日出発のみ | × | × | ○ | × |
| 主観疲労 | ○ | ○ | 同日上書きのみ | × | × | ○ | × |
| AI記憶 | ○ | ○ | × | ○ | × | ○ | × |
| AI履歴 | ○ | ○ | × | ○ | × | ○ | × |
| HealthKit由来データ | 外部 | ○ | 外部 | 外部 | 外部 | Apple側 | Apple側 |

主な証拠:

- `AppStore.saveBodyMetricEntry`は既存IDなら更新できるが、画面は常に新規IDを生成する。
- 食事、体型写真、トレーニング履歴には既存値を渡す編集画面がある。
- `makeExportData()`はスキーマ6で主要記録を出力するが、復元・インポート処理はない。
- 削除は即時保存で、共通Undoやゴミ箱はない。

## 8. R7 中断・再開

### 現状

- iPhoneのセッションはView内の`@State`だけで保持する。
- iPhoneで終了すると「完了していない記録は保存されません」として破棄する。
- Watchは進行中セッションと休憩終了時刻を保存し、再起動後に復元する。
- Watchは更新ごとにiPhoneへライブ同期する。

### 必要な状態遷移

`draft -> active -> paused -> active -> completed`

例外:

- `active/paused -> cancelled`: 確認後に破棄し、取消猶予を持つ。
- `active/paused -> interrupted`: OS終了や通信断。自動保存から復元する。
- iPhoneとWatchの双方に更新がある場合は、セッションID、revision、updatedAtで競合を判定する。
- セット単位の変更をマージし、同一セット競合だけユーザーへ選択を求める。

## 9. R8 移行形式

| 優先 | 移行元 | 公式に確認できたこと | 実ファイル | 判定 |
| --- | --- | --- | --- | --- |
| A | BodyMode JSON | スキーマ6で全主要記録を出力 | 生成可能 | まず同形式の復元を実装候補 |
| A | Strong | スプレッドシート互換CSVを出力。Strong自身には再インポートできない | 公開サンプル2件解析、本人の公式出力待ち | 列候補は一致。CSV内に重量単位がない版があり、取込時の単位確認が必要 |
| A | Hevy workout | Strong CSV取込とワークアウトデータ出力を案内 | 公開サンプル3件解析、本人の公式出力待ち | 公開サンプル間でも列・日時・set indexが相違 |
| A | Hevy measurements | 測定データ出力を案内 | 未取得 | ヘッダー確定前 |
| B | Apple Health | Healthアプリから全Health/FitnessデータをXMLで一括出力 | 未取得 | 全量XMLから必要型だけを抽出する設計前 |
| B | JEFIT | 公式サイトはセット、回数、重量、時刻、種目名を含むCSV出力を案内 | 未取得 | 実際の列、入手条件、版差の確認前 |
| 保留 | Fitbod | 公開された安定一括形式を確認できず | 未取得 | 正式形式確認まで対象外 |

参照:

- [Strong export](https://help.strongapp.io/article/235-export-workout-data)
- [Hevy import/export](https://help.hevyapp.com/hc/en-us/articles/38001424401943-How-to-Import-Strong-App-CSV-Files-and-Export-Your-Data-in-Hevy)
- [Apple Health data export](https://support.apple.com/guide/iphone/share-health-and-fitness-data-iph5ede58c3d/ios)
- [JEFIT workout logging and export](https://www.jefit.com/use-case/workout-logging-app)

公開リポジトリのサンプルは解析できたが、実在アプリから現在出力したものとは証明できない。最低でも各形式2件、kg/lb、自重、追加重量、アシスト重量、カスタム種目を含む匿名化した公式出力が必要。Hevyはワークアウトと身体測定が別ファイルなので、それぞれを別fixtureとして取得する。

補助的な公開コード調査では、Strong互換形式の12列とHevyの`start_time`、`end_time`、`exercise_title`、`set_index`、`set_type`、`weight_kg/lbs`、`reps`等を確認した。ただし公式エクスポート実物ではないため、実装fixtureの代用にはしない。

### 外部形式からBodyModeへの対応

| 外部項目 | BodyMode候補 | 変換規則 | 調査上の注意 |
| --- | --- | --- | --- |
| workout title | `WorkoutSession.title` | 文字列を保持 | 空なら移行元名を含む既定値 |
| start/end | `startedAt/endedAt` | タイムゾーンを保持してDate化 | タイムゾーン欠落時は取込前に地域確認 |
| exercise name | `WorkoutExercise.exercise` | 既定種目のalias照合、未一致はカスタム種目 | 言語・器具表記を正規化しても原文を保持 |
| set index/order | `WorkoutSet.setOrder` | 種目内で並べ直す | 0始まり/1始まり、文字列W等を許容 |
| weight | `actualWeight` | kgへ正規化 | Strongは単位列がないためユーザー確認必須 |
| reps | `actualReps` | 非負整数 | 距離・時間種目では未入力を0回と誤解しない |
| RPE | `rpe` | 1〜10、小数可 | 未入力を0にしない |
| set type | 追加メタデータが必要 | warmup/normal/failure/dropset | 現行`WorkoutSet`に直接の保存先がない |
| distance/duration | 追加メタデータが必要 | m/秒へ正規化 | 現行`WorkoutSet`は汎用距離を保持しない |
| notes | `WorkoutSet.note`または`WorkoutSession.note` | スコープ別に保持 | Strongではセット・ワークアウトの2種類 |
| workout duration | `endedAt`補完候補 | start + duration | endがある場合はendを優先 |

外部履歴にはBodyModeの`targetWeight`、`targetReps`が存在しないことが多い。実績値を目標値へ複製すると、過去の達成率と目標差が事実でない値になる。このため、インポート由来かつ計画値不明を表す状態を追加し、計画差分から除外する。

### BodyMode JSON復元の監査

- 現行出力は`schemaVersion = 6`、ISO 8601日付、主要な全記録を含む。
- 写真データ、ジム位置、AI会話・送信履歴も含む平文JSONであり、共有先の注意表示が必要。
- 復元処理は現状存在しない。
- 復元は現在データを直接上書きせず、検証、プレビュー、自動バックアップ、原子的適用、取込単位の取消が必要。
- 未知の新しいschemaは拒否し、古いschemaは段階的migrationを通す。
- ID衝突は同一IDの新旧だけでなく、同日時・同種目・同セットの意味的重複も判定する。

### 公開サンプルから確認した列候補

| 形式 | 列候補 | 信頼区分 |
| --- | --- | --- |
| Strong互換 | `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE` | 複数公開実装で一致。ただし公式実物fixture待ち |
| Hevy variant A | `title, start_time, end_time, description, exercise_title, set_index, set_type, weight_kg, reps, distance_meters, duration_seconds, rpe, exercise_notes, workout_duration` | 公開サンプル。日時は`yyyy-MM-dd HH:mm:ss`、set indexは1始まり |
| Hevy variant B | `title, start_time, end_time, description, exercise_title, superset_id, exercise_notes, set_index, set_type, weight_kg, reps, distance_km, duration_seconds, rpe` | 公開サンプル2件。`30 Jun 2025, 19:56`型を含む英語月名日時、set indexは0始まり |

Strongでは重量単位列がないこと、Hevyではウォームアップ・失敗・ドロップセットが区別されることが、BodyMode側の現行モデル不足として確定した。またHevyは列名だけでなく距離単位、日時形式、セット番号基準、スーパーセット情報の版差を許容する必要がある。

### 公開サンプル差分から確定したパーサー要件

- ヘッダー名で形式とvariantを判定し、列順へ依存しない。
- UTF-8 BOM、CRLF、引用符内改行、絵文字、余分な列を許容する。
- 日時はISO風、ローカライズされた英語月名、タイムゾーン有無を分けて解析する。
- タイムゾーンがない場合は自動推測せず、取込地域を確認してプレビューへ表示する。
- `set_index`は0/1始まりをファイル単位で判定し、原値も保持する。
- `distance_meters`と`distance_km`を正規化し、単位列がない重量はユーザーがkg/lbを選ぶ。
- `superset_id`、`set_type`、未知列は捨てず、未対応メタデータとして取込レポートへ残す。
- CSV行が同じでも、取込元、ファイルfingerprint、ワークアウト日時、種目、セットを組み合わせて再取込重複を防ぐ。

公開サンプルは形式差の発見用であり、製品fixtureにはしない。製品fixtureは匿名化した公式出力を利用者の許可を得て保存する。

## 10. R9 根拠表示

### 採用候補

1. 一文: `背中は4日空いているため、今日は背中を提案しました。`
2. 判断材料: 最終実施、直近ボリューム、睡眠、疲労、利用器具、欠損データ。
3. 根拠: 研究名、対象、何を支持するか、PubMed/DOIリンク。

必須表示:

- 提案生成時刻と更新理由。
- `ローカルルール`、`AI補正`、`ユーザー変更`の出所。
- 信頼度と不足データ。
- 文献は一般的傾向の根拠であり、そのユーザー個人の結果を保証しない旨。
- 拒否、変更、手入力への導線。

### 理解度テスト

次の4問を1画面あたり5秒以内で回答できるか確認する。

1. 今日何をすればよいか。
2. なぜそれが選ばれたか。
3. どのデータが足りないか。
4. 合わない場合にどう変えるか。

提示可能な静的プロトタイプを`research-prototypes/r9_rationale_5_second_test.html`へ作成した。さらに`research-prototypes/bodymode_core_research_runner.html`へ、R5のA/B/C固定割付、R9の順序回転、5秒遮蔽、自由回答、進行役採点、ローカル保存、JSON書き出しを実装した。モバイル幅390pxで5タスクを完走し、横はみ出し、JavaScriptエラー、結果欠落がないことを確認した。参加者の正答率はまだ未取得である。

### 現行ホームのヒューリスティック監査

現行スクリーンショットと実装を基準に確認した。

| 項目 | 判定 | 根拠 |
| --- | --- | --- |
| 画面目的 | 良好 | `今日の3つ`と完了数が上部にある |
| 主操作 | 良好 | 最優先カードだけ大きな開始ボタンを持つ |
| 詳細の段階表示 | 良好 | 各行動の理由と変更が二次操作になっている |
| AI状態 | 要改善 | `確認待ち`と`提案は利用可能`が同時に表示され、ローカル提案とAI補正の差が初見で分かりにくい |
| 判断材料 | 要改善 | GOODの根拠、データ充足度、欠損は画面上から直接分からない |
| 反復操作 | 要改善 | 補助カードにも理由・変更が繰り返され、縦方向と視線移動が増える |
| 信頼・復旧 | 要改善 | 提案変更履歴や元に戻す可否が主画面から判断できない |

R9のプロトタイプでは、通常時は一文理由を表示しない。`なぜ？`を開いた時に、判断材料とAI補正の有無を先に示し、文献はさらに下の層に置く。

## 11. 実装計画を確定する前の残調査

| 必須 | 準備状況 | 残作業 | 完了条件 |
| --- | --- | --- | --- |
| R1 | 計測・集計・同意改訂・テスト完了 | 改訂版を配布して任意同意者の実利用を集計 | 目的・経験別に表示、開始、完了、差替え理由を集計できる |
| R5 | A/B/Cの実行・採点・集計ツールをブラウザ完走済み | テスター比較を実施 | 理解時間、主CTA実行、詳細閲覧を比較できる |
| R8 | Strong 2件・Hevy 3件の公開標本で非実値監査ツールを検証済み | 匿名化した現行公式エクスポートを取得 | Wave A各形式2件以上を列・単位・版差まで解析できる |
| R9 | 4ケースの実行・採点・集計ツールをブラウザ完走済み | 初見参加者で5秒テスト | 5秒テスト4問の成功率を記録できる |

これらが終わるまでは、実装計画を`暫定`のまま維持する。

## 12. R10 暫定優先順位

5点満点。リスクは高いほど先に対処する。

| 候補 | 価値 | 頻度 | 安全・損失リスク | 差別化 | 検証容易性 | 暫定順 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| iPhone自動保存・中断再開 | 5 | 5 | 5 | 3 | 5 | 1 |
| 編集・Undo・BodyMode復元 | 5 | 4 | 5 | 3 | 4 | 2 |
| DailyAction実利用計測 | 5 | 5 | 2 | 5 | 4 | 3 |
| 構造化AI計画改訂 | 5 | 3 | 4 | 5 | 3 | 4 |
| 完了画面比較 | 4 | 4 | 1 | 3 | 5 | 5 |
| 根拠3層表示 | 4 | 3 | 3 | 5 | 4 | 6 |
| Strong/Hevy取込 | 4 | 2 | 4 | 4 | 2 | 7 |
| Apple Health/JEFIT取込 | 3 | 2 | 4 | 3 | 2 | 8 |

実測後にR1、R5、R8、R9の順位を更新する。
