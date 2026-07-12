import Foundation

enum PresetExerciseStore {
    static let exercises: [Exercise] = [
        // Chest
        Exercise(
            name: "ベンチプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .barbell,
            instruction: "肩甲骨を寄せて胸を張り、バーを胸の中央へ下ろして押し上げる。"
        ),
        Exercise(
            name: "インクラインベンチプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .barbell,
            instruction: "ベンチに角度をつけ、胸上部を狙って斜め上へ押し上げる。"
        ),
        Exercise(
            name: "ダンベルベンチプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .dumbbell,
            instruction: "肩甲骨を寄せ、肘を開きすぎずにダンベルを胸の横へ下ろして押す。"
        ),
        Exercise(
            name: "インクラインダンベルプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .dumbbell,
            instruction: "ベンチに角度をつけ、胸上部を狙ってダンベルを押し上げる。"
        ),
        Exercise(
            name: "ダンベルフライ",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .dumbbell,
            instruction: "肘を軽く曲げたまま胸を開き、弧を描くようにダンベルを寄せる。"
        ),
        Exercise(
            name: "ケーブルクロスオーバー",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .cable,
            instruction: "胸を張り、ケーブルを胸の前で合わせて大胸筋を収縮させる。"
        ),
        Exercise(
            name: "チェストプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .machine,
            instruction: "シートを調整し、胸の高さから前方へ押し出す。"
        ),
        Exercise(
            name: "ペックデックフライ",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .machine,
            instruction: "肘または前腕でパッドを押し、胸の前で腕を閉じる。"
        ),
        Exercise(
            name: "プッシュアップ",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps, .core],
            equipment: .bodyweight,
            instruction: "頭から踵まで一直線を保ち、胸を床へ近づけて押し上げる。"
        ),
        Exercise(
            name: "ディップス",
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .bodyweight,
            instruction: "やや前傾し、胸と上腕三頭筋を使って体を押し上げる。"
        ),

