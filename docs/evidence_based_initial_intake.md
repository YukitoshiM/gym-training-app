# BodyMode 初回ヒアリング設計

## 目的

- 5分以内で、今日の提案に必要な最小限の情報を集める。
- 診断は行わず、運動負荷の調整と専門家の指示の優先に使う。
- 既存の目的、経験、運動頻度、器具は再質問しない。
- 回答は端末保存とし、AIへの共有は別の明示設定で制御する。

## 質問構成

| ブロック | 質問 | 提案への使い方 |
|---|---|---|
| 共通 | 定期的な運動習慣 | 開始負荷と進行速度 |
| 共通 | 予定する強度 | 医学的確認が必要な場合の判定材料 |
| 共通 | 既知の疾患、運動時症状、けが、動作制限 | 負荷を抑える、または運動提案を止める |
| 共通 | ふだんの睡眠時間帯 | 回復に関する初期値。当日のHealthKit値があればそちらを優先 |
| 減量 | 体重、食習慣、腹囲のどれを優先するか | 日次アクションの優先順位 |
| 減量・体型改善 | カロリー助言の扱い | 体重中心の助言を避ける、専門家の食事方針を優先 |
| 筋肥大 | 筋量、筋力、回復のどれを優先するか | ボリューム、漸進、回復の比重 |
| 健康維持 | 習慣、心肺体力、可動性、睡眠のどれを優先するか | WHO指針に基づく活動の種類と量 |
| 体型改善 | 写真変化、姿勢、部位バランスのどれを優先するか | 記録頻度とトレーニング配分 |
| 競技力向上 | 競技、他の練習回数、筋力・持久力・回復の優先順位 | 練習と筋トレの重複を避け、総負荷を調整 |

## 判定ルール

- 胸の痛み・圧迫感、異常な息切れ、めまい・失神、強い動悸が登録された日は、BodyModeから運動負荷を提案しない。
- けが、関節・筋肉の違和感、動作制限は、既存計画を軽くする初期条件にする。
- 専門家の指示とユーザーのメモは、AIとローカルルールの両方で最優先の制約とする。
- 欠損値を診断的に推測しない。「回答しない」を常に選べる。

## 主な根拠

- Riebe D, et al. Updating ACSM's Recommendations for Exercise Preparticipation Health Screening. 2015. https://doi.org/10.1249/MSS.0000000000000664
- World Health Organization. Guidelines on physical activity and sedentary behaviour. 2020. https://www.who.int/publications/i/item/9789240015128
- Watson NF, et al. Recommended Amount of Sleep for a Healthy Adult. 2015. https://doi.org/10.5664/jcsm.4758
- Morton RW, et al. Protein supplementation and resistance training-induced gains. 2018. https://doi.org/10.1136/bjsports-2017-097608
- Burke LE, et al. Self-Monitoring in Weight Loss: A Systematic Review. 2011. https://doi.org/10.1016/j.jada.2010.10.008
- Mountjoy M, et al. 2023 IOC consensus statement on Relative Energy Deficiency in Sport. 2023. https://doi.org/10.1136/bjsports-2023-106994

## 運用

- 定期的に最新のガイドラインと用語を確認する。
- 上記は診断ツールの転記ではない。製品の提案制御に必要な概念だけを用いる。
- 新しい質問を追加する際は、「回答が提案を変えるか」を必須条件とする。
