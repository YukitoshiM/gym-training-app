import Foundation

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "朝食"
        case .lunch: "昼食"
        case .dinner: "夕食"
        case .snack: "間食"
        }
    }
}

struct MealEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var recordedAt: Date
    var mealType: MealType
    var name: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var memo: String
    var imageData: Data?
    var aiDraft: MealAIDraft?
    var confirmedByUser: Bool

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        mealType: MealType = .lunch,
        name: String,
        calories: Double = 0,
        protein: Double = 0,
        fat: Double = 0,
        carbs: Double = 0,
        memo: String = "",
        imageData: Data? = nil,
        aiDraft: MealAIDraft? = nil,
        confirmedByUser: Bool = true
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.mealType = mealType
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.memo = memo
        self.imageData = imageData
        self.aiDraft = aiDraft
        self.confirmedByUser = confirmedByUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
        mealType = try container.decodeIfPresent(MealType.self, forKey: .mealType) ?? .lunch
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        aiDraft = try container.decodeIfPresent(MealAIDraft.self, forKey: .aiDraft)
        confirmedByUser = try container.decodeIfPresent(Bool.self, forKey: .confirmedByUser) ?? true
    }
}
