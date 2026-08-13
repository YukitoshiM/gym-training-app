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
                        MetricPill(title: "今日の食事", value: "\(appStore.mealEntries().count)", systemImage: "fork.knife", tint: AppTheme.orange)
                        MetricPill(title: "摂取 kcal", value: AppFormatters.calories(todayCalories), systemImage: "flame", tint: AppTheme.accent)
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
                        coachPersona: appStore.userProfile.coachPersona
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section("記録") {
                    if appStore.mealEntries.isEmpty {
                        Text("食事記録はまだありません")
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
                        .accessibilityLabel("\(meal.name)を編集")
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
            .navigationTitle("食事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRequest = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("食事を追加")
                    .accessibilityIdentifier("addMealButton")
                }
            }
            .sheet(item: $editorRequest) { request in
                MealEditorView(existingMeal: request.meal) {
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

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CoachAttributionLabel(
                    persona: coachPersona,
                    text: "今日の食事候補",
                    avatarSize: 30
                )
                ForEach(suggestions) { suggestion in
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
                    }
                }
            }
        }
        .accessibilityIdentifier("dailyMealSuggestionsCard")
    }
}

private struct MealEditorRequest: Identifiable {
    let id: UUID
    let meal: MealEntry?

    static var new: MealEditorRequest {
        MealEditorRequest(id: UUID(), meal: nil)
    }

    init(id: UUID = UUID(), meal: MealEntry?) {
        self.id = id
        self.meal = meal
    }
}

