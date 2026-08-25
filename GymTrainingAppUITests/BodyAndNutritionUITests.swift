import XCTest

@MainActor
final class BodyAndNutritionUITests: GymTrainingAppUITestCase {
    func testBodyMetricFlow() throws {
        openBodyMetricDetail()
        setBodyMetricGoal()
        addBodyMetricEntry()
        verifyBodyMetricSummary()
        verifyPreviousBodyMetricPrefillsNextEntry()
    }

    func testGoalModeSelection() throws {
        tapTab("ホーム")

        let goalCard = scrollToHittable(app.buttons["goalActionCard"])
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["体型改善"].exists)

        goalCard.tap()

        let dietOption = app.buttons["goalOption-diet"]
        XCTAssertTrue(dietOption.waitForExistence(timeout: 5))
        dietOption.tap()

        XCTAssertTrue(app.staticTexts["ダイエット"].waitForExistence(timeout: 5))
    }

    func testManualMealAndBodyPhotoLogFlow() throws {
        addManualMealEntry()
        addBodyPhotoMemoEntry()
        verifyDailyJournalForManualLogs()
    }

    func testMealTemplatePrefillsNextMealFoodList() throws {
        tapTab("記録")
        let mealLink = scrollToHittable(app.buttons["recordHubMealLink"])
        XCTAssertTrue(mealLink.isHittable)
        mealLink.tap()

        let template = scrollToHittable(
            app.descendants(matching: .any)["dailyMealSuggestion-breakfast"]
        )
        XCTAssertTrue(template.isHittable)
        template.tap()

        XCTAssertTrue(app.navigationBars["食事を記録"].waitForExistence(timeout: 5))
        let foodFields = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "mealFoodItemField-")
        )
        XCTAssertEqual(foodFields.count, 4)
        XCTAssertEqual(foodFields.element(boundBy: 0).value as? String, "無糖ヨーグルト 150g")
        let nameField = scrollToHittable(app.textFields["mealNameField"])
        XCTAssertTrue(nameField.exists)
        XCTAssertEqual(nameField.value as? String, "軽く整える朝食")
    }

    func testBodyPhotoSetCanBeReopenedForLaterAdditions() throws {
        addBodyPhotoMemoEntry()

        let row = app.buttons["bodyPhotoRow-front"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["bodyPhotoMeasurementContext"]
                .waitForExistence(timeout: 5)
        )
        let editButton = app.buttons["editBodyPhotoSetButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(app.navigationBars["撮影セットを編集"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bodyPhotoPicker"].exists)
        XCTAssertTrue(app.buttons["bodyPhotoPicker-side"].exists)
        XCTAssertTrue(app.buttons["bodyPhotoPicker-back"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Body photo set editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPreviousMealNutritionPrefillsSameMealType() throws {
        addManualMealEntry()

        let addMealButton = app.buttons["addMealButton"]
        XCTAssertTrue(addMealButton.waitForExistence(timeout: 5))
        addMealButton.tap()

        assertMealField("mealProteinField", equals: "31")
        assertMealField("mealFatField", equals: "20")
        assertMealField("mealCarbsField", equals: "52")
        assertMealField("mealCaloriesField", equals: "512")
    }

    func testSavedMealCanBeEditedWithoutCreatingDuplicate() throws {
        addManualMealEntry()

        let savedMeal = app.buttons["mealRow-鶏むね肉定食"]
        XCTAssertTrue(savedMeal.waitForExistence(timeout: 5))
        savedMeal.tap()

        XCTAssertTrue(app.navigationBars["食事を編集"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mealCameraButton"].exists)
        XCTAssertTrue(app.buttons["mealPhotoPicker"].exists)
        XCTAssertEqual(scrollToHittable(app.textFields["mealProteinField"]).value as? String, "31")
        XCTAssertEqual(scrollToHittable(app.textFields["mealCaloriesField"]).value as? String, "512")

        let nameField = app.textFields["mealNameField"]
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        nameField.typeText("鶏むね肉と玄米")
        XCTAssertEqual(nameField.value as? String, "鶏むね肉と玄米")
        app.buttons["saveMealButton"].tap()

        XCTAssertTrue(app.buttons["mealRow-鶏むね肉と玄米"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "mealRow-")
        ).count, 1)
        XCTAssertFalse(app.buttons["mealRow-鶏むね肉定食"].exists)
    }

    func testMealPhotoAutoEstimateWithDeterministicAIStub() throws {
        app.terminate()
        app.launchArguments.append("--stub-meal-ai")
        app.launch()

        tapTab("記録")

        let mealLink = app.buttons["recordHubMealLink"]
        XCTAssertTrue(mealLink.waitForExistence(timeout: 5))
        mealLink.tap()

        let addButton = app.buttons["addMealButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let photoPicker = app.buttons["mealPhotoPicker"]
        XCTAssertTrue(photoPicker.waitForExistence(timeout: 5))
        photoPicker.tap()

        let nameField = app.textFields["mealNameField"]
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let value = nameField.value as? String ?? ""
            if !value.isEmpty, value != "食事名" {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        let populatedCaloriesField = scrollToHittable(app.textFields["mealCaloriesField"])
        XCTAssertTrue(populatedCaloriesField.waitForExistence(timeout: 5))
        XCTAssertEqual(populatedCaloriesField.value as? String, "483")
        XCTAssertFalse((app.textFields["mealNameField"].value as? String ?? "").isEmpty)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "meal-photo-auto-estimate"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMealFoodListAutoEstimateWithDeterministicAIStub() throws {
        app.terminate()
        app.launchArguments.append("--stub-meal-text-ai")
        app.launch()

        tapTab("記録")

        let mealLink = app.buttons["recordHubMealLink"]
        XCTAssertTrue(mealLink.waitForExistence(timeout: 5))
        mealLink.tap()

        let addButton = app.buttons["addMealButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let inputPicker = app.segmentedControls["mealInputModePicker"]
        XCTAssertTrue(inputPicker.waitForExistence(timeout: 5))
        inputPicker.buttons["食べたもの"].tap()

        let foodField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "mealFoodItemField-")
        ).firstMatch
        XCTAssertTrue(foodField.waitForExistence(timeout: 5))
        foodField.tap()
        foodField.typeText("白ごはん 150g")
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists {
            returnKey.tap()
        }

        let analyzeButton = app.buttons["analyzeMealTextButton"]
        XCTAssertTrue(analyzeButton.waitForExistence(timeout: 5))
        analyzeButton.tap()

        let populatedName = NSPredicate(
            format: "value == %@",
            "白ごはん・鶏むね肉・味噌汁"
        )
        expectation(for: populatedName, evaluatedWith: app.textFields["mealNameField"])
        waitForExpectations(timeout: 10)

        let caloriesField = scrollToHittable(app.textFields["mealCaloriesField"])
        XCTAssertTrue(caloriesField.waitForExistence(timeout: 5))
        XCTAssertEqual(caloriesField.value as? String, "427")
        XCTAssertEqual(
            app.textFields["mealNameField"].value as? String,
            "白ごはん・鶏むね肉・味噌汁"
        )
        let firstDraftItem = scrollToHittable(app.staticTexts["白ごはん"])
        XCTAssertTrue(firstDraftItem.exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "meal-food-list-auto-estimate"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMEXTFoodDatabaseSearchAndAmountCalculation() throws {
        tapTab("記録")
        app.buttons["recordHubMealLink"].tap()
        app.buttons["addMealButton"].tap()
        app.segmentedControls["mealInputModePicker"].buttons["食べたもの"].tap()

        let databaseButton = scrollToHittable(app.buttons["openFoodDatabaseButton"])
        XCTAssertTrue(databaseButton.isHittable)
        databaseButton.tap()

        let searchField = app.textFields["foodDatabaseSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("水稲めし 精白米 うるち米")

        let rice = app.buttons["foodDatabaseResult-01088"]
        XCTAssertTrue(rice.waitForExistence(timeout: 5))
        rice.tap()
        XCTAssertTrue(app.navigationBars["食品DB"].waitForNonExistence(timeout: 5))

        let amount = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "compositionAmount-")
        ).firstMatch
        let visibleAmount = scrollToHittable(amount)
        XCTAssertTrue(visibleAmount.exists)
        replaceNumericText(in: visibleAmount, with: "150")
        XCTAssertEqual(visibleAmount.value as? String, "150")

        XCTAssertTrue(scrollToHittable(app.staticTexts["食品から自動集計"]).exists)
        let caloriesField = scrollToHittable(app.textFields["mealCaloriesField"])
        XCTAssertEqual(caloriesField.value as? String, "234")
        XCTAssertEqual(app.textFields["mealNameField"].value as? String, "こめ ［水稲めし］ 精白米 うるち米")
    }

    func testUnknownBarcodeCanBeEnteredAndReusedLocally() throws {
        tapTab("記録")
        app.buttons["recordHubMealLink"].tap()
        app.buttons["addMealButton"].tap()
        app.segmentedControls["mealInputModePicker"].buttons["食べたもの"].tap()
        scrollToHittable(app.buttons["openBarcodeFoodButton"]).tap()

        replaceText(in: app.textFields["barcodeManualField"], with: "4900000000000")
        replaceText(in: app.textFields["barcodeProductNameField"], with: "テスト食品")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeBasisAmountField"]), with: "50")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeAmountField"]), with: "75")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeCaloriesField"]), with: "120")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeProteinField"]), with: "5")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeFatField"]), with: "3")
        replaceNumericText(in: scrollToHittable(app.textFields["barcodeCarbsField"]), with: "18")
        app.buttons["addBarcodeFoodButton"].tap()

        let caloriesField = scrollToHittable(app.textFields["mealCaloriesField"])
        XCTAssertEqual(caloriesField.value as? String, "180")
        XCTAssertEqual(app.textFields["mealNameField"].value as? String, "テスト食品")
    }

    private func assertMealField(_ identifier: String, equals expectedValue: String) {
        let field = scrollToHittable(app.textFields[identifier])
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing meal field: \(identifier)")
        XCTAssertEqual(field.value as? String, expectedValue)
    }

}
