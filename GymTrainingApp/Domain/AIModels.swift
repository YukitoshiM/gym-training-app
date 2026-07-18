import Foundation

struct AISettings: Codable, Equatable {
    var isEnabled: Bool
    var baseURLString: String
    var apiKey: String
    var dataSharing: AIDataSharingSettings

    init(
        isEnabled: Bool,
        baseURLString: String,
        apiKey: String,
        dataSharing: AIDataSharingSettings = .default
    ) {
        self.isEnabled = isEnabled
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        self.dataSharing = dataSharing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        baseURLString = try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? "http://127.0.0.1:8765"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "dev-local-key"
        dataSharing = try container.decodeIfPresent(AIDataSharingSettings.self, forKey: .dataSharing) ?? .default
    }

    static let `default` = AISettings(
        isEnabled: true,
        baseURLString: "http://127.0.0.1:8765",
        apiKey: "dev-local-key"
    )
}

struct AIDataSharingSettings: Codable, Equatable {
    var bodyMetrics: Bool
    var meals: Bool
    var workouts: Bool
    var bodyPhotos: Bool
    var sleepAndRecovery: Bool
    var dailyActivity: Bool
    var gymVisits: Bool
    var workoutSensors: Bool

    static let `default` = AIDataSharingSettings(
        bodyMetrics: true,
        meals: true,
        workouts: true,
        bodyPhotos: true,
        sleepAndRecovery: false,
        dailyActivity: false,
        gymVisits: false,
        workoutSensors: false
    )

    var enabledCategoryNames: [String] {
        [
            bodyMetrics ? "身体KPI" : nil,
            meals ? "食事" : nil,
            workouts ? "筋トレ" : nil,
            bodyPhotos ? "体型写真" : nil,
            sleepAndRecovery ? "睡眠・回復" : nil,
            dailyActivity ? "日常活動" : nil,
            gymVisits ? "ジム訪問" : nil,
            workoutSensors ? "ワークアウトセンサー" : nil
        ].compactMap { $0 }
    }
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

struct AITransmissionRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var sentAt: Date
    var purpose: String
    var sharedCategories: [String]
    var itemCount: Int
    var status: AITransmissionStatus

    init(
        id: UUID = UUID(),
        sentAt: Date = Date(),
        purpose: String,
        sharedCategories: [String],
        itemCount: Int,
        status: AITransmissionStatus = .sending
    ) {
        self.id = id
        self.sentAt = sentAt
        self.purpose = purpose
        self.sharedCategories = sharedCategories
        self.itemCount = itemCount
        self.status = status
    }
}

enum AITransmissionStatus: String, Codable {
    case sending
    case completed
    case failed
}