        // Back
        Exercise(
            name: "ラットプルダウン",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .machine,
            instruction: "胸を張り、肩をすくめずにバーを鎖骨付近へ引く。"
        ),
        Exercise(
            name: "チンニング",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .core],
            equipment: .bodyweight,
            instruction: "肩を下げて胸を張り、肘を体側へ引く意識で体を持ち上げる。"
        ),
        Exercise(
            name: "バーベルロー",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .hamstrings, .core],
            equipment: .barbell,
            instruction: "股関節を曲げて上体を固定し、バーをみぞおち方向へ引く。"
        ),
        Exercise(
            name: "ワンハンドダンベルロー",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .dumbbell,
            instruction: "背中を平らに保ち、肘を腰へ引くようにダンベルを持ち上げる。"
        ),
        Exercise(
            name: "シーテッドロー",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .machine,
            instruction: "背筋を伸ばし、肘を後ろに引いて背中を寄せる。"
        ),
        Exercise(
            name: "ケーブルロー",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .cable,
            instruction: "骨盤を立て、肩甲骨を寄せながらハンドルを腹部へ引く。"
        ),
        Exercise(
            name: "ストレートアームプルダウン",
            primaryMuscle: .back,
            secondaryMuscles: [.triceps],
            equipment: .cable,
            instruction: "肘を軽く曲げたまま、腕を弧を描くように太もも側へ下ろす。"
        ),
        Exercise(
            name: "バックエクステンション",
            primaryMuscle: .back,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .bodyweight,
            instruction: "腰を反らしすぎず、股関節を支点に上体を起こす。"
        ),

        // Shoulders
        Exercise(
            name: "ショルダープレス",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps],
            equipment: .dumbbell,
            instruction: "体幹を固め、肘を軽く前に出して頭上へ押し上げる。"
        ),
        Exercise(
            name: "バーベルオーバーヘッドプレス",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps, .core],
            equipment: .barbell,
            instruction: "腹圧を保ち、バーを顔の前から頭上へまっすぐ押し上げる。"
        ),
        Exercise(
            name: "マシンショルダープレス",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps],
            equipment: .machine,
            instruction: "シートを調整し、肩をすくめずにハンドルを頭上へ押す。"
        ),
        Exercise(
            name: "サイドレイズ",
            primaryMuscle: .shoulders,
            equipment: .dumbbell,
            instruction: "肩をすくめず、肘を軽く曲げて横に持ち上げる。"
        ),
        Exercise(
            name: "ケーブルサイドレイズ",
            primaryMuscle: .shoulders,
            equipment: .cable,
            instruction: "ケーブルを体の横から引き、反動を抑えて肩の横へ上げる。"
        ),
        Exercise(
            name: "フロントレイズ",
            primaryMuscle: .shoulders,
            equipment: .dumbbell,
            instruction: "体を反らさず、ダンベルを肩の高さまで前方へ上げる。"
        ),
        Exercise(
            name: "リアレイズ",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .dumbbell,
            instruction: "上体を倒し、肩甲骨を寄せすぎずに肘を横へ開く。"
        ),
        Exercise(
            name: "フェイスプル",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .cable,
            instruction: "ロープを顔の高さへ引き、肩後部と肩甲骨周りを意識する。"
        ),
        Exercise(
            name: "アップライトロー",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.traps, .biceps],
            equipment: .barbell,
            instruction: "バーを体の近くで引き上げ、肩に違和感が出ない範囲で行う。"
        ),

        // Arms
        Exercise(
            name: "バーベルカール",
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .barbell,
            instruction: "肘を体側に固定し、反動を抑えてバーを持ち上げる。"
        ),
        Exercise(
            name: "ダンベルカール",
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .dumbbell,
            instruction: "肘の位置を保ち、手首を返しながらダンベルを上げる。"
        ),
        Exercise(
            name: "インクラインダンベルカール",
            primaryMuscle: .biceps,
            equipment: .dumbbell,
            instruction: "傾斜ベンチで腕を後ろに置き、二頭筋を伸ばした位置から曲げる。"
        ),
        Exercise(
            name: "ハンマーカール",
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .dumbbell,
            instruction: "手のひらを向かい合わせにし、前腕も使いながら持ち上げる。"
        ),
        Exercise(
            name: "ケーブルカール",
            primaryMuscle: .biceps,
            equipment: .cable,
            instruction: "肘の位置を固定し、反動を使わずに前腕を曲げる。"
        ),
        Exercise(
            name: "プリーチャーカール",
            primaryMuscle: .biceps,
            equipment: .machine,
            instruction: "腕をパッドに乗せ、肘が浮かないように曲げ伸ばしする。"
        ),
        Exercise(
            name: "トライセプスプレスダウン",
            primaryMuscle: .triceps,
            equipment: .cable,
            instruction: "肘を体側に固定し、バーを下へ押し切る。"
        ),
        Exercise(
            name: "オーバーヘッドトライセプスエクステンション",
            primaryMuscle: .triceps,
            equipment: .dumbbell,
            instruction: "肘を開きすぎず、頭上で肘を曲げ伸ばしする。"
        ),
        Exercise(
            name: "スカルクラッシャー",
            primaryMuscle: .triceps,
            equipment: .barbell,
            instruction: "上腕を固定し、額の上へバーを下ろして肘を伸ばす。"
        ),
        Exercise(
            name: "ナローベンチプレス",
            primaryMuscle: .triceps,
            secondaryMuscles: [.chest, .shoulders],
            equipment: .barbell,
            instruction: "通常より狭めに握り、肘を閉じ気味にして押し上げる。"
        ),
        Exercise(
            name: "トライセプスキックバック",
            primaryMuscle: .triceps,
            equipment: .dumbbell,
            instruction: "上腕を床と平行に近づけ、肘から先だけを後ろへ伸ばす。"
        ),
        Exercise(
            name: "リストカール",
            primaryMuscle: .forearms,
            equipment: .dumbbell,
            instruction: "前腕を固定し、手首だけを曲げ伸ばしして前腕を鍛える。"
        ),

        // Lower body
        Exercise(
            name: "スクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .barbell,
            instruction: "足裏全体で踏み、膝とつま先の向きを揃えてしゃがむ。"
        ),
        Exercise(
            name: "フロントスクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .core],
            equipment: .barbell,
            instruction: "バーを肩前部で支え、上体を立てたまましゃがむ。"
        ),
        Exercise(
            name: "スミスマシンスクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes],
            equipment: .smithMachine,
            instruction: "軌道に沿ってしゃがみ、膝とつま先の向きを揃える。"
        ),
        Exercise(
            name: "レッグプレス",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .machine,
            instruction: "腰が浮かない範囲で深く下ろし、膝を伸ばし切らずに押す。"
        ),
        Exercise(
            name: "ハックスクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes],
            equipment: .machine,
            instruction: "背中をパッドにつけ、膝の向きを保って上下する。"
        ),
        Exercise(
            name: "レッグエクステンション",
            primaryMuscle: .quadriceps,
            equipment: .machine,
            instruction: "膝関節を軸にして脚を伸ばし、大腿四頭筋を収縮させる。"
        ),
        Exercise(
            name: "ブルガリアンスクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .dumbbell,
            instruction: "後ろ足を台に置き、前脚に体重を乗せてしゃがむ。"
        ),
        Exercise(
            name: "ランジ",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .dumbbell,
            instruction: "一歩踏み出し、前脚の膝とつま先の向きを揃えて沈み込む。"
        ),
        Exercise(
            name: "ゴブレットスクワット",
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .core],
            equipment: .kettlebell,
            instruction: "胸の前で重りを持ち、上体を立てたまましゃがむ。"
        ),
        Exercise(
            name: "ルーマニアンデッドリフト",
            primaryMuscle: .hamstrings,
            secondaryMuscles: [.glutes, .back],
            equipment: .barbell,
            instruction: "膝を軽く曲げ、股関節を後ろへ引いてハムストリングスを伸ばす。"
        ),
        Exercise(
            name: "ダンベルルーマニアンデッドリフト",
            primaryMuscle: .hamstrings,
            secondaryMuscles: [.glutes, .back],
            equipment: .dumbbell,
            instruction: "ダンベルを体の近くに保ち、股関節主導で上体を倒す。"
        ),
        Exercise(
            name: "レッグカール",
            primaryMuscle: .hamstrings,
            equipment: .machine,
            instruction: "膝を支点にして踵を臀部へ近づけ、ハムストリングスを収縮させる。"
        ),
        Exercise(
            name: "ヒップスラスト",
            primaryMuscle: .glutes,
            secondaryMuscles: [.hamstrings, .core],
            equipment: .barbell,
            instruction: "肩甲骨付近をベンチに乗せ、骨盤を後傾させながら股関節を伸ばす。"
        ),
        Exercise(
            name: "グルートブリッジ",
            primaryMuscle: .glutes,
            secondaryMuscles: [.hamstrings],
            equipment: .bodyweight,
            instruction: "仰向けで足裏を床につけ、臀部を締めながら腰を持ち上げる。"
        ),
        Exercise(
            name: "ケーブルキックバック",
            primaryMuscle: .glutes,
            equipment: .cable,
            instruction: "体幹を固定し、脚を後方へ蹴り出して臀部を収縮させる。"
        ),
        Exercise(
            name: "ヒップアブダクション",
            primaryMuscle: .glutes,
            equipment: .machine,
            instruction: "膝を外へ開き、中臀筋を意識してゆっくり戻す。"
        ),
        Exercise(
            name: "スタンディングカーフレイズ",
            primaryMuscle: .calves,
            equipment: .machine,
            instruction: "膝を伸ばしたまま踵を上げ、ふくらはぎを収縮させる。"
        ),
        Exercise(
            name: "シーテッドカーフレイズ",
            primaryMuscle: .calves,
            equipment: .machine,
            instruction: "座った姿勢で踵を上げ、下腿をゆっくり伸ばし縮める。"
        ),

        // Core
        Exercise(
            name: "プランク",
            primaryMuscle: .core,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: "頭から踵まで一直線を保ち、腰が落ちないように姿勢を維持する。"
        ),
        Exercise(
            name: "サイドプランク",
            primaryMuscle: .obliques,
            secondaryMuscles: [.core],
            equipment: .bodyweight,
            instruction: "肘と足で体を支え、体側が落ちないように姿勢を保つ。"
        ),
        Exercise(
            name: "クランチ",
            primaryMuscle: .abs,
            equipment: .bodyweight,
            instruction: "腰を反らさず、みぞおちを骨盤へ近づけるように上体を丸める。"
        ),
        Exercise(
            name: "ハンギングレッグレイズ",
            primaryMuscle: .abs,
            secondaryMuscles: [.core],
            equipment: .bodyweight,
            instruction: "ぶら下がった姿勢で反動を抑え、脚を持ち上げる。"
        ),
        Exercise(
            name: "ケーブルクランチ",
            primaryMuscle: .abs,
            equipment: .cable,
            instruction: "骨盤を固定し、背中を丸めるようにケーブルを引き下げる。"
        ),
        Exercise(
            name: "アブローラー",
            primaryMuscle: .abs,
            secondaryMuscles: [.core, .shoulders],
            equipment: .other,
            instruction: "腰を反らさず、体幹を固めたままローラーを前方へ転がす。"
        ),
        Exercise(
            name: "ロシアンツイスト",
            primaryMuscle: .obliques,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: "背中を丸めすぎず、体幹を左右にひねる。"
        ),
        Exercise(
            name: "デッドバグ",
            primaryMuscle: .core,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: "腰を床に近づけたまま、対角の手足をゆっくり伸ばす。"
        ),

        // Full body and conditioning
        Exercise(
            name: "デッドリフト",
            primaryMuscle: .fullBody,
            secondaryMuscles: [.back, .glutes, .hamstrings, .quadriceps, .core],
            equipment: .barbell,
            instruction: "バーを体の近くに保ち、背中を丸めずに床から引き上げる。"
        ),
        Exercise(
            name: "ケトルベルスイング",
            primaryMuscle: .fullBody,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .kettlebell,
            instruction: "腕で持ち上げず、股関節の伸展でケトルベルを振る。"
        ),
        Exercise(
            name: "ファーマーズウォーク",
            primaryMuscle: .fullBody,
            secondaryMuscles: [.forearms, .core, .traps],
            equipment: .dumbbell,
            instruction: "重りを両手に持ち、体幹を固めて背筋を伸ばして歩く。"
        ),
        Exercise(
            name: "バーピー",
            primaryMuscle: .fullBody,
            secondaryMuscles: [.chest, .quadriceps, .core],
            equipment: .bodyweight,
            instruction: "しゃがむ、腕立て姿勢、ジャンプを連続して行う。"
        ),
        Exercise(
            name: "TRXロー",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .core],
            equipment: .suspension,
            instruction: "体を一直線に保ち、肘を後ろへ引いて胸をハンドルへ近づける。"
        ),
        Exercise(
            name: "バンドプルアパート",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .resistanceBand,
            instruction: "腕を伸ばしたままバンドを左右に開き、肩後部と背中を使う。"
        )
    ]
}
