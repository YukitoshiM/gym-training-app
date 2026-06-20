import Foundation

enum PresetExerciseStore {
    static let exercises: [Exercise] = [
        Exercise(
            name: "ベンチプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .arms],
            equipment: .barbell,
            instruction: "肩甲骨を寄せて胸を張り、バーを胸の中央へ下ろして押し上げる。"
        ),
        Exercise(
            name: "インクラインダンベルプレス",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .arms],
            equipment: .dumbbell,
            instruction: "ベンチに角度をつけ、胸上部を狙ってダンベルを押し上げる。"
        ),
        Exercise(
            name: "ラットプルダウン",
            primaryMuscle: .back,
            secondaryMuscles: [.arms],
            equipment: .machine,
            instruction: "胸を張り、肩をすくめずにバーを鎖骨付近へ引く。"
        ),
        Exercise(
            name: "シーテッドロー",
            primaryMuscle: .back,
            secondaryMuscles: [.arms],
            equipment: .machine,
            instruction: "背筋を伸ばし、肘を後ろに引いて背中を寄せる。"
        ),
        Exercise(
            name: "スクワット",
            primaryMuscle: .legs,
            secondaryMuscles: [.core],
            equipment: .barbell,
            instruction: "足裏全体で踏み、膝とつま先の向きを揃えてしゃがむ。"
        ),
        Exercise(
            name: "レッグプレス",
            primaryMuscle: .legs,
            equipment: .machine,
            instruction: "腰が浮かない範囲で深く下ろし、膝を伸ばし切らずに押す。"
        ),
        Exercise(
            name: "ショルダープレス",
            primaryMuscle: .shoulders,
            secondaryMuscles: [.arms],
            equipment: .dumbbell,
            instruction: "体幹を固め、肘を軽く前に出して頭上へ押し上げる。"
        ),
        Exercise(
            name: "サイドレイズ",
            primaryMuscle: .shoulders,
            equipment: .dumbbell,
            instruction: "肩をすくめず、肘を軽く曲げて横に持ち上げる。"
        ),
        Exercise(
            name: "ケーブルカール",
            primaryMuscle: .arms,
            equipment: .cable,
            instruction: "肘の位置を固定し、反動を使わずに前腕を曲げる。"
        ),
        Exercise(
            name: "トライセプスプレスダウン",
            primaryMuscle: .arms,
            equipment: .cable,
            instruction: "肘を体側に固定し、バーを下へ押し切る。"
        ),
        Exercise(
            name: "プランク",
            primaryMuscle: .core,
            equipment: .bodyweight,
            instruction: "頭から踵まで一直線を保ち、腰が落ちないように姿勢を維持する。"
        )
    ]
}

