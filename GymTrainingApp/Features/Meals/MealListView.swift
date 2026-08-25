import AVFoundation
import PhotosUI
import SwiftUI

struct MealListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var editorRequest: MealEditorRequest?

    init(startsWithEditor: Bool = false) {
        _editorRequest = State(initialValue: startsWithEditor ? .new : nil)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        MetricPill(title: L10n.string("health_meals_body_ai.8167b76a03f0", fallback: "今日の食事"), value: "\(appStore.mealEntries().count)", systemImage: "fork.knife", tint: AppTheme.orange)
                        MetricPill(title: L10n.string("health_meals_body_ai.4480ba8fa2eb", fallback: "摂取 kcal"), value: AppFormatters.calories(todayCalories), systemImage: "flame", tint: AppTheme.accent)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    NutritionGoalCard(progress: nutritionProgress)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    DailyMealSuggestionsCard(
                        suggestions: DailyMealSuggestionEngine().suggestions(
                            progress: nutritionProgress,
                            goalType: appStore.userProfile.goalType
                        ),
                        coachPersona: appStore.userProfile.coachPersona,
                        selectSuggestion: { suggestion in
                            editorRequest = .template(suggestion)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section(L10n.string("health_meals_body_ai.88346340fae8", fallback: "記録")) {
                    if appStore.mealEntries.isEmpty {
                        Text(L10n.string("health_meals_body_ai.b18007a5bc56", fallback: "食事記録はまだありません"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(appStore.mealEntries) { meal in
                        Button {
                            editorRequest = MealEditorRequest(meal: meal)
                        } label: {
                            MealRow(
                                meal: meal,
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("health_meals_body_ai.763b6c839189", fallback: "{{value1}}を編集", values: [String(describing: meal.name)]))
                        .accessibilityIdentifier("mealRow-\(meal.name)")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: appStore.deleteMealEntries)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TrainingBackground())
            .navigationTitle(L10n.string("health_meals_body_ai.738844ab541c", fallback: "食事"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRequest = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.string("health_meals_body_ai.e1790b48822b", fallback: "食事を追加"))
                    .accessibilityIdentifier("addMealButton")
                }
            }
            .sheet(item: $editorRequest) { request in
                MealEditorView(existingMeal: request.meal, initialMeal: request.initialMeal) {
                    editorRequest = nil
                }
            }
        }
    }

    private var todayCalories: Double {
        appStore.mealEntries().reduce(0) { $0 + $1.calories }
    }

    private var nutritionProgress: DailyNutritionProgress {
        DailyNutritionProgress(
            meals: appStore.mealEntries(),
            goals: appStore.userProfile.nutritionGoals
        )
    }
}

private struct DailyMealSuggestionsCard: View {
    let suggestions: [DailyMealSuggestion]
    let coachPersona: CoachPersona
    let selectSuggestion: (DailyMealSuggestion) -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CoachAttributionLabel(
                    persona: coachPersona,
                    text: L10n.string("health_meals_body_ai.0e38f949ffe5", fallback: "今日の食事候補"),
                    avatarSize: 30
                )
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "fork.knife.circle.fill")
                                .foregroundStyle(AppTheme.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.subheadline.bold())
                                Text(suggestion.detail)
                                    .font(.subheadline)
                                Text(suggestion.rationale)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer(minLength: 8)
                            if suggestion.canStartEntry {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!suggestion.canStartEntry)
                    .accessibilityIdentifier("dailyMealSuggestion-\(suggestion.mealType?.rawValue ?? "info")")
                }
            }
        }
    }
}

private struct MealEditorRequest: Identifiable {
    let id: UUID
    let meal: MealEntry?
    let initialMeal: MealEntry?

    static var new: MealEditorRequest {
        MealEditorRequest(id: UUID(), meal: nil, initialMeal: nil)
    }

    static func template(_ suggestion: DailyMealSuggestion) -> MealEditorRequest {
        MealEditorRequest(
            id: UUID(),
            meal: nil,
            initialMeal: MealEntry(
                mealType: suggestion.mealType ?? .snack,
                name: suggestion.title,
                foodItems: suggestion.foodItems
            )
        )
    }

    init(id: UUID = UUID(), meal: MealEntry?) {
        self.id = id
        self.meal = meal
        initialMeal = nil
    }

