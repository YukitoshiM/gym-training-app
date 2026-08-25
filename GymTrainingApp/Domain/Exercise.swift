import Foundation

struct Exercise: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let primaryMuscle: MuscleGroup
    let secondaryMuscles: [MuscleGroup]
    let equipment: Equipment
    let instruction: String

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        instruction: String
    ) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instruction = instruction
    }
}

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest
    case back
    case traps
    case shoulders
    case biceps
    case triceps
    case forearms
    case quadriceps
    case hamstrings
    case glutes
    case calves
    case core
    case abs
    case obliques
    case fullBody
    case arms
    case legs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: L10n.string("domain_catalog.39acb71c4382", fallback: "胸")
        case .back: L10n.string("domain_catalog.31f85c63408c", fallback: "背中")
        case .traps: L10n.string("domain_catalog.0691ba053a52", fallback: "僧帽筋")
        case .shoulders: L10n.string("domain_catalog.5c177baeb760", fallback: "肩")
        case .biceps: L10n.string("domain_catalog.c7c955f95fae", fallback: "上腕二頭筋")
        case .triceps: L10n.string("domain_catalog.c3a15e701859", fallback: "上腕三頭筋")
        case .forearms: L10n.string("domain_catalog.07526d7f2cc6", fallback: "前腕")
        case .quadriceps: L10n.string("domain_catalog.008dc77eb69f", fallback: "大腿四頭筋")
        case .hamstrings: L10n.string("domain_catalog.e7927193d843", fallback: "ハムストリングス")
        case .glutes: L10n.string("domain_catalog.0a9b53448d57", fallback: "臀部")
        case .calves: L10n.string("domain_catalog.36f6c898b53a", fallback: "ふくらはぎ")
        case .abs: L10n.string("domain_catalog.a7648212eeed", fallback: "腹直筋")
        case .obliques: L10n.string("domain_catalog.5b338e4ab472", fallback: "腹斜筋")
        case .arms: L10n.string("domain_catalog.2d8d11ce0fe6", fallback: "腕")
        case .legs: L10n.string("domain_catalog.eeb0aa3e0d43", fallback: "脚")
        case .core: L10n.string("domain_catalog.0c52dc2ec22b", fallback: "体幹")
        case .fullBody: L10n.string("domain_catalog.8ff8ddea80c6", fallback: "全身")
        }
    }

    var systemImage: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back, .traps: "figure.strengthtraining.functional"
        case .shoulders: "figure.arms.open"
        case .biceps, .triceps, .forearms, .arms: "dumbbell.fill"
        case .quadriceps, .hamstrings, .glutes, .calves, .legs: "figure.walk"
        case .core, .abs, .obliques: "figure.core.training"
        case .fullBody: "figure.mixed.cardio"
        }
    }

    static var selectionCases: [MuscleGroup] {
        [
            .chest,
            .back,
            .traps,
            .shoulders,
            .biceps,
            .triceps,
            .forearms,
            .quadriceps,
            .hamstrings,
            .glutes,
            .calves,
            .abs,
            .obliques,
            .core,
            .fullBody
        ]
    }

    static var focusSelectionCases: [MuscleGroup] {
        [.chest, .back, .shoulders, .arms, .quadriceps, .glutes, .core]
    }

    var relatedGroups: Set<MuscleGroup> {
        switch self {
        case .arms:
            [.arms, .biceps, .triceps, .forearms]
        case .legs:
            [.legs, .quadriceps, .hamstrings, .glutes, .calves]
        case .core:
            [.core, .abs, .obliques]
        default:
            [self]
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Codable {
    case barbell
    case dumbbell
    case smithMachine
    case machine
    case cable
    case kettlebell
    case resistanceBand
    case suspension
    case bodyweight
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: L10n.string("domain_catalog.9d84b8975c8e", fallback: "バーベル")
        case .dumbbell: L10n.string("domain_catalog.3e3505b43c22", fallback: "ダンベル")
        case .smithMachine: L10n.string("domain_catalog.a561fd10109b", fallback: "スミスマシン")
        case .machine: L10n.string("domain_catalog.6ec7c09949a1", fallback: "マシン")
        case .cable: L10n.string("domain_catalog.f23ffd13e49f", fallback: "ケーブル")
        case .kettlebell: L10n.string("domain_catalog.cb57944e9d86", fallback: "ケトルベル")
        case .resistanceBand: L10n.string("domain_catalog.078284b91915", fallback: "バンド")
        case .suspension: L10n.string("domain_catalog.a7b9552f5f66", fallback: "サスペンション")
        case .bodyweight: L10n.string("domain_catalog.85d0ccc5ceba", fallback: "自重")
        case .other: L10n.string("domain_catalog.e3ad94e4b3b3", fallback: "その他")
        }
    }

    var systemImage: String {
        switch self {
        case .barbell: "dumbbell.fill"
        case .dumbbell: "dumbbell"
        case .smithMachine: "square.grid.3x3.fill"
        case .machine: "gearshape.2.fill"
        case .cable: "point.3.connected.trianglepath.dotted"
        case .kettlebell: "scalemass.fill"
        case .resistanceBand: "link"
        case .suspension: "lines.measurement.horizontal"
        case .bodyweight: "figure.strengthtraining.functional"
        case .other: "wrench.and.screwdriver.fill"
        }
    }

    var usageDescription: String {
        switch self {
        case .barbell: L10n.string("domain_catalog.e6dc11c050a3", fallback: "両手でバーを保持し、左右を同時に動かす")
        case .dumbbell: L10n.string("domain_catalog.7239b6b11f9d", fallback: "左右を独立して動かし、軌道を調整する")
        case .smithMachine: L10n.string("domain_catalog.1c3c0f3425a7", fallback: "固定されたレール上でバーを動かす")
        case .machine: L10n.string("domain_catalog.b3fdfb32748f", fallback: "シートとパッドを体格に合わせて使用する")
        case .cable: L10n.string("domain_catalog.774cb95972ff", fallback: "一定の張力を保ちながらケーブルを動かす")
        case .kettlebell: L10n.string("domain_catalog.88e6880332b9", fallback: "重心が手元から離れた器具を制御する")
        case .resistanceBand: L10n.string("domain_catalog.60a3e4582b17", fallback: "伸びるほど強くなる抵抗を利用する")
        case .suspension: L10n.string("domain_catalog.7fd846c04ba8", fallback: "ストラップと自重を使って姿勢を保つ")
        case .bodyweight: L10n.string("domain_catalog.789e6b234dde", fallback: "自分の体重を負荷として動く")
        case .other: L10n.string("domain_catalog.23caae87951d", fallback: "施設の器具や用途を確認して使用する")
        }
    }
}

