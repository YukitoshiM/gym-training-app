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
}

extension Exercise {
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