    private init(id: UUID, meal: MealEntry?, initialMeal: MealEntry?) {
        self.id = id
        self.meal = meal
        self.initialMeal = initialMeal
    }
}

private struct NutritionGoalCard: View {
    let progress: DailyNutritionProgress

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("health_meals_body_ai.bca43a6ff7b0", fallback: "今日の食事目標"))
                            .font(.headline)
                        Text(L10n.string("health_meals_body_ai.985a2101ab82", fallback: "回数と栄養を別々に判定"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    Spacer()
                    statusBadge(
                        title: nutritionStatusTitle,
                        isCompleted: progress.isNutritionAchieved
                    )
                }

                HStack(spacing: 8) {
                    nutritionProgress(title: "kcal", value: progress.calories, goal: progress.goals.calories, rate: progress.calorieProgress)
                    nutritionProgress(title: "P", value: progress.protein, goal: progress.goals.protein, rate: progress.proteinProgress)
                    nutritionProgress(title: "F", value: progress.fat, goal: progress.goals.fat, rate: progress.fatProgress)
                    nutritionProgress(title: "C", value: progress.carbs, goal: progress.goals.carbs, rate: progress.carbsProgress)
                }

                Label(
                    L10n.string("health_meals_body_ai.6a0da3609e1e", fallback: "{{value1}}/{{value2}}回", values: [String(describing: progress.mealCount), String(describing: progress.goals.mealCount)]),
                    systemImage: progress.isMealCountAchieved ? "checkmark.circle.fill" : "fork.knife"
                )
                .font(.footnote.bold())
                .foregroundStyle(progress.isMealCountAchieved ? AppTheme.positive : AppTheme.mutedInk)
            }
        }
        .accessibilityIdentifier("nutritionGoalCard")
    }

    private var nutritionStatusTitle: String {
        if progress.isCalorieAchieved, progress.isPFCAchieved {
            return L10n.string("health_meals_body_ai.72f5049fd184", fallback: "kcal・PFC達成")
        }
        if progress.isCalorieAchieved {
            return L10n.string("health_meals_body_ai.44a5b22247ad", fallback: "kcal達成")
        }
        if progress.isPFCAchieved {
            return L10n.string("health_meals_body_ai.01862aa03144", fallback: "PFC達成")
        }
        return L10n.string("health_meals_body_ai.dfccb419b22f", fallback: "栄養途中")
    }

    private func nutritionProgress(
        title: String,
        value: Double,
        goal: Double,
        rate: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.mutedInk)
            ProgressView(value: rate)
                .tint(rate >= 0.9 ? AppTheme.positive : AppTheme.accent)
            Text("\(Int(value.rounded()))/\(Int(goal.rounded()))")
                .font(.footnote)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(title: String, isCompleted: Bool) -> some View {
        Text(title)
            .font(.footnote.bold())
            .foregroundStyle(isCompleted ? AppTheme.positive : AppTheme.mutedInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                (isCompleted ? AppTheme.positive : AppTheme.mutedInk).opacity(0.12),
                in: Capsule()
            )
    }
}

private struct MealRow: View {
    let meal: MealEntry
    let coachPersona: CoachPersona

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                MealThumbnail(imageData: meal.imageData)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(meal.name)
                            .font(.headline)
                        Spacer()
                        Text(meal.mealType.displayName)
                            .font(.footnote.bold())
                            .foregroundStyle(AppTheme.orange)
                    }

                    Text(AppFormatters.shortDate.string(from: meal.recordedAt))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    HStack(spacing: 8) {
                        Text(AppFormatters.calories(meal.calories))
                        Text("P \(AppFormatters.grams(meal.protein))")
                        Text("F \(AppFormatters.grams(meal.fat))")
                        Text("C \(AppFormatters.grams(meal.carbs))")
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)

                    if let aiDraft = meal.aiDraft {
                        CoachAttributionLabel(
                            persona: coachPersona,
                            text: L10n.string("health_meals_body_ai.6bf0f1539402", fallback: "{{value1}}の下書き・{{value2}}", values: [String(describing: coachPersona.displayName), String(describing: aiDraft.confidence)]),
                            avatarSize: 24
                        )
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct MealThumbnail: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(AppTheme.orange)
            }
        }
        .frame(width: 54, height: 54)
        .background(AppTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private enum MealInputMode: String, CaseIterable, Identifiable {
    case photo
    case foodList

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: L10n.string("health_meals_body_ai.595af419ef23", fallback: "写真")
        case .foodList: L10n.string("health_meals_body_ai.4023d26ef616", fallback: "食べたもの")
        }
    }
}