extension Exercise {
    var equipmentSetupName: String {
        switch equipment {
        case .barbell:
            if name.contains(L10n.string("domain_catalog.f39a081101ef", fallback: "ベンチ")) {
                return name.contains(L10n.string("domain_catalog.0d134133df87", fallback: "インクライン")) ? L10n.string("domain_catalog.3468c99d967b", fallback: "角度付きベンチ＋バーベル") : L10n.string("domain_catalog.b21d4fe27511", fallback: "フラットベンチ＋バーベル")
            }
            return L10n.string("domain_catalog.e04f1c15ff26", fallback: "バーベル＋ラック")
        case .dumbbell:
            return name.contains(L10n.string("domain_catalog.f39a081101ef", fallback: "ベンチ")) || name.contains(L10n.string("domain_catalog.0e398c444a63", fallback: "フライ")) || name.contains(L10n.string("domain_catalog.0d134133df87", fallback: "インクライン"))
                ? L10n.string("domain_catalog.1ef485639c52", fallback: "ベンチ＋ダンベル")
                : L10n.string("domain_catalog.3e3505b43c22", fallback: "ダンベル")
        case .smithMachine:
            return L10n.string("domain_catalog.a561fd10109b", fallback: "スミスマシン")
        case .machine:
            return name.hasSuffix(L10n.string("domain_catalog.6ec7c09949a1", fallback: "マシン")) ? name : L10n.string("domain_catalog.a140ea27deb0", fallback: "{{value1}}マシン", values: [String(describing: name)])
        case .cable:
            return L10n.string("domain_catalog.d4547ef759f3", fallback: "ケーブルマシン")
        case .kettlebell:
            return L10n.string("domain_catalog.cb57944e9d86", fallback: "ケトルベル")
        case .resistanceBand:
            return L10n.string("domain_catalog.3131957a07ea", fallback: "トレーニングバンド")
        case .suspension:
            return L10n.string("domain_catalog.1d2f5637f72f", fallback: "サスペンショントレーナー")
        case .bodyweight:
            if name.contains(L10n.string("domain_catalog.57ae8b998965", fallback: "チン")) {
                return L10n.string("domain_catalog.c5bc251eecc5", fallback: "懸垂バー")
            }
            if name.contains(L10n.string("domain_catalog.630273f87ac0", fallback: "ディップ")) {
                return L10n.string("domain_catalog.35430f21626e", fallback: "ディップススタンド")
            }
            return L10n.string("domain_catalog.f7d7d09ec6af", fallback: "自重・マット")
        case .other:
            return L10n.string("domain_catalog.ef202f8d8cc2", fallback: "施設の専用器具")
        }
    }

