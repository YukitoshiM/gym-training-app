import XCTest
@testable import GymTrainingApp

final class FoodCompositionTests: XCTestCase {
    func testBundledMEXTDatabaseContainsCurrentCorrectedCatalog() throws {
        let database = FoodCompositionDatabase.shared

        XCTAssertGreaterThanOrEqual(database.catalog.items.count, 2_500)
        XCTAssertEqual(database.catalog.correctionDate, "2026-03-27")
        XCTAssertTrue(database.catalog.sourceName.contains("増補2023年"))

        let rice = try XCTUnwrap(database.catalog.items.first { $0.id == "01088" })
        XCTAssertEqual(rice.calories, 156, accuracy: 0.01)
        XCTAssertEqual(rice.protein, 2.5, accuracy: 0.01)
        XCTAssertEqual(rice.fat, 0.3, accuracy: 0.01)
        XCTAssertEqual(rice.carbs, 37.1, accuracy: 0.01)

        let broth = try XCTUnwrap(database.catalog.items.first { $0.id == "09059" })
        XCTAssertEqual(Set(broth.unavailableNutrients), Set([.protein, .fat]))
        XCTAssertTrue(broth.dataQualityNote?.contains("未測定") == true)
    }

    func testFoodSearchAndAmountCalculationAreDeterministic() throws {
        let database = FoodCompositionDatabase.shared
        let rice = try XCTUnwrap(database.search("水稲めし 精白米 うるち米").first)
        let item = MealCompositionItem(food: rice, amountGrams: 150)

        XCTAssertEqual(item.nutrition.calories, 234, accuracy: 0.01)
        XCTAssertEqual(item.nutrition.protein, 3.75, accuracy: 0.01)
        XCTAssertEqual(item.nutrition.carbs, 55.65, accuracy: 0.01)
    }

    func testBarcodeBasisAmountConvertsToPer100AndActualAmount() throws {
        let product = BarcodeFoodProduct(
            code: "4900000000000",
            name: "テスト食品",
            basisAmountGrams: 50,
            nutritionPerBasis: NutritionAmount(calories: 120, protein: 5, fat: 3, carbs: 18)
        )
        let consumed = product.mealItem(amountGrams: 75).nutrition

        XCTAssertEqual(product.nutritionPer100Grams.calories, 240, accuracy: 0.01)
        XCTAssertEqual(consumed.calories, 180, accuracy: 0.01)
        XCTAssertEqual(consumed.protein, 7.5, accuracy: 0.01)
    }

    func testLegacyMealDecodesWithoutCompositionItems() throws {
        let data = Data(#"{"name":"旧食事","foodItems":["白ごはん"]}"#.utf8)
        let meal = try JSONDecoder().decode(MealEntry.self, from: data)

        XCTAssertEqual(meal.name, "旧食事")
        XCTAssertTrue(meal.compositionItems.isEmpty)
    }

    func testDailyMealSuggestionExplainsProteinShortfall() throws {
        let progress = DailyNutritionProgress(
            meals: [MealEntry(name: "朝食", calories: 500, protein: 20, fat: 10, carbs: 60)],
            goals: NutritionGoals(calories: 2_000, protein: 120, fat: 60, carbs: 250, mealCount: 3)
        )
        let suggestions = DailyMealSuggestionEngine().suggestions(
            progress: progress,
            goalType: .muscleGain
        )

        XCTAssertEqual(suggestions.first?.title, "高たんぱくの一品")
        XCTAssertTrue(suggestions.first?.rationale.contains("100g") == true)
        XCTAssertLessThanOrEqual(suggestions.count, 3)
    }

    func testAIDraftUsesMEXTNutritionOnlyForConservativeMatches() throws {
        let draft = MealAIDraft(
            mealName: "昼食",
            calories: 1,
            protein: 1,
            fat: 1,
            carbs: 1,
            confidence: "medium",
            comment: "AI推定",
            items: [
                MealAIDraftItem(
                    name: "白ごはん",
                    amount: "150g",
                    calories: 999,
                    protein: 999,
                    fat: 999,
                    carbs: 999
                ),
                MealAIDraftItem(
                    name: "具だくさんスープ",
                    amount: "1杯",
                    calories: 80,
                    protein: 4,
                    fat: 2,
                    carbs: 10
                ),
            ]
        )

        let resolution = MealNutritionResolver().resolve(draft)
        let rice = try XCTUnwrap(resolution.draft.items.first)

        XCTAssertEqual(resolution.matchedCount, 1)
        XCTAssertEqual(resolution.unresolvedItemNames, ["具だくさんスープ"])
        XCTAssertEqual(rice.nutritionSource, .mext)
        XCTAssertEqual(rice.sourceID, "01088")
        XCTAssertEqual(rice.calories, 234, accuracy: 0.01)
        XCTAssertEqual(resolution.draft.calories, 314, accuracy: 0.01)
        XCTAssertTrue(resolution.draft.comment.contains("未照合"))
    }

    func testNutritionResolverParsesGramsAndKilograms() {
        XCTAssertEqual(MealNutritionResolver.grams(from: "150g"), 150)
        XCTAssertEqual(MealNutritionResolver.grams(from: "０．２ kg"), 200)
        XCTAssertNil(MealNutritionResolver.grams(from: "1杯"))
    }

    func testNormalPFCFormattingUsesWholeGramsWhileDetailKeepsPrecision() {
        XCTAssertEqual(AppFormatters.grams(12.6), "13g")
        XCTAssertEqual(AppFormatters.preciseGrams(12.6), "12.6g")
    }

    func testNutritionLabelOCRParserExtractsJapanesePFC() throws {
        let draft = try NutritionLabelReader.parse(
            "栄養成分表示 100g当たり エネルギー 242kcal たんぱく質 12.6g 脂質 8.4g 炭水化物 29.1g"
        )

        XCTAssertEqual(draft.basisAmountGrams, 100)
        XCTAssertEqual(draft.calories, 242)
        XCTAssertEqual(draft.protein, 12.6)
        XCTAssertEqual(draft.fat, 8.4)
        XCTAssertEqual(draft.carbs, 29.1)
    }

    func testNutritionLabelOCRParserRejectsUnrelatedText() {
        XCTAssertThrowsError(try NutritionLabelReader.parse("商品名 おいしい食品 内容量 100g"))
    }

    func testBarcodeProductPreservesNutritionLabelProvenance() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_786_680_000)
        let product = BarcodeFoodProduct(
            code: "4900000000000",
            name: "テスト食品",
            basisAmountGrams: 100,
            nutritionPerBasis: NutritionAmount(calories: 242, protein: 12.6, fat: 8.4, carbs: 29.1),
            sourceDescription: "栄養成分表示OCR（ユーザー確認）",
            sourceUpdatedAt: confirmedAt
        )

        let decoded = try JSONDecoder().decode(
            BarcodeFoodProduct.self,
            from: JSONEncoder().encode(product)
        )

        XCTAssertEqual(decoded.sourceDescription, product.sourceDescription)
        XCTAssertEqual(decoded.sourceUpdatedAt, confirmedAt)
    }
}