private struct MealFoodInput: Identifiable {
    let id = UUID()
    var text = ""
}

private struct MealEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let existingMeal: MealEntry?
    let onSave: () -> Void

    @State private var mealType: MealType
    @State private var recordedAt: Date
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @State private var memo: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var aiDraft: MealAIDraft?
    @State private var isAnalyzing = false
    @State private var aiErrorMessage: String?
    @State private var aiErrorRecovery: String?
    @State private var creditAccessIssue: AICreditAccessIssue?
    @State private var calculatesCaloriesFromPFC: Bool
    @State private var inputMode: MealInputMode
    @State private var foodInputs: [MealFoodInput]
    @State private var compositionItems: [MealCompositionItem]
    @State private var isShowingCamera = false
    @State private var isShowingCameraPermissionAlert = false
    @State private var isShowingFoodDatabase = false
    @State private var isShowingBarcode = false

    init(
        existingMeal: MealEntry? = nil,
        initialMeal: MealEntry? = nil,
        onSave: @escaping () -> Void
    ) {
        self.existingMeal = existingMeal
        self.onSave = onSave

        let seedMeal = existingMeal ?? initialMeal
        let protein = seedMeal?.protein ?? 0
        let fat = seedMeal?.fat ?? 0
        let carbs = seedMeal?.carbs ?? 0
        let pfcCalories = protein * 4 + fat * 9 + carbs * 4
        let storedCalories = seedMeal?.calories ?? 0
        let foodItems = seedMeal?.foodItems ?? []

        _mealType = State(initialValue: seedMeal?.mealType ?? .lunch)
        _recordedAt = State(initialValue: RecordDatePolicy.normalizedDay(seedMeal?.recordedAt ?? Date()))
        _name = State(initialValue: seedMeal?.name ?? "")
        _calories = State(initialValue: seedMeal.map {
            $0.calories.formatted(.number.precision(.fractionLength(0)))
        } ?? "")
        _protein = State(initialValue: seedMeal.map {
            $0.protein.formatted(.number.precision(.fractionLength(0)))
        } ?? "")
        _fat = State(initialValue: seedMeal.map {
            $0.fat.formatted(.number.precision(.fractionLength(0)))
        } ?? "")
        _carbs = State(initialValue: seedMeal.map {
            $0.carbs.formatted(.number.precision(.fractionLength(0)))
        } ?? "")
        _memo = State(initialValue: seedMeal?.memo ?? "")
        _imageData = State(initialValue: seedMeal?.imageData)
        _aiDraft = State(initialValue: seedMeal?.aiDraft)
        _calculatesCaloriesFromPFC = State(
            initialValue: seedMeal == nil || abs(storedCalories - pfcCalories) < 1
        )
        _inputMode = State(
            initialValue: (!foodItems.isEmpty || !(seedMeal?.compositionItems.isEmpty ?? true))
                && seedMeal?.imageData == nil ? .foodList : .photo
        )
        _foodInputs = State(
            initialValue: foodItems.isEmpty
                ? [MealFoodInput()]
                : foodItems.map { MealFoodInput(text: $0) }
        )
        _compositionItems = State(initialValue: seedMeal?.compositionItems ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("health_meals_body_ai.b76e2c70647b", fallback: "入力方法")) {
                    CoachIdentityView(
                        persona: appStore.userProfile.coachPersona,
                        role: L10n.string("health_meals_body_ai.d15616c39ec5", fallback: "食事チェック"),
                        detail: L10n.string("health_meals_body_ai.f592bc420a69", fallback: "写真や食べたものから栄養の下書きを作ります。"),
                        avatarSize: 48
                    )
                    .accessibilityIdentifier("mealAICoachIdentity")

                    AICreditCostStatusView(feature: "meal", settings: appStore.aiSettings)

                    Picker(L10n.string("health_meals_body_ai.b76e2c70647b", fallback: "入力方法"), selection: $inputMode) {
                        ForEach(MealInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mealInputModePicker")

                    if inputMode == .photo {
                        HStack(spacing: 12) {
                            Button {
                                requestCameraAccess()
                            } label: {
                                Label(L10n.string("health_meals_body_ai.e4a6aca658b9", fallback: "撮影"), systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            .accessibilityIdentifier("mealCameraButton")

                            photoLibraryControl
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("mealPhotoPicker")
                        }

                        if let imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                        }

                        Button {
                            analyzeMealImage()
                        } label: {
                            Label(imageAnalysisButtonTitle, systemImage: "sparkles")
                        }
                        .disabled(
                            imageData == nil
                                || isAnalyzing
                                || !canUseMealAI
                        )
                        .accessibilityIdentifier("analyzeMealButton")
                    } else {
                        ForEach($foodInputs) { $item in
                            HStack(spacing: 8) {
                                TextField(L10n.string("health_meals_body_ai.87bd781e5e2a", fallback: "例：白ごはん 150g"), text: $item.text)
                                    .textInputAutocapitalization(.never)
                                    .accessibilityIdentifier("mealFoodItemField-\(item.id.uuidString)")

                                if foodInputs.count > 1 {
                                    Button {
                                        removeFoodInput(item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(AppTheme.critical)
                                    .accessibilityLabel(L10n.string("health_meals_body_ai.907dbde4bc88", fallback: "削除"))
                                }
                            }
                        }

                        Button {
                            foodInputs.append(MealFoodInput())
                        } label: {
                            Label(L10n.string("health_meals_body_ai.9e38754cb6e4", fallback: "食べたものを追加"), systemImage: "plus")
                        }
                        .disabled(foodInputs.count >= 20)
                        .accessibilityIdentifier("addMealFoodItemButton")

                        HStack(spacing: 10) {
                            Button {
                                isShowingFoodDatabase = true
                            } label: {
                                Label(L10n.string("health_meals_body_ai.3d6e7d3996d5", fallback: "食品DB"), systemImage: "books.vertical.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("openFoodDatabaseButton")

                            Button {
                                isShowingBarcode = true
                            } label: {
                                Label(L10n.string("health_meals_body_ai.f15118749eab", fallback: "バーコード"), systemImage: "barcode.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("openBarcodeFoodButton")
                        }

                        ForEach($compositionItems) { $item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button {
                                        compositionItems.removeAll { $0.id == item.id }
                                        applyCompositionNutrition()
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(AppTheme.critical)
                                    .accessibilityLabel(L10n.string("health_meals_body_ai.d801f8eaaf8a", fallback: "{{value1}}を削除", values: [String(describing: item.name)]))
                                }

                                NumericTextInputControl(
                                    text: Binding(
                                        get: { item.amountGrams.formatted(.number.precision(.fractionLength(0...1))) },
                                        set: { item.amountGrams = parsed($0) }
                                    ),
                                    title: L10n.string("health_meals_body_ai.33cef63d33eb", fallback: "実食量"),
                                    unit: "g",
                                    range: 0...2_000,
                                    step: 1,
                                    defaultValue: item.amountGrams,
                                    accessibilityIdentifier: "compositionAmount-\(item.id.uuidString)"
                                )
                                Text("\(Int(item.nutrition.calories.rounded()))kcal  P\(Int(item.nutrition.protein.rounded()))  F\(Int(item.nutrition.fat.rounded()))  C\(Int(item.nutrition.carbs.rounded()))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                if let note = item.dataQualityNote {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.warning)
                                }
                            }
                        }

                        if !compositionItems.isEmpty {
                            let total = compositionNutritionTotal
                            VStack(alignment: .leading, spacing: 8) {
                                Label(L10n.string("health_meals_body_ai.4563c325c141", fallback: "食品から自動集計"), systemImage: "sum")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.positive)
                                    .accessibilityIdentifier("compositionNutritionSummary")
                                Text(
                                    "\(AppFormatters.calories(total.calories))  "
                                    + "P \(AppFormatters.grams(total.protein))  "
                                    + "F \(AppFormatters.grams(total.fat))  "
                                    + "C \(AppFormatters.grams(total.carbs))"
                                )
                                .font(.headline)
                                Text(L10n.string("health_meals_body_ai.61184419aea8", fallback: "食品DBとバーコードの追加・実食量変更をすぐ合計へ反映します。自由入力した食品はAI推定後に合算します。"))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }

                        Button {
                            analyzeMealText()
                        } label: {
                            Label(textAnalysisButtonTitle, systemImage: "sparkles")
                        }
                        .disabled(allFoodItems.isEmpty || isAnalyzing || !canUseMealAI)
                        .accessibilityIdentifier("analyzeMealTextButton")
                    }

                    Text(aiHelpText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Section(L10n.string("health_meals_body_ai.738844ab541c", fallback: "食事")) {
                    DatePicker(
                        L10n.string("health_meals_body_ai.c5deaf60f00d", fallback: "記録日"),
                        selection: $recordedAt,
                        in: RecordDatePolicy.allowedRange(),
                        displayedComponents: .date
                    )

                    Picker(L10n.string("health_meals_body_ai.bc5796a0a9e9", fallback: "種類"), selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    TextField(L10n.string("health_meals_body_ai.c5b5539d921c", fallback: "食事名"), text: $name)
                        .accessibilityIdentifier("mealNameField")
                }

                Section("PFC") {
                    Toggle(L10n.string("health_meals_body_ai.16bcee4b0ed9", fallback: "PFCからカロリーを自動計算"), isOn: $calculatesCaloriesFromPFC)
                        .accessibilityIdentifier("mealAutoCalorieToggle")

                    NumericTextInputControl(
                        text: $calories,
                        title: L10n.string("health_meals_body_ai.a412f109a6d5", fallback: "カロリー"),
                        unit: "kcal",
                        range: 0...5_000,
                        step: 1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealCaloriesField"
                    )
                    .disabled(calculatesCaloriesFromPFC)
                    NumericTextInputControl(
                        text: $protein,
                        title: L10n.string("health_meals_body_ai.140a2c34da87", fallback: "たんぱく質"),
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealProteinField"
                    )
                    NumericTextInputControl(
                        text: $fat,
                        title: L10n.string("health_meals_body_ai.c20a7b4dbb8b", fallback: "脂質"),
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealFatField"
                    )
                    NumericTextInputControl(
                        text: $carbs,
                        title: L10n.string("health_meals_body_ai.09beaa3b972f", fallback: "炭水化物"),
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealCarbsField"
                    )

                    if calculatesCaloriesFromPFC {
                        Text("P×4 + F×9 + C×4 = \(calculatedCalories.formatted(.number.precision(.fractionLength(0)))) kcal")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Section(L10n.string("health_meals_body_ai.03b5d7044111", fallback: "メモ")) {
                    TextField(L10n.string("health_meals_body_ai.03b5d7044111", fallback: "メモ"), text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let aiDraft {
                    Section(L10n.string("health_meals_body_ai.e6415cd101bd", fallback: "{{value1}}の下書き", values: [String(describing: appStore.userProfile.coachPersona.displayName)])) {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: L10n.string("health_meals_body_ai.9c55bbc73d4a", fallback: "確認してから保存してください")
                        )
                        LabeledContent(L10n.string("health_meals_body_ai.7421e1ca9b5b", fallback: "信頼度"), value: aiDraft.confidence)

                        if !aiDraft.comment.isEmpty {
                            Text(aiDraft.comment)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)
                        }

                        ForEach(aiDraft.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text("\(item.amount) / \(AppFormatters.calories(item.calories)) / P \(AppFormatters.preciseGrams(item.protein))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                if item.nutritionSource == .mext {
                                    Label(L10n.string("health_meals_body_ai.00ae7a9a5808", fallback: "食品成分表で再計算"), systemImage: "checkmark.seal.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.positive)
                                } else {
                                    Label(L10n.string("health_meals_body_ai.7e9dd72271a8", fallback: "AI参考値・要確認"), systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.warning)
                                }
                            }
                        }
                    }
                }

                if let aiErrorMessage {
                    Section(L10n.string("health_meals_body_ai.7d80eebb209d", fallback: "AIエラー")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(aiErrorMessage, systemImage: "xmark.octagon.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.critical)

                            if let aiErrorRecovery {
                                Text(aiErrorRecovery)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }

                            Text(L10n.string("health_meals_body_ai.a9e371b42094", fallback: "食事名とPFCを手動で入力すれば、このまま保存できます。"))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .accessibilityIdentifier("mealAIErrorRecoveryCard")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(existingMeal == nil ? L10n.string("health_meals_body_ai.2fab54303f04", fallback: "食事を記録") : L10n.string("health_meals_body_ai.f31f45373056", fallback: "食事を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveMealButton")
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let loadedData = try? await item?.loadTransferable(type: Data.self) else {
                        return
                    }
                    receiveImageData(loadedData)
                }
            }
            .onAppear {
                if existingMeal == nil {
                    restorePreviousNutritionValues(for: mealType)
                }
            }
            .onChange(of: mealType) { _, newMealType in
                guard existingMeal == nil, imageData == nil, aiDraft == nil else { return }
                restorePreviousNutritionValues(for: newMealType)
            }
            .onChange(of: protein) { _, _ in updateCalculatedCalories() }
            .onChange(of: fat) { _, _ in updateCalculatedCalories() }
            .onChange(of: carbs) { _, _ in updateCalculatedCalories() }
            .onChange(of: calculatesCaloriesFromPFC) { _, isEnabled in
                if isEnabled {
                    updateCalculatedCalories()
                }
            }
            .onChange(of: compositionItems) { _, _ in
                applyCompositionNutrition()
            }
            .sheet(isPresented: $isShowingFoodDatabase) {
                FoodCompositionPickerView { item in
                    addCompositionItem(item)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = item.name
                    }
                }
            }
            .sheet(isPresented: $isShowingBarcode) {
                BarcodeFoodPickerView { item in
                    addCompositionItem(item)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = item.name
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraImagePicker { data in
                    isShowingCamera = false
                    receiveImageData(data)
                } onCancel: {
                    isShowingCamera = false
                }
                .ignoresSafeArea()
            }
            .alert(L10n.string("health_meals_body_ai.188fd18847ac", fallback: "カメラを使用できません"), isPresented: $isShowingCameraPermissionAlert) {
                Button(L10n.string("health_meals_body_ai.1ed3ceaf4396", fallback: "設定を開く")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル"), role: .cancel) {}
            } message: {
                Text(L10n.string("health_meals_body_ai.576015450b34", fallback: "設定でBodyModeのカメラ利用を許可してください。"))
            }
            .aiCreditRecoverySheet(
                issue: $creditAccessIssue,
                settings: appStore.aiSettings,
                onResolved: {
                    await MainActor.run {
                        aiErrorMessage = nil
                        aiErrorRecovery = nil
                        if inputMode == .photo {
                            analyzeMealImage()
                        } else {
                            analyzeMealText()
                        }
                    }
                }
            )
        }
    }

    private var calculatedCalories: Double {
        parsed(protein) * 4 + parsed(fat) * 9 + parsed(carbs) * 4
    }

    @ViewBuilder
    private var photoLibraryControl: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stub-meal-ai") {
            Button {
                receiveImageData(Data("meal-photo-ui-test".utf8))
            } label: {
                Label(L10n.string("health_meals_body_ai.506e586e218c", fallback: "ライブラリ"), systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(L10n.string("health_meals_body_ai.506e586e218c", fallback: "ライブラリ"), systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
        }
        #else
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label(L10n.string("health_meals_body_ai.506e586e218c", fallback: "ライブラリ"), systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
        #endif
    }

    private func parsed(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func updateCalculatedCalories() {
        guard calculatesCaloriesFromPFC else { return }
        calories = calculatedCalories.formatted(.number.precision(.fractionLength(0)))
    }

    private func restorePreviousNutritionValues(for mealType: MealType) {
        guard let previous = appStore.latestMealEntry(for: mealType) else {
            calories = ""
            protein = ""
            fat = ""
            carbs = ""
            calculatesCaloriesFromPFC = true
            return
        }

        protein = previous.protein.formatted(.number.precision(.fractionLength(0)))
        fat = previous.fat.formatted(.number.precision(.fractionLength(0)))
        carbs = previous.carbs.formatted(.number.precision(.fractionLength(0)))

        let pfcCalories = previous.protein * 4 + previous.fat * 9 + previous.carbs * 4
        calculatesCaloriesFromPFC = abs(previous.calories - pfcCalories) < 1
        calories = previous.calories.formatted(.number.precision(.fractionLength(0)))
        updateCalculatedCalories()
    }

    private var aiHelpText: String {
        if !appStore.aiSettings.isEnabled {
            return L10n.string("health_meals_body_ai.16d5fbaa5425", fallback: "AI機能は設定でオフです。手動入力はこのまま保存できます。")
        }

        if !appStore.aiSettings.dataSharing.meals {
            return L10n.string("health_meals_body_ai.166aed922fa0", fallback: "食事のAI共有は設定でオフです。")
        }

        if inputMode == .foodList {
            return L10n.string("health_meals_body_ai.1313855c233c", fallback: "分かる範囲で量も書くと、推定精度が上がります。")
        }

        if imageData == nil { return L10n.string("health_meals_body_ai.9ab5dabe4459", fallback: "写真を選ぶと、カロリーなどを自動入力します。") }
        return L10n.string("health_meals_body_ai.24383cef4e4f", fallback: "推定値は参考値です。下の入力欄で自由に修正できます。")
    }

    private var imageAnalysisButtonTitle: String {
        if isAnalyzing { return L10n.string("health_meals_body_ai.333d812c9fca", fallback: "カロリー推定中") }
        return aiDraft == nil ? L10n.string("health_meals_body_ai.8c5fc5e7a8da", fallback: "写真からカロリーを推定") : L10n.string("health_meals_body_ai.9200c9bcb7a4", fallback: "もう一度推定")
    }

    private var textAnalysisButtonTitle: String {
        if isAnalyzing { return L10n.string("health_meals_body_ai.333d812c9fca", fallback: "カロリー推定中") }
        return aiDraft == nil ? L10n.string("health_meals_body_ai.530bc7429a78", fallback: "リストからカロリーを推定") : L10n.string("health_meals_body_ai.9200c9bcb7a4", fallback: "もう一度推定")
    }

    private var canUseMealAI: Bool {
        appStore.aiSettings.isEnabled && appStore.aiSettings.dataSharing.meals
    }

    private var validFoodItems: [String] {
        foodInputs
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var allFoodItems: [String] {
        validFoodItems + compositionItems.map(\.displayText)
    }

    private var compositionNutritionTotal: NutritionAmount {
        compositionItems.reduce(.zero) { $0 + $1.nutrition }
    }

    private func addCompositionItem(_ item: MealCompositionItem) {
        if let index = compositionItems.firstIndex(where: {
            $0.sourceKind == item.sourceKind && $0.sourceID == item.sourceID
        }) {
            compositionItems[index].amountGrams += item.amountGrams
        } else {
            compositionItems.append(item)
        }
        applyCompositionNutrition()
    }

    private func applyCompositionNutrition() {
        guard !compositionItems.isEmpty else { return }
        let total = compositionNutritionTotal
        calculatesCaloriesFromPFC = false
        calories = total.calories.formatted(.number.precision(.fractionLength(0)))
        protein = total.protein.formatted(.number.precision(.fractionLength(0)))
        fat = total.fat.formatted(.number.precision(.fractionLength(0)))
        carbs = total.carbs.formatted(.number.precision(.fractionLength(0)))
    }

    private func removeFoodInput(_ id: UUID) {
        foodInputs.removeAll { $0.id == id }
        if foodInputs.isEmpty {
            foodInputs = [MealFoodInput()]
        }
    }

    private func requestCameraAccess() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    if granted {
                        isShowingCamera = true
                    } else {
                        isShowingCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            isShowingCameraPermissionAlert = true
        @unknown default:
            isShowingCameraPermissionAlert = true
        }
    }

    private func receiveImageData(_ data: Data) {
        inputMode = .photo
        imageData = (try? AIImageUploadProcessor.jpegData(from: data)) ?? data
        aiDraft = nil
        aiErrorMessage = nil
        aiErrorRecovery = nil
        if appStore.aiSettings.isEnabled {
            analyzeMealImage()
        }
    }

    private func analyzeMealImage() {
        guard let imageData,
              appStore.aiSettings.isEnabled,
              appStore.aiSettings.dataSharing.meals else {
            return
        }

        isAnalyzing = true
        aiErrorMessage = nil
        aiErrorRecovery = nil
        let transmission = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.6301c7ac2181", fallback: "食事画像解析"),
            sharedCategories: [L10n.string("health_meals_body_ai.909d632d0101", fallback: "食事写真")],
            itemCount: 1
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let draft = try await AIAPIClient(settings: appStore.aiSettings)
                    .analyzeMealImage(
                        imageData: imageData,
                        mealType: mealType,
                        memo: memo,
                        coach: AIRequestCoachContext(profile: appStore.userProfile)
                    )
                await MainActor.run {
                    apply(draft)
                    appStore.updateAITransmission(id: transmission.id, status: .completed)
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                    let presentation = AIClientError.presentation(for: error)
                    aiErrorMessage = presentation.message
                    aiErrorRecovery = presentation.recovery
                    creditAccessIssue = AICreditAccessIssue(error: error)
                    isAnalyzing = false
                }
            }
        }
    }

    private func analyzeMealText() {
        let items = allFoodItems
        guard !items.isEmpty,
              appStore.aiSettings.isEnabled,
              appStore.aiSettings.dataSharing.meals else {
            return
        }

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = mealName(from: items)
        }

        isAnalyzing = true
        aiErrorMessage = nil
        aiErrorRecovery = nil
        let transmission = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.037d690fd891", fallback: "食事内容解析"),
            sharedCategories: [L10n.string("health_meals_body_ai.3384dbefe259", fallback: "食事名・量")],
            itemCount: items.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let draft = try await AIAPIClient(settings: appStore.aiSettings)
                    .analyzeMealText(
                        items: items,
                        mealType: mealType,
                        memo: memo,
                        coach: AIRequestCoachContext(profile: appStore.userProfile)
                    )
                await MainActor.run {
                    apply(draft)
                    appStore.updateAITransmission(id: transmission.id, status: .completed)
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                    let presentation = AIClientError.presentation(for: error)
                    aiErrorMessage = presentation.message
                    aiErrorRecovery = presentation.recovery
                    creditAccessIssue = AICreditAccessIssue(error: error)
                    isAnalyzing = false
                }
            }
        }
    }

    private func apply(_ draft: MealAIDraft) {
        let resolved = MealNutritionResolver().resolve(draft).draft
        aiDraft = resolved
        name = resolved.mealName
        calculatesCaloriesFromPFC = false
        calories = resolved.calories.formatted(.number.precision(.fractionLength(0)))
        protein = resolved.protein.formatted(.number.precision(.fractionLength(0)))
        fat = resolved.fat.formatted(.number.precision(.fractionLength(0)))
        carbs = resolved.carbs.formatted(.number.precision(.fractionLength(0)))
    }

    private func mealName(from items: [String]) -> String {
        let names = items.prefix(3).map { item in
            item.replacingOccurrences(
                of: #"\s+(?:\d+(?:[.,]\d+)?\s*)?(?:g|kg|ml|l|個|枚|杯|本|切れ|食|人前)\b.*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        let suffix = items.count > 3 ? " " + L10n.string("health_meals_body_ai.9cc8f59144b4", fallback: "ほか{{value1}}品", values: [(items.count - 3).formatted()]) : ""
        return names.joined(separator: L10n.string("health_meals_body_ai.3654226ac56b", fallback: "・")) + suffix
    }

    private func save() {
        appStore.saveMealEntry(
            MealEntry(
                id: existingMeal?.id ?? UUID(),
            recordedAt: RecordDatePolicy.normalizedDay(recordedAt),
                mealType: mealType,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: parsed(calories),
                protein: parsed(protein),
                fat: parsed(fat),
                carbs: parsed(carbs),
                memo: memo,
                imageData: imageData,
                foodItems: inputMode == .foodList ? validFoodItems : [],
                compositionItems: inputMode == .foodList ? compositionItems : [],
                aiDraft: aiDraft,
                confirmedByUser: true
            )
        )
        onSave()
    }
}

#Preview {
    MealListView()
        .environmentObject(AppStore())
}