    var movementName: String {
        let normalizedName = name.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        if normalizedName.contains(L10n.string("domain_catalog.0e398c444a63", fallback: "フライ")) || normalizedName.contains(L10n.string("domain_catalog.2ae9779480d0", fallback: "クロス")) {
            return L10n.string("domain_catalog.b86a2354e349", fallback: "腕を閉じる")
        }
        if normalizedName.contains(L10n.string("domain_catalog.7215a2ca998d", fallback: "カール")) {
            return L10n.string("domain_catalog.83730a291436", fallback: "肘を曲げる")
        }
        if normalizedName.contains(L10n.string("domain_catalog.7c83ed5189f6", fallback: "レイズ")) {
            return L10n.string("domain_catalog.34e9cbb6de7b", fallback: "腕を持ち上げる")
        }
        if normalizedName.contains(L10n.string("domain_catalog.f93900b1afc2", fallback: "ロー")) || normalizedName.contains(L10n.string("domain_catalog.66c3d2cc0715", fallback: "プル")) || normalizedName.contains(L10n.string("domain_catalog.57ae8b998965", fallback: "チン")) {
            return L10n.string("domain_catalog.b6d4c6091e0b", fallback: "体へ引く")
        }
        if normalizedName.contains(L10n.string("domain_catalog.38a7433c29d6", fallback: "プレス")) || normalizedName.contains(L10n.string("domain_catalog.1b4073f615d8", fallback: "プッシュ")) || normalizedName.contains(L10n.string("domain_catalog.630273f87ac0", fallback: "ディップ")) {
            return L10n.string("domain_catalog.2b1e37af5f6b", fallback: "押し出す")
        }
        if normalizedName.contains(L10n.string("domain_catalog.bb86be7f410e", fallback: "スクワット")) || normalizedName.contains(L10n.string("domain_catalog.5040d710ed48", fallback: "ランジ")) {
            return L10n.string("domain_catalog.e1b7b23b9300", fallback: "しゃがんで立つ")
        }
        if normalizedName.contains(L10n.string("domain_catalog.8e1637849284", fallback: "デッドリフト")) || normalizedName.contains(L10n.string("domain_catalog.e528d95671c8", fallback: "ヒップ")) {
            return L10n.string("domain_catalog.d5e0b518f056", fallback: "股関節を伸ばす")
        }
        if primaryMuscle == .core || primaryMuscle == .abs || primaryMuscle == .obliques {
            return L10n.string("domain_catalog.63b90f2a3e7b", fallback: "体幹を制御する")
        }
        return L10n.string("domain_catalog.3eafb191a8f3", fallback: "フォームを保って動く")
    }

    var movementSystemImage: String {
        switch movementName {
        case L10n.string("domain_catalog.b6d4c6091e0b", fallback: "体へ引く"): "arrow.left"
        case L10n.string("domain_catalog.2b1e37af5f6b", fallback: "押し出す"): "arrow.right"
        case L10n.string("domain_catalog.34e9cbb6de7b", fallback: "腕を持ち上げる"): "arrow.up"
        case L10n.string("domain_catalog.83730a291436", fallback: "肘を曲げる"), L10n.string("domain_catalog.b86a2354e349", fallback: "腕を閉じる"): "arrow.turn.up.left"
        case L10n.string("domain_catalog.e1b7b23b9300", fallback: "しゃがんで立つ"), L10n.string("domain_catalog.d5e0b518f056", fallback: "股関節を伸ばす"): "arrow.up.and.down"
        case L10n.string("domain_catalog.63b90f2a3e7b", fallback: "体幹を制御する"): "scope"
        default: "arrow.left.and.right"
        }
    }

    var supportsAssistedLoad: Bool {
        AssistedLoadSupport.isSupported(exerciseName: name)
    }

    var isDipExercise: Bool {
        AssistedLoadSupport.isDip(exerciseName: name)
    }

    var weightInputRange: ClosedRange<Double> {
        supportsAssistedLoad ? AssistedLoadSupport.kilogramRange : 0...999
    }

    func matches(muscle selectedMuscle: MuscleGroup?) -> Bool {
        guard let selectedMuscle else {
            return true
        }

        let targetGroups = selectedMuscle.relatedGroups
        return targetGroups.contains(primaryMuscle)
        || secondaryMuscles.contains { targetGroups.contains($0) }
    }

    func matches(equipment selectedEquipment: Equipment?) -> Bool {
        guard let selectedEquipment else {
            return true
        }

        return equipment == selectedEquipment
    }
}
