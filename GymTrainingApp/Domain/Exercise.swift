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
    case legs
    case shoulders
    case arms
    case core
    case fullBody

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "胸"
        case .back: "背中"
        case .legs: "脚"
        case .shoulders: "肩"
        case .arms: "腕"
        case .core: "体幹"
        case .fullBody: "全身"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Codable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "バーベル"
        case .dumbbell: "ダンベル"
        case .machine: "マシン"
        case .cable: "ケーブル"
        case .bodyweight: "自重"
        }
    }
}
