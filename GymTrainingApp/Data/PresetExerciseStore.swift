import Foundation

enum PresetExerciseStore {
    static let exercises: [Exercise] = [
        // Chest
        Exercise(
            name: L10n.string("domain_catalog.c2a566ea8251", fallback: "ベンチプレス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.f3b5cbad91e8", fallback: "肩甲骨を寄せて胸を張り、バーを胸の中央へ下ろして押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.ce208d04dc8a", fallback: "インクラインベンチプレス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.e569c630ac0d", fallback: "ベンチに角度をつけ、胸上部を狙って斜め上へ押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.dcb079c45c6c", fallback: "ダンベルベンチプレス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.fd6d8990ae12", fallback: "肩甲骨を寄せ、肘を開きすぎずにダンベルを胸の横へ下ろして押す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.1b8e2d080da4", fallback: "インクラインダンベルプレス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.d2b19f8df9ef", fallback: "ベンチに角度をつけ、胸上部を狙ってダンベルを押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.883366e48839", fallback: "ダンベルフライ"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.38aea37fa327", fallback: "肘を軽く曲げたまま胸を開き、弧を描くようにダンベルを寄せる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.da46dfa1365b", fallback: "ケーブルクロスオーバー"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .cable,
            instruction: L10n.string("domain_catalog.be9bc1818213", fallback: "胸を張り、ケーブルを胸の前で合わせて大胸筋を収縮させる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.e9621eac02b3", fallback: "チェストプレス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.bfa9f9e01dcb", fallback: "シートを調整し、胸の高さから前方へ押し出す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.d3e414c96c7c", fallback: "ペックデックフライ"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.ac8f9d14bf9a", fallback: "肘または前腕でパッドを押し、胸の前で腕を閉じる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.beda4562c5ed", fallback: "プッシュアップ"),
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps, .core],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.a1f1d48b670f", fallback: "頭から踵まで一直線を保ち、胸を床へ近づけて押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a8c2f5144429", fallback: "ディップス"),
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.fae7ab24c5bd", fallback: "やや前傾し、胸と上腕三頭筋を使って体を押し上げる。")
        ),

        // Back
        Exercise(
            name: L10n.string("domain_catalog.f912225f0d5d", fallback: "ラットプルダウン"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.7df261432999", fallback: "胸を張り、肩をすくめずにバーを鎖骨付近へ引く。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.8eb6bd923f0d", fallback: "チンニング"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .core],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.05d19324262b", fallback: "肩を下げて胸を張り、肘を体側へ引く意識で体を持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.82a2aeb11b42", fallback: "バーベルロー"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .hamstrings, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.d94b736f99ef", fallback: "股関節を曲げて上体を固定し、バーをみぞおち方向へ引く。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.8c66e2563b4b", fallback: "ワンハンドダンベルロー"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.8797f4d5f573", fallback: "背中を平らに保ち、肘を腰へ引くようにダンベルを持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.2421c01f1aaf", fallback: "シーテッドロー"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.3b9441e14585", fallback: "背筋を伸ばし、肘を後ろに引いて背中を寄せる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.23e832e5df3b", fallback: "ケーブルロー"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .cable,
            instruction: L10n.string("domain_catalog.5c69a908bdc7", fallback: "骨盤を立て、肩甲骨を寄せながらハンドルを腹部へ引く。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.290018d0a5df", fallback: "ストレートアームプルダウン"),
            primaryMuscle: .back,
            secondaryMuscles: [.triceps],
            equipment: .cable,
            instruction: L10n.string("domain_catalog.1ff7bc87bcdd", fallback: "肘を軽く曲げたまま、腕を弧を描くように太もも側へ下ろす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.7acdb9a8304d", fallback: "バックエクステンション"),
            primaryMuscle: .back,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.aab8a869a7c4", fallback: "腰を反らしすぎず、股関節を支点に上体を起こす。")
        ),

        // Shoulders
        Exercise(
            name: L10n.string("domain_catalog.696ad3132f6c", fallback: "ショルダープレス"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.c69fe4f4931d", fallback: "体幹を固め、肘を軽く前に出して頭上へ押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.2a280b36e2bd", fallback: "バーベルオーバーヘッドプレス"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.4fa5744407c2", fallback: "腹圧を保ち、バーを顔の前から頭上へまっすぐ押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.e2241d1ff91a", fallback: "マシンショルダープレス"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.triceps],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.59ed1c8a7b13", fallback: "シートを調整し、肩をすくめずにハンドルを頭上へ押す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a9f236ec70e3", fallback: "サイドレイズ"),
            primaryMuscle: .shoulders,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.f041e32b3191", fallback: "肩をすくめず、肘を軽く曲げて横に持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.f80514096571", fallback: "ケーブルサイドレイズ"),
            primaryMuscle: .shoulders,
            equipment: .cable,
            instruction: L10n.string("domain_catalog.efc55a5e5d0d", fallback: "ケーブルを体の横から引き、反動を抑えて肩の横へ上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.303eb3f8b894", fallback: "フロントレイズ"),
            primaryMuscle: .shoulders,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.5d6a1ebd0a56", fallback: "体を反らさず、ダンベルを肩の高さまで前方へ上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.74f975848d5e", fallback: "リアレイズ"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.d462815994b8", fallback: "上体を倒し、肩甲骨を寄せすぎずに肘を横へ開く。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.5af670c6eade", fallback: "フェイスプル"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .cable,
            instruction: L10n.string("domain_catalog.e1f8d5497739", fallback: "ロープを顔の高さへ引き、肩後部と肩甲骨周りを意識する。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.82a081d1ac91", fallback: "アップライトロー"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.traps, .biceps],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.a740b9a4bb20", fallback: "バーを体の近くで引き上げ、肩に違和感が出ない範囲で行う。")
        ),

        // Arms
        Exercise(
            name: L10n.string("domain_catalog.c0a6d7c2a225", fallback: "バーベルカール"),
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.74eb4280f919", fallback: "肘を体側に固定し、反動を抑えてバーを持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.44071b6aba40", fallback: "ダンベルカール"),
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.49042d56f471", fallback: "肘の位置を保ち、手首を返しながらダンベルを上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.229e32a252f7", fallback: "インクラインダンベルカール"),
            primaryMuscle: .biceps,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.c4c8f8c07255", fallback: "傾斜ベンチで腕を後ろに置き、二頭筋を伸ばした位置から曲げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.fc557946398d", fallback: "ハンマーカール"),
            primaryMuscle: .biceps,
            secondaryMuscles: [.forearms],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.bf1f4a0fe72a", fallback: "手のひらを向かい合わせにし、前腕も使いながら持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.c2f484f7f013", fallback: "ケーブルカール"),
            primaryMuscle: .biceps,
            equipment: .cable,
            instruction: L10n.string("domain_catalog.d98fc69956aa", fallback: "肘の位置を固定し、反動を使わずに前腕を曲げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a7bf8f28b16d", fallback: "プリーチャーカール"),
            primaryMuscle: .biceps,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.293caccc9c79", fallback: "腕をパッドに乗せ、肘が浮かないように曲げ伸ばしする。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.6b0bfa3feb7f", fallback: "トライセプスプレスダウン"),
            primaryMuscle: .triceps,
            equipment: .cable,
            instruction: L10n.string("domain_catalog.bd5b88f852e0", fallback: "肘を体側に固定し、バーを下へ押し切る。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.da90e1d8f981", fallback: "オーバーヘッドトライセプスエクステンション"),
            primaryMuscle: .triceps,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.ac6c2ce3f8a7", fallback: "肘を開きすぎず、頭上で肘を曲げ伸ばしする。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.adb09e5a425d", fallback: "スカルクラッシャー"),
            primaryMuscle: .triceps,
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.6d905526f64f", fallback: "上腕を固定し、額の上へバーを下ろして肘を伸ばす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.bfc50ff9f2e8", fallback: "ナローベンチプレス"),
            primaryMuscle: .triceps,
            secondaryMuscles: [.chest, .shoulders],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.98506c24d2ee", fallback: "通常より狭めに握り、肘を閉じ気味にして押し上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.bde33303765d", fallback: "トライセプスキックバック"),
            primaryMuscle: .triceps,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.535a51f88058", fallback: "上腕を床と平行に近づけ、肘から先だけを後ろへ伸ばす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.0b0e3ca82493", fallback: "リストカール"),
            primaryMuscle: .forearms,
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.6c43886de639", fallback: "前腕を固定し、手首だけを曲げ伸ばしして前腕を鍛える。")
        ),

        // Lower body
        Exercise(
            name: L10n.string("domain_catalog.bb86be7f410e", fallback: "スクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.72208ced79dd", fallback: "足裏全体で踏み、膝とつま先の向きを揃えてしゃがむ。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.3e2b052a69c8", fallback: "フロントスクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.4717074d085c", fallback: "バーを肩前部で支え、上体を立てたまましゃがむ。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.1f510875c76d", fallback: "スミスマシンスクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes],
            equipment: .smithMachine,
            instruction: L10n.string("domain_catalog.a5bb33628c1d", fallback: "軌道に沿ってしゃがみ、膝とつま先の向きを揃える。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.0f7c8ab332a1", fallback: "レッグプレス"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.07083bafb071", fallback: "腰が浮かない範囲で深く下ろし、膝を伸ばし切らずに押す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.202ce690e832", fallback: "ハックスクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes],
            equipment: .machine,
            instruction: L10n.string("domain_catalog.2c82919f0aad", fallback: "背中をパッドにつけ、膝の向きを保って上下する。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.f535a50232c8", fallback: "レッグエクステンション"),
            primaryMuscle: .quadriceps,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.706df71283ca", fallback: "膝関節を軸にして脚を伸ばし、大腿四頭筋を収縮させる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.57a4cf316c90", fallback: "ブルガリアンスクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.108b69a035d3", fallback: "後ろ足を台に置き、前脚に体重を乗せてしゃがむ。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.5040d710ed48", fallback: "ランジ"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.e85958c34f0b", fallback: "一歩踏み出し、前脚の膝とつま先の向きを揃えて沈み込む。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a445012ac5ab", fallback: "ゴブレットスクワット"),
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .core],
            equipment: .kettlebell,
            instruction: L10n.string("domain_catalog.c035ffe6187c", fallback: "胸の前で重りを持ち、上体を立てたまましゃがむ。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.7539bfc86597", fallback: "ルーマニアンデッドリフト"),
            primaryMuscle: .hamstrings,
            secondaryMuscles: [.glutes, .back],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.6fbb94213999", fallback: "膝を軽く曲げ、股関節を後ろへ引いてハムストリングスを伸ばす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.3ce615b07b19", fallback: "ダンベルルーマニアンデッドリフト"),
            primaryMuscle: .hamstrings,
            secondaryMuscles: [.glutes, .back],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.50c6a86a89fe", fallback: "ダンベルを体の近くに保ち、股関節主導で上体を倒す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a63e2e368a92", fallback: "レッグカール"),
            primaryMuscle: .hamstrings,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.6c25cd154d21", fallback: "膝を支点にして踵を臀部へ近づけ、ハムストリングスを収縮させる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.6e53925a0c71", fallback: "ヒップスラスト"),
            primaryMuscle: .glutes,
            secondaryMuscles: [.hamstrings, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.886d55d3ef41", fallback: "肩甲骨付近をベンチに乗せ、骨盤を後傾させながら股関節を伸ばす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.4280d342ea70", fallback: "グルートブリッジ"),
            primaryMuscle: .glutes,
            secondaryMuscles: [.hamstrings],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.5bca283426f5", fallback: "仰向けで足裏を床につけ、臀部を締めながら腰を持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.ef6912570765", fallback: "ケーブルキックバック"),
            primaryMuscle: .glutes,
            equipment: .cable,
            instruction: L10n.string("domain_catalog.fd491d2bd8bd", fallback: "体幹を固定し、脚を後方へ蹴り出して臀部を収縮させる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.f72a879fb20d", fallback: "ヒップアブダクション"),
            primaryMuscle: .glutes,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.04fd00e0335e", fallback: "膝を外へ開き、中臀筋を意識してゆっくり戻す。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.43c77f1d88bf", fallback: "スタンディングカーフレイズ"),
            primaryMuscle: .calves,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.f74adb9e882d", fallback: "膝を伸ばしたまま踵を上げ、ふくらはぎを収縮させる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.94a47e1839ff", fallback: "シーテッドカーフレイズ"),
            primaryMuscle: .calves,
            equipment: .machine,
            instruction: L10n.string("domain_catalog.b80a2858a8d1", fallback: "座った姿勢で踵を上げ、下腿をゆっくり伸ばし縮める。")
        ),

        // Core
        Exercise(
            name: L10n.string("domain_catalog.29bc148beebf", fallback: "プランク"),
            primaryMuscle: .core,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.3ee9c2228273", fallback: "頭から踵まで一直線を保ち、腰が落ちないように姿勢を維持する。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a2aa90f41c5a", fallback: "サイドプランク"),
            primaryMuscle: .obliques,
            secondaryMuscles: [.core],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.9ce2b7c6a4ef", fallback: "肘と足で体を支え、体側が落ちないように姿勢を保つ。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.bb7c180d314c", fallback: "クランチ"),
            primaryMuscle: .abs,
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.e4fa57b19772", fallback: "腰を反らさず、みぞおちを骨盤へ近づけるように上体を丸める。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.8f628844dc9e", fallback: "ハンギングレッグレイズ"),
            primaryMuscle: .abs,
            secondaryMuscles: [.core],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.f4577fa825e1", fallback: "ぶら下がった姿勢で反動を抑え、脚を持ち上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.3969524dde47", fallback: "ケーブルクランチ"),
            primaryMuscle: .abs,
            equipment: .cable,
            instruction: L10n.string("domain_catalog.bc5c2cf53ef0", fallback: "骨盤を固定し、背中を丸めるようにケーブルを引き下げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.bb89e66f6f35", fallback: "アブローラー"),
            primaryMuscle: .abs,
            secondaryMuscles: [.core, .shoulders],
            equipment: .other,
            instruction: L10n.string("domain_catalog.502e3b30230d", fallback: "腰を反らさず、体幹を固めたままローラーを前方へ転がす。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.af273fdc159a", fallback: "ロシアンツイスト"),
            primaryMuscle: .obliques,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.893f386f44d0", fallback: "背中を丸めすぎず、体幹を左右にひねる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a21d92684639", fallback: "デッドバグ"),
            primaryMuscle: .core,
            secondaryMuscles: [.abs],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.cf9aa255c8df", fallback: "腰を床に近づけたまま、対角の手足をゆっくり伸ばす。")
        ),

        // Full body and conditioning
        Exercise(
            name: L10n.string("domain_catalog.8e1637849284", fallback: "デッドリフト"),
            primaryMuscle: .fullBody,
            secondaryMuscles: [.back, .glutes, .hamstrings, .quadriceps, .core],
            equipment: .barbell,
            instruction: L10n.string("domain_catalog.b0b9c30ff338", fallback: "バーを体の近くに保ち、背中を丸めずに床から引き上げる。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.df1bc7d67526", fallback: "ケトルベルスイング"),
            primaryMuscle: .fullBody,
            secondaryMuscles: [.glutes, .hamstrings, .core],
            equipment: .kettlebell,
            instruction: L10n.string("domain_catalog.fe37c9ed6763", fallback: "腕で持ち上げず、股関節の伸展でケトルベルを振る。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.c749f18edd8d", fallback: "ファーマーズウォーク"),
            primaryMuscle: .fullBody,
            secondaryMuscles: [.forearms, .core, .traps],
            equipment: .dumbbell,
            instruction: L10n.string("domain_catalog.0660b9fa7db9", fallback: "重りを両手に持ち、体幹を固めて背筋を伸ばして歩く。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.8dc615a1cbbf", fallback: "バーピー"),
            primaryMuscle: .fullBody,
            secondaryMuscles: [.chest, .quadriceps, .core],
            equipment: .bodyweight,
            instruction: L10n.string("domain_catalog.ea7e68e02761", fallback: "しゃがむ、腕立て姿勢、ジャンプを連続して行う。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.9ed5d6ea2c6a", fallback: "TRXロー"),
            primaryMuscle: .back,
            secondaryMuscles: [.biceps, .core],
            equipment: .suspension,
            instruction: L10n.string("domain_catalog.66d79da7b3e4", fallback: "体を一直線に保ち、肘を後ろへ引いて胸をハンドルへ近づける。")
        ),
        Exercise(
            name: L10n.string("domain_catalog.a65e66cf431a", fallback: "バンドプルアパート"),
            primaryMuscle: .shoulders,
            secondaryMuscles: [.back],
            equipment: .resistanceBand,
            instruction: L10n.string("domain_catalog.8184e17f695d", fallback: "腕を伸ばしたままバンドを左右に開き、肩後部と背中を使う。")
        )
    ]
}
