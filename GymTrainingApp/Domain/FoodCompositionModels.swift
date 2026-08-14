import Foundation

struct NutritionAmount: Codable, Hashable {
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double

    static let zero = NutritionAmount(calories: 0, protein: 0, fat: 0, carbs: 0)

    static func + (left: NutritionAmount, right: NutritionAmount) -> NutritionAmount {
        NutritionAmount(
            calories: left.calories + right.calories,
            protein: left.protein + right.protein,
            fat: left.fat + right.fat,
            carbs: left.carbs + right.carbs
        )
    }

    func scaled(by multiplier: Double) -> NutritionAmount {
        NutritionAmount(
            calories: calories * multiplier,
            protein: protein * multiplier,
            fat: fat * multiplier,
            carbs: carbs * multiplier
        )
    }
}

enum FoodCompositionNutrient: String, Codable, Hashable {
    case calories
    case protein
    case fat
    case carbs

    var displayName: String {
        switch self {
        case .calories: "カロリー"
        case .protein: "たんぱく質"
        case .fat: "脂質"
        case .carbs: "炭水化物"
        }
    }
}

struct FoodCompositionItem: Codable, Hashable, Identifiable {
    var id: String
    var foodGroup: String
    var name: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var unavailableNutrients: [FoodCompositionNutrient]
    var traceNutrients: [FoodCompositionNutrient]

    enum CodingKeys: String, CodingKey {
        case id
        case foodGroup = "food_group"
        case name
        case calories
        case protein
        case fat
        case carbs
        case unavailableNutrients = "unavailable_nutrients"
        case traceNutrients = "trace_nutrients"
    }

    var nutritionPer100Grams: NutritionAmount {
        NutritionAmount(calories: calories, protein: protein, fat: fat, carbs: carbs)
    }

    var dataQualityNote: String? {
        if !unavailableNutrients.isEmpty {
            return "未測定: \(unavailableNutrients.map(\.displayName).joined(separator: "・"))"
        }
        if !traceNutrients.isEmpty {
            return "微量: \(traceNutrients.map(\.displayName).joined(separator: "・"))"
        }
        return nil
    }
}

struct FoodCompositionCatalog: Codable, Hashable {
    var sourceName: String
    var sourceURL: String
    var correctionDate: String
    var basis: String
    var attribution: String
    var items: [FoodCompositionItem]

    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case correctionDate = "correction_date"
        case basis
        case attribution
        case items
    }
}

final class FoodCompositionDatabase: @unchecked Sendable {
    static let shared = FoodCompositionDatabase()

    let catalog: FoodCompositionCatalog

    init(catalog: FoodCompositionCatalog? = nil) {
        self.catalog = catalog ?? Self.loadBundledCatalog()
    }

    func search(_ query: String, limit: Int = 30) -> [FoodCompositionItem] {
        let words = Self.normalized(query)
            .split(separator: " ")
            .map(String.init)
        guard !words.isEmpty else { return Array(catalog.items.prefix(limit)) }

        return catalog.items
            .lazy
            .filter { item in
                let candidate = Self.normalized(item.name)
                return words.allSatisfy(candidate.contains)
            }
            .prefix(limit)
            .map { $0 }
    }

    func conservativeMatch(for candidateName: String) -> FoodCompositionItem? {
        let candidate = Self.normalized(candidateName)
        guard !candidate.isEmpty else { return nil }

        let aliases = [
            "白ごはん": "01088",
            "白ご飯": "01088",
            "ごはん": "01088",
            "ご飯": "01088",
            "炊いた白ごはん": "01088",
            "炊いた白ご飯": "01088",
        ]
        if let sourceID = aliases[candidate] {
            return catalog.items.first { $0.id == sourceID }
        }

        let exactMatches = catalog.items.filter { Self.normalized($0.name) == candidate }
        guard exactMatches.count == 1 else { return nil }
        return exactMatches[0]
    }

