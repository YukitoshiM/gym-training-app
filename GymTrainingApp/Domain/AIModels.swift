import Foundation

struct AISettings: Codable, Equatable {
    var isEnabled: Bool
    var baseURLString: String
    var apiKey: String

    static let `default` = AISettings(
        isEnabled: true,
        baseURLString: "http://127.0.0.1:8765",
        apiKey: "dev-local-key"
    )
}

struct MealAIDraft: Codable, Hashable {
    var mealName: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var confidence: String
    var comment: String
    var items: [MealAIDraftItem]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case calories
        case protein
        case fat
        case carbs
        case confidence
        case comment
        case items
    }

    static let empty = MealAIDraft(
        mealName: "",
        calories: 0,
        protein: 0,
        fat: 0,
        carbs: 0,
        confidence: "low",
        comment: "",
        items: []
    )
}

struct MealAIDraftItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var amount: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double

    init(
        id: UUID = UUID(),
        name: String,
        amount: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
    }
}

struct BodyPhotoAIComment: Codable, Hashable {
    var summary: String
    var abdomen: String
    var waist: String
    var posture: String
    var score: Double?
    var confidence: String
}

struct AIInsight: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var insightType: AIInsightType
    var inputSummary: String
    var outputComment: String
    var actionSuggestion: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        insightType: AIInsightType,
        inputSummary: String,
        outputComment: String,
        actionSuggestion: String
    ) {
        self.id = id
        self.date = date
        self.insightType = insightType
        self.inputSummary = inputSummary
        self.outputComment = outputComment
        self.actionSuggestion = actionSuggestion
    }
}

enum AIInsightType: String, Codable, Hashable {
    case weekly
    case meal
    case bodyPhoto
}
