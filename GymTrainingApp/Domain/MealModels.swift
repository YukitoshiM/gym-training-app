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
    var foodItems: [String]
    var compositionItems: [MealCompositionItem]
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
        foodItems: [String] = [],
        compositionItems: [MealCompositionItem] = [],
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
        self.foodItems = foodItems
        self.compositionItems = compositionItems
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
        foodItems = try container.decodeIfPresent([String].self, forKey: .foodItems) ?? []
        compositionItems = try container.decodeIfPresent([MealCompositionItem].self, forKey: .compositionItems) ?? []
        aiDraft = try container.decodeIfPresent(MealAIDraft.self, forKey: .aiDraft)
        confirmedByUser = try container.decodeIfPresent(Bool.self, forKey: .confirmedByUser) ?? true
    }
}

struct DailyNutritionProgress: Equatable {
    let mealCount: Int
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let goals: NutritionGoals

    init(meals: [MealEntry], goals: NutritionGoals) {
        mealCount = meals.count
        calories = meals.reduce(0) { $0 + $1.calories }
        protein = meals.reduce(0) { $0 + $1.protein }
        fat = meals.reduce(0) { $0 + $1.fat }
        carbs = meals.reduce(0) { $0 + $1.carbs }
        self.goals = goals.normalized()
    }

    var isMealCountAchieved: Bool {
        mealCount >= goals.mealCount
    }

    var isCalorieAchieved: Bool {
        reaches(calories, goal: goals.calories)
    }

    var isPFCAchieved: Bool {
        reaches(protein, goal: goals.protein)
            && withinUpperTarget(fat, goal: goals.fat)
            && reaches(carbs, goal: goals.carbs)
    }

    var isNutritionAchieved: Bool {
        isCalorieAchieved || isPFCAchieved
    }

    var calorieProgress: Double {
        progress(calories, goal: goals.calories)
    }

    var proteinProgress: Double {
        progress(protein, goal: goals.protein)
    }

    var fatProgress: Double {
        progress(fat, goal: goals.fat)
    }

    var carbsProgress: Double {
        progress(carbs, goal: goals.carbs)
    }

    private func reaches(_ value: Double, goal: Double) -> Bool {
        goal <= 0 || value >= goal * 0.9
    }

    private func withinUpperTarget(_ value: Double, goal: Double) -> Bool {
        goal <= 0 || (value >= goal * 0.8 && value <= goal * 1.1)
    }

    private func progress(_ value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 1 }
        return min(1, max(0, value / goal))
    }
}