    private static func loadBundledCatalog() -> FoodCompositionCatalog {
        let bundles = [Bundle.main, Bundle(for: FoodCompositionBundleToken.self)]
            + Bundle.allFrameworks
        for bundle in bundles {
            guard let url = bundle.url(
                forResource: "mext_food_composition_2023",
                withExtension: "json"
            ), let data = try? Data(contentsOf: url),
               let catalog = try? JSONDecoder().decode(FoodCompositionCatalog.self, from: data) else {
                continue
            }
            return catalog
        }
        AppDiagnostics.shared.record(
            category: "food.database",
            message: "Bundled MEXT food composition database could not be loaded"
        )
        return FoodCompositionCatalog(
            sourceName: "日本食品標準成分表（八訂）増補2023年",
            sourceURL: "https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html",
            correctionDate: "2026-03-27",
            basis: "可食部100g当たり",
            attribution: "日本食品標準成分表（八訂）増補2023年から引用",
            items: []
        )
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: #"[\[\]［］〈〉＜＞（）()]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private final class FoodCompositionBundleToken: NSObject {}

struct MealCompositionItem: Codable, Hashable, Identifiable {
    var id: UUID
    var sourceID: String
    var sourceKind: MealNutritionSource
    var name: String
    var amountGrams: Double
    var nutritionPer100Grams: NutritionAmount
    var unavailableNutrients: [FoodCompositionNutrient]?
    var traceNutrients: [FoodCompositionNutrient]?

    init(
        id: UUID = UUID(),
        sourceID: String,
        sourceKind: MealNutritionSource,
        name: String,
        amountGrams: Double,
        nutritionPer100Grams: NutritionAmount,
        unavailableNutrients: [FoodCompositionNutrient] = [],
        traceNutrients: [FoodCompositionNutrient] = []
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.name = name
        self.amountGrams = max(0, amountGrams)
        self.nutritionPer100Grams = nutritionPer100Grams
        self.unavailableNutrients = unavailableNutrients
        self.traceNutrients = traceNutrients
    }

    init(food: FoodCompositionItem, amountGrams: Double = 100) {
        self.init(
            sourceID: food.id,
            sourceKind: .mext,
            name: food.name,
            amountGrams: amountGrams,
            nutritionPer100Grams: food.nutritionPer100Grams,
            unavailableNutrients: food.unavailableNutrients,
            traceNutrients: food.traceNutrients
        )
    }

    var nutrition: NutritionAmount {
        nutritionPer100Grams.scaled(by: amountGrams / 100)
    }

    var displayText: String {
        "\(name) \(amountGrams.formatted(.number.precision(.fractionLength(0...1))))g"
    }

    var dataQualityNote: String? {
        if let unavailableNutrients, !unavailableNutrients.isEmpty {
            return "未測定のため合計に含まれない項目: \(unavailableNutrients.map(\.displayName).joined(separator: "・"))"
        }
        if let traceNutrients, !traceNutrients.isEmpty {
            return "微量を0として概算: \(traceNutrients.map(\.displayName).joined(separator: "・"))"
        }
        return nil
    }
}

enum MealNutritionSource: String, Codable, Hashable {
    case mext
    case barcode
}

struct MealNutritionResolution: Equatable {
    var draft: MealAIDraft
    var matchedCount: Int
    var unresolvedItemNames: [String]
}

struct MealNutritionResolver {
    let database: FoodCompositionDatabase

    init(database: FoodCompositionDatabase = .shared) {
        self.database = database
    }

    func resolve(_ sourceDraft: MealAIDraft) -> MealNutritionResolution {
        guard !sourceDraft.items.isEmpty else {
            return MealNutritionResolution(
                draft: sourceDraft,
                matchedCount: 0,
                unresolvedItemNames: []
            )
        }

        var resolvedItems: [MealAIDraftItem] = []
        var unresolvedNames: [String] = []
        var matchedCount = 0

        for var item in sourceDraft.items {
            guard let amountGrams = Self.grams(from: item.amount),
                  let food = database.conservativeMatch(for: item.name),
                  food.unavailableNutrients.isEmpty else {
                unresolvedNames.append(item.name)
                resolvedItems.append(item)
                continue
            }

            let nutrition = MealCompositionItem(food: food, amountGrams: amountGrams).nutrition
            item.calories = nutrition.calories
            item.protein = nutrition.protein
            item.fat = nutrition.fat
            item.carbs = nutrition.carbs
            item.nutritionSource = .mext
            item.sourceID = food.id
            resolvedItems.append(item)
            matchedCount += 1
        }

        var draft = sourceDraft
        draft.items = resolvedItems
        draft = draft.reconciledFromItems()
        if matchedCount > 0 {
            let note = unresolvedNames.isEmpty
                ? "全食品の栄養値を日本食品標準成分表から再計算しました。"
                : "\(matchedCount)品の栄養値を日本食品標準成分表から再計算しました。未照合の食品はAI参考値です。"
            draft.comment = draft.comment.isEmpty ? note : "\(draft.comment)\n\(note)"
        }

        return MealNutritionResolution(
            draft: draft,
            matchedCount: matchedCount,
            unresolvedItemNames: unresolvedNames
        )
    }

    static func grams(from amount: String) -> Double? {
        let normalized = amount
            .folding(options: [.widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(kg|g)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let valueRange = Range(match.range(at: 1), in: normalized),
              let unitRange = Range(match.range(at: 2), in: normalized),
              let value = Double(normalized[valueRange]) else {
            return nil
        }
        return normalized[unitRange] == "kg" ? value * 1_000 : value
    }
}

struct BarcodeFoodProduct: Codable, Hashable, Identifiable {
    var code: String
    var name: String
    var basisAmountGrams: Double
    var nutritionPerBasis: NutritionAmount
    var sourceDescription: String?
    var sourceUpdatedAt: Date?

    var id: String { code }

    init(
        code: String,
        name: String,
        basisAmountGrams: Double,
        nutritionPerBasis: NutritionAmount,
        sourceDescription: String? = nil,
        sourceUpdatedAt: Date? = nil
    ) {
        self.code = code
        self.name = name
        self.basisAmountGrams = max(0.1, basisAmountGrams)
        self.nutritionPerBasis = nutritionPerBasis
        self.sourceDescription = sourceDescription
        self.sourceUpdatedAt = sourceUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        basisAmountGrams = max(
            0.1,
            try container.decodeIfPresent(Double.self, forKey: .basisAmountGrams) ?? 100
        )
        nutritionPerBasis = try container.decodeIfPresent(
            NutritionAmount.self,
            forKey: .nutritionPerBasis
        ) ?? container.decodeIfPresent(
            NutritionAmount.self,
            forKey: .legacyNutritionPer100Grams
        ) ?? .zero
        sourceDescription = try container.decodeIfPresent(String.self, forKey: .sourceDescription)
        sourceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encode(basisAmountGrams, forKey: .basisAmountGrams)
        try container.encode(nutritionPerBasis, forKey: .nutritionPerBasis)
        try container.encodeIfPresent(sourceDescription, forKey: .sourceDescription)
        try container.encodeIfPresent(sourceUpdatedAt, forKey: .sourceUpdatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case name
        case basisAmountGrams
        case nutritionPerBasis
        case legacyNutritionPer100Grams = "nutritionPer100Grams"
        case sourceDescription
        case sourceUpdatedAt
    }

    var nutritionPer100Grams: NutritionAmount {
        guard basisAmountGrams > 0 else { return .zero }
        return nutritionPerBasis.scaled(by: 100 / basisAmountGrams)
    }

    func mealItem(amountGrams: Double) -> MealCompositionItem {
        MealCompositionItem(
            sourceID: code,
            sourceKind: .barcode,
            name: name,
            amountGrams: amountGrams,
            nutritionPer100Grams: nutritionPer100Grams
        )
    }
}

struct BarcodeFoodProductStore: Sendable {
    static let storageKey = "gym.training.food.barcodeProducts"
    private let dataStore: ProtectedDataStore

    init(dataStore: ProtectedDataStore = .shared) {
        self.dataStore = dataStore
    }

    func product(for code: String) -> BarcodeFoodProduct? {
        products().first { $0.code == Self.normalizedCode(code) }
    }

    func save(_ product: BarcodeFoodProduct) throws {
        var values = products()
        let normalized = BarcodeFoodProduct(
            code: Self.normalizedCode(product.code),
            name: product.name.trimmingCharacters(in: .whitespacesAndNewlines),
            basisAmountGrams: max(0.1, product.basisAmountGrams),
            nutritionPerBasis: product.nutritionPerBasis,
            sourceDescription: product.sourceDescription,
            sourceUpdatedAt: product.sourceUpdatedAt
        )
        values.removeAll { $0.code == normalized.code }
        values.append(normalized)
        try dataStore.set(try JSONEncoder().encode(values), forKey: Self.storageKey)
    }

    func products() -> [BarcodeFoodProduct] {
        guard let data = dataStore.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([BarcodeFoodProduct].self, from: data)) ?? []
    }

    private static func normalizedCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }
}

struct DailyMealSuggestion: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var rationale: String
}

struct DailyMealSuggestionEngine {
    func suggestions(
        progress: DailyNutritionProgress,
        goalType: GoalType,
        limit: Int = 3
    ) -> [DailyMealSuggestion] {
        let calorieRemaining = max(0, progress.goals.calories - progress.calories)
        let proteinRemaining = max(0, progress.goals.protein - progress.protein)
        let fatOver = max(0, progress.fat - progress.goals.fat)
        var result: [DailyMealSuggestion] = []

        if proteinRemaining >= 20 {
            result.append(
                DailyMealSuggestion(
                    title: "高たんぱくの一品",
                    detail: fatOver > 0 ? "鶏むね肉、白身魚、無脂肪ヨーグルト" : "魚、卵、鶏肉、豆腐から選ぶ",
                    rationale: "たんぱく質があと約\(Int(proteinRemaining.rounded()))gです"
                )
            )
        }

        if fatOver > 0 {
            result.append(
                DailyMealSuggestion(
                    title: "脂質を控えめに",
                    detail: "揚げ物より、焼く・蒸す・茹でる料理",
                    rationale: "脂質が目標を約\(Int(fatOver.rounded()))g上回っています"
                )
            )
        } else if calorieRemaining >= 300 {
            let detail = goalType == .muscleGain
                ? "ごはんとたんぱく源を組み合わせる"
                : "主食・主菜・野菜を小さめに組み合わせる"
            result.append(
                DailyMealSuggestion(
                    title: "残りの食事目安",
                    detail: detail,
                    rationale: "摂取目安まで約\(Int(calorieRemaining.rounded()))kcalです"
                )
            )
        }

        if !progress.isMealCountAchieved {
            result.append(
                DailyMealSuggestion(
                    title: "次の記録",
                    detail: "食べたら写真か食品DBですぐ記録",
                    rationale: "今日の記録は\(progress.mealCount)/\(progress.goals.mealCount)回です"
                )
            )
        }

        if result.isEmpty {
            result.append(
                DailyMealSuggestion(
                    title: "今のペースを維持",
                    detail: "空腹と体調を見ながら無理なく続ける",
                    rationale: "今日の栄養目安に近づいています"
                )
            )
        }
        return Array(result.prefix(max(1, limit)))
    }
}
