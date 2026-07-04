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
        imageData: Data? = nil
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
    }
}
