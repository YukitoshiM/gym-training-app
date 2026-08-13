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
        case .chest: "胸"
        case .back: "背中"
        case .traps: "僧帽筋"
        case .shoulders: "肩"
        case .biceps: "上腕二頭筋"
        case .triceps: "上腕三頭筋"
        case .forearms: "前腕"
        case .quadriceps: "大腿四頭筋"
        case .hamstrings: "ハムストリングス"
        case .glutes: "臀部"
        case .calves: "ふくらはぎ"
        case .abs: "腹直筋"
        case .obliques: "腹斜筋"
        case .arms: "腕"
        case .legs: "脚"
        case .core: "体幹"
        case .fullBody: "全身"
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
        case .barbell: "バーベル"
        case .dumbbell: "ダンベル"
        case .smithMachine: "スミスマシン"
        case .machine: "マシン"
        case .cable: "ケーブル"
        case .kettlebell: "ケトルベル"
        case .resistanceBand: "バンド"
        case .suspension: "サスペンション"
        case .bodyweight: "自重"
        case .other: "その他"
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
        case .barbell: "両手でバーを保持し、左右を同時に動かす"
        case .dumbbell: "左右を独立して動かし、軌道を調整する"
        case .smithMachine: "固定されたレール上でバーを動かす"
        case .machine: "シートとパッドを体格に合わせて使用する"
        case .cable: "一定の張力を保ちながらケーブルを動かす"
        case .kettlebell: "重心が手元から離れた器具を制御する"
        case .resistanceBand: "伸びるほど強くなる抵抗を利用する"
        case .suspension: "ストラップと自重を使って姿勢を保つ"
        case .bodyweight: "自分の体重を負荷として動く"
        case .other: "施設の器具や用途を確認して使用する"
        }
    }
}

extension Exercise {
    var equipmentSetupName: String {
        switch equipment {
        case .barbell:
            if name.contains("ベンチ") {
                return name.contains("インクライン") ? "角度付きベンチ＋バーベル" : "フラットベンチ＋バーベル"
            }
            return "バーベル＋ラック"
        case .dumbbell:
            return name.contains("ベンチ") || name.contains("フライ") || name.contains("インクライン")
                ? "ベンチ＋ダンベル"
                : "ダンベル"
        case .smithMachine:
            return "スミスマシン"
        case .machine:
            return name.hasSuffix("マシン") ? name : "\(name)マシン"
        case .cable:
            return "ケーブルマシン"
        case .kettlebell:
            return "ケトルベル"
        case .resistanceBand:
            return "トレーニングバンド"
        case .suspension:
            return "サスペンショントレーナー"
        case .bodyweight:
            if name.contains("チン") {
                return "懸垂バー"
            }
            if name.contains("ディップ") {
                return "ディップススタンド"
            }
            return "自重・マット"
        case .other:
            return "施設の専用器具"
        }
    }

    var movementName: String {
        let normalizedName = name.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        if normalizedName.contains("フライ") || normalizedName.contains("クロス") {
            return "腕を閉じる"
        }
        if normalizedName.contains("カール") {
            return "肘を曲げる"
        }
        if normalizedName.contains("レイズ") {
            return "腕を持ち上げる"
        }
        if normalizedName.contains("ロー") || normalizedName.contains("プル") || normalizedName.contains("チン") {
            return "体へ引く"
        }
        if normalizedName.contains("プレス") || normalizedName.contains("プッシュ") || normalizedName.contains("ディップ") {
            return "押し出す"
        }
        if normalizedName.contains("スクワット") || normalizedName.contains("ランジ") {
            return "しゃがんで立つ"
        }
        if normalizedName.contains("デッドリフト") || normalizedName.contains("ヒップ") {
            return "股関節を伸ばす"
        }
        if primaryMuscle == .core || primaryMuscle == .abs || primaryMuscle == .obliques {
            return "体幹を制御する"
        }
        return "フォームを保って動く"
    }

    var movementSystemImage: String {
        switch movementName {
        case "体へ引く": "arrow.left"
        case "押し出す": "arrow.right"
        case "腕を持ち上げる": "arrow.up"
        case "肘を曲げる", "腕を閉じる": "arrow.turn.up.left"
        case "しゃがんで立つ", "股関節を伸ばす": "arrow.up.and.down"
        case "体幹を制御する": "scope"
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