private struct NutritionGoalCard: View {
    let progress: DailyNutritionProgress

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日の食事目標")
                            .font(.headline)
                        Text("回数と栄養を別々に判定")
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
                    "\(progress.mealCount)/\(progress.goals.mealCount)回",
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
            return "kcal・PFC達成"
        }
        if progress.isCalorieAchieved {
            return "kcal達成"
        }
        if progress.isPFCAchieved {
            return "PFC達成"
        }
        return "栄養途中"
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

                    Text(AppFormatters.shortDateTime.string(from: meal.recordedAt))
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
                            text: "\(coachPersona.displayName)の下書き・\(aiDraft.confidence)",
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
        case .photo: "写真"
        case .foodList: "食べたもの"
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
    @State private var calculatesCaloriesFromPFC: Bool
    @State private var inputMode: MealInputMode
    @State private var foodInputs: [MealFoodInput]
    @State private var compositionItems: [MealCompositionItem]
    @State private var isShowingCamera = false
    @State private var isShowingCameraPermissionAlert = false
    @State private var isShowingFoodDatabase = false
    @State private var isShowingBarcode = false

    init(existingMeal: MealEntry? = nil, onSave: @escaping () -> Void) {
        self.existingMeal = existingMeal
        self.onSave = onSave

        let protein = existingMeal?.protein ?? 0
        let fat = existingMeal?.fat ?? 0
        let carbs = existingMeal?.carbs ?? 0
        let pfcCalories = protein * 4 + fat * 9 + carbs * 4
        let storedCalories = existingMeal?.calories ?? 0
        let foodItems = existingMeal?.foodItems ?? []

        _mealType = State(initialValue: existingMeal?.mealType ?? .lunch)
        _name = State(initialValue: existingMeal?.name ?? "")
        _calories = State(initialValue: existingMeal.map {
            $0.calories.formatted(.number.precision(.fractionLength(0)))
        } ?? "")
        _protein = State(initialValue: existingMeal.map {
            $0.protein.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "")
        _fat = State(initialValue: existingMeal.map {
            $0.fat.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "")
        _carbs = State(initialValue: existingMeal.map {
            $0.carbs.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "")
        _memo = State(initialValue: existingMeal?.memo ?? "")
        _imageData = State(initialValue: existingMeal?.imageData)
        _aiDraft = State(initialValue: existingMeal?.aiDraft)
        _calculatesCaloriesFromPFC = State(
            initialValue: existingMeal == nil || abs(storedCalories - pfcCalories) < 1
        )
        _inputMode = State(
            initialValue: (!foodItems.isEmpty || !(existingMeal?.compositionItems.isEmpty ?? true))
                && existingMeal?.imageData == nil ? .foodList : .photo
        )
        _foodInputs = State(
            initialValue: foodItems.isEmpty
                ? [MealFoodInput()]
                : foodItems.map { MealFoodInput(text: $0) }
        )
        _compositionItems = State(initialValue: existingMeal?.compositionItems ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("入力方法") {
                    CoachIdentityView(
                        persona: appStore.userProfile.coachPersona,
                        role: "食事チェック",
                        detail: "写真や食べたものから栄養の下書きを作ります。",
                        avatarSize: 48
                    )
                    .accessibilityIdentifier("mealAICoachIdentity")

                    Picker("入力方法", selection: $inputMode) {
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
                                Label("撮影", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            .accessibilityIdentifier("mealCameraButton")

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("ライブラリ", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
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
                                TextField("例：白ごはん 150g", text: $item.text)
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
                                    .accessibilityLabel("削除")
                                }
                            }
                        }

                        Button {
                            foodInputs.append(MealFoodInput())
                        } label: {
                            Label("食べたものを追加", systemImage: "plus")
                        }
                        .disabled(foodInputs.count >= 20)
                        .accessibilityIdentifier("addMealFoodItemButton")

                        HStack(spacing: 10) {
                            Button {
                                isShowingFoodDatabase = true
                            } label: {
                                Label("食品DB", systemImage: "books.vertical.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("openFoodDatabaseButton")

                            Button {
                                isShowingBarcode = true
                            } label: {
                                Label("バーコード", systemImage: "barcode.viewfinder")
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
                                    .accessibilityLabel("\(item.name)を削除")
                                }

                                NumericTextInputControl(
                                    text: Binding(
                                        get: { item.amountGrams.formatted(.number.precision(.fractionLength(0...1))) },
                                        set: { item.amountGrams = parsed($0) }
                                    ),
                                    title: "実食量",
                                    unit: "g",
                                    range: 0...2_000,
                                    step: 1,
                                    defaultValue: item.amountGrams,
                                    accessibilityIdentifier: "compositionAmount-\(item.id.uuidString)"
                                )
                                Text("\(Int(item.nutrition.calories.rounded()))kcal  P\(item.nutrition.protein.formatted(.number.precision(.fractionLength(0...1))))  F\(item.nutrition.fat.formatted(.number.precision(.fractionLength(0...1))))  C\(item.nutrition.carbs.formatted(.number.precision(.fractionLength(0...1))))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                if let note = item.dataQualityNote {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.warning)
                                }
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

                Section("食事") {
                    Picker("種類", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    TextField("食事名", text: $name)
                        .accessibilityIdentifier("mealNameField")
                }

                Section("PFC") {
                    Toggle("PFCからカロリーを自動計算", isOn: $calculatesCaloriesFromPFC)
                        .accessibilityIdentifier("mealAutoCalorieToggle")

                    NumericTextInputControl(
                        text: $calories,
                        title: "カロリー",
                        unit: "kcal",
                        range: 0...5_000,
                        step: 1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealCaloriesField"
                    )
                    .disabled(calculatesCaloriesFromPFC)
                    NumericTextInputControl(
                        text: $protein,
                        title: "たんぱく質",
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealProteinField"
                    )
                    NumericTextInputControl(
                        text: $fat,
                        title: "脂質",
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "mealFatField"
                    )
                    NumericTextInputControl(
                        text: $carbs,
                        title: "炭水化物",
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

                Section("メモ") {
                    TextField("メモ", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let aiDraft {
                    Section("\(appStore.userProfile.coachPersona.displayName)の下書き") {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: "確認してから保存してください"
                        )
                        LabeledContent("信頼度", value: aiDraft.confidence)

                        if !aiDraft.comment.isEmpty {
                            Text(aiDraft.comment)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)
                        }

                        ForEach(aiDraft.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text("\(item.amount) / \(AppFormatters.calories(item.calories)) / P \(AppFormatters.grams(item.protein))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                                if item.nutritionSource == .mext {
                                    Label("食品成分表で再計算", systemImage: "checkmark.seal.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.positive)
                                } else {
                                    Label("AI参考値・要確認", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.warning)
                                }
                            }
                        }
                    }
                }

                if let aiErrorMessage {
                    Section("AIエラー") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(aiErrorMessage, systemImage: "xmark.octagon.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.critical)

                            if let aiErrorRecovery {
                                Text(aiErrorRecovery)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }

                            Text("食事名とPFCを手動で入力すれば、このまま保存できます。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .accessibilityIdentifier("mealAIErrorRecoveryCard")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(existingMeal == nil ? "食事を記録" : "食事を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
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
                    compositionItems.append(item)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = item.name
                    }
                    applyCompositionNutrition()
                }
            }
            .sheet(isPresented: $isShowingBarcode) {
                BarcodeFoodPickerView { item in
                    compositionItems.append(item)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = item.name
                    }
                    applyCompositionNutrition()
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
            .alert("カメラを使用できません", isPresented: $isShowingCameraPermissionAlert) {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("設定でBodyModeのカメラ利用を許可してください。")
            }
        }
    }

    private var calculatedCalories: Double {
        parsed(protein) * 4 + parsed(fat) * 9 + parsed(carbs) * 4
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

        protein = previous.protein.formatted(.number.precision(.fractionLength(0...1)))
        fat = previous.fat.formatted(.number.precision(.fractionLength(0...1)))
        carbs = previous.carbs.formatted(.number.precision(.fractionLength(0...1)))

        let pfcCalories = previous.protein * 4 + previous.fat * 9 + previous.carbs * 4
        calculatesCaloriesFromPFC = abs(previous.calories - pfcCalories) < 1
        calories = previous.calories.formatted(.number.precision(.fractionLength(0)))
        updateCalculatedCalories()
    }

    private var aiHelpText: String {
        if !appStore.aiSettings.isEnabled {
            return "AI機能は設定でオフです。手動入力はこのまま保存できます。"
        }

        if !appStore.aiSettings.dataSharing.meals {
            return "食事のAI共有は設定でオフです。"
        }

        if inputMode == .foodList {
            return "分かる範囲で量も書くと、推定精度が上がります。"
        }

        if imageData == nil { return "写真を選ぶと、カロリーなどを自動入力します。" }
        return "推定値は参考値です。下の入力欄で自由に修正できます。"
    }

    private var imageAnalysisButtonTitle: String {
        if isAnalyzing { return "カロリー推定中" }
        return aiDraft == nil ? "写真からカロリーを推定" : "もう一度推定"
    }

    private var textAnalysisButtonTitle: String {
        if isAnalyzing { return "カロリー推定中" }
        return aiDraft == nil ? "リストからカロリーを推定" : "もう一度推定"
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

    private func applyCompositionNutrition() {
        guard !compositionItems.isEmpty else { return }
        let total = compositionItems.reduce(NutritionAmount.zero) { $0 + $1.nutrition }
        calculatesCaloriesFromPFC = false
        calories = total.calories.formatted(.number.precision(.fractionLength(0)))
        protein = total.protein.formatted(.number.precision(.fractionLength(0...1)))
        fat = total.fat.formatted(.number.precision(.fractionLength(0...1)))
        carbs = total.carbs.formatted(.number.precision(.fractionLength(0...1)))
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
            purpose: "食事画像解析",
            sharedCategories: ["食事写真"],
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
                    appStore.updateAITransmission(id: transmission.id, status: .failed)
                    let presentation = AIClientError.presentation(for: error)
                    aiErrorMessage = presentation.message
                    aiErrorRecovery = presentation.recovery
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
            purpose: "食事内容解析",
            sharedCategories: ["食事名・量"],
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
                    appStore.updateAITransmission(id: transmission.id, status: .failed)
                    let presentation = AIClientError.presentation(for: error)
                    aiErrorMessage = presentation.message
                    aiErrorRecovery = presentation.recovery
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
        protein = resolved.protein.formatted(.number.precision(.fractionLength(0...1)))
        fat = resolved.fat.formatted(.number.precision(.fractionLength(0...1)))
        carbs = resolved.carbs.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func mealName(from items: [String]) -> String {
        let names = items.prefix(3).map { item in
            item.replacingOccurrences(
                of: #"\s+(?:\d+(?:[.,]\d+)?\s*)?(?:g|kg|ml|l|個|枚|杯|本|切れ|食|人前)\b.*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        let suffix = items.count > 3 ? " ほか\(items.count - 3)品" : ""
        return names.joined(separator: "・") + suffix
    }

    private func save() {
        appStore.saveMealEntry(
            MealEntry(
                id: existingMeal?.id ?? UUID(),
                recordedAt: existingMeal?.recordedAt ?? Date(),
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
