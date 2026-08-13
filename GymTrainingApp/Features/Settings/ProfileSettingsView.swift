import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var gymLocationManager: GymLocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var aiDraft: AISettings
    @State private var sensorDraft: SensorSettings
    @State private var appearanceDraft: AppAppearanceSettings
    @State private var heightText: String
    @State private var birthYearText: String
    @State private var weeklyTrainingDaysText: String
    @State private var preferredSessionMinutesText: String
    @State private var calorieGoalText: String
    @State private var proteinGoalText: String
    @State private var fatGoalText: String
    @State private var carbsGoalText: String
    @State private var mealCountGoalText: String
    @State private var isConfirmingReset = false
    @State private var isCheckingAI = false
    @State private var aiConnectionResult: AIConnectionCheckResult?
    @State private var isExportingData = false
    @State private var exportDocument = GymDataExportDocument()
    @State private var isExportingDiagnostics = false
    @State private var diagnosticDocument = DiagnosticLogDocument()
    @State private var diagnosticSharePayload: DiagnosticSharePayload?
    @State private var usageAnalyticsEnabled: Bool
    @State private var isExportingUsageAnalytics = false
    @State private var usageAnalyticsDocument = DiagnosticLogDocument()
    @State private var exportErrorMessage: String?
    @State private var isAISharingExpanded = false

    init(
        profile: UserProfile,
        aiSettings: AISettings = .default,
        sensorSettings: SensorSettings = .default,
        appearanceSettings: AppAppearanceSettings = .default
    ) {
        _draft = State(initialValue: profile)
        _aiDraft = State(initialValue: aiSettings)
        _sensorDraft = State(initialValue: sensorSettings)
        _appearanceDraft = State(initialValue: appearanceSettings)
        _usageAnalyticsEnabled = State(initialValue: UsageAnalytics.shared.isCollectionEnabled)
        _heightText = State(initialValue: profile.heightCm.map { String(format: "%.1f", $0) } ?? "")
        _birthYearText = State(initialValue: profile.birthYear.map(String.init) ?? "")
        _weeklyTrainingDaysText = State(initialValue: String(profile.weeklyTrainingDays))
        _preferredSessionMinutesText = State(initialValue: String(profile.preferredSessionMinutes))
        _calorieGoalText = State(initialValue: profile.nutritionGoals.calories.formatted(.number.precision(.fractionLength(0))))
        _proteinGoalText = State(initialValue: profile.nutritionGoals.protein.formatted(.number.precision(.fractionLength(0...1))))
        _fatGoalText = State(initialValue: profile.nutritionGoals.fat.formatted(.number.precision(.fractionLength(0...1))))
        _carbsGoalText = State(initialValue: profile.nutritionGoals.carbs.formatted(.number.precision(.fractionLength(0...1))))
        _mealCountGoalText = State(initialValue: String(profile.nutritionGoals.mealCount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プロフィール") {
                    Picker("目的", selection: $draft.goalType) {
                        ForEach(GoalType.allCases) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    .onChange(of: draft.goalType) { _, goal in
                        if !OutcomeStyle.available(for: goal).contains(draft.outcomeStyle) {
                            draft.outcomeStyle = OutcomeStyle.recommended(for: goal)
                        }
                        if !goal.supportsFocusMuscles {
                            draft.focusMuscles = []
                        }
                    }

                    CoachRecommendationPicker(profile: $draft)

                    Picker("すべての担当", selection: $draft.coachType) {
                        ForEach(CoachType.allCases) { coach in
                            Text(coach.displayName).tag(coach)
                        }
                    }
                    .accessibilityIdentifier("coachTypePicker")

                    if draft.coachType != CoachType.recommended(for: draft.goalType) {
                        Button {
                            draft.coachType = CoachType.recommended(for: draft.goalType)
                        } label: {
                            Label("おすすめの担当を適用", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("applyRecommendedCoachButton")
                    }

                    CoachPersonaPicker(selection: $draft.coachPersona)

                    Picker("話し方", selection: $draft.coachingStyle) {
                        ForEach(CoachingStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("coachingStylePicker")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.coachType.expertiseProfile.promise)
                            .font(.subheadline.bold())
                        Text(CoachType.recommendationReason(for: draft))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .accessibilityIdentifier("coachCharacteristic")

                    DisclosureGroup("担当コーチの方針") {
                        CoachExpertiseSummary(profile: draft.coachType.expertiseProfile)
                    }
                    .accessibilityIdentifier("coachExpertiseDetails")

                    NumericTextInputControl(
                        text: $heightText,
                        title: "身長",
                        unit: "cm",
                        range: 50...250,
                        step: 0.1,
                        defaultValue: 170,
                        accessibilityIdentifier: "profileHeightField"
                    )

                    NumericTextInputControl(
                        text: $birthYearText,
                        title: "生年",
                        unit: "年",
                        range: 1900...Double(Calendar.current.component(.year, from: Date())),
                        step: 1,
                        defaultValue: Double(Calendar.current.component(.year, from: Date()) - 30),
                        accessibilityIdentifier: "profileBirthYearField"
                    )

                    Picker("性別", selection: $draft.sex) {
                        ForEach(Sex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }

                    Picker("経験レベル", selection: $draft.experienceLevel) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                Section("目標とペース") {
                    Picker("目指すスタイル", selection: $draft.outcomeStyle) {
                        ForEach(OutcomeStyle.available(for: draft.goalType)) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("outcomeStylePicker")

                    Text(draft.outcomeStyle.detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    if draft.outcomeStyle == .custom {
                        TextField("目指したい状態", text: $draft.customOutcomeText, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("customOutcomeField")
                    }

                    if draft.goalType.supportsFocusMuscles {
                        Menu {
                            ForEach(MuscleGroup.focusSelectionCases) { muscle in
                                Button {
                                    toggleFocusMuscle(muscle)
                                } label: {
                                    Label(
                                        muscle.displayName,
                                        systemImage: draft.focusMuscles.contains(muscle) ? "checkmark" : muscle.systemImage
                                    )
                                }
                            }
                        } label: {
                            LabeledContent("重点部位", value: focusMuscleSummary)
                        }
                        .accessibilityIdentifier("focusMuscleMenu")
                    }

                    NumericTextInputControl(
                        text: $weeklyTrainingDaysText,
                        title: "週の回数",
                        unit: "日",
                        range: 1...7,
                        step: 1,
                        defaultValue: 3,
                        accessibilityIdentifier: "weeklyTrainingDaysField"
                    )

                    NumericTextInputControl(
                        text: $preferredSessionMinutesText,
                        title: "1回の時間",
                        unit: "分",
                        range: 10...240,
                        step: 5,
                        defaultValue: 60,
                        accessibilityIdentifier: "preferredSessionMinutesField"
                    )
                }

                Section {
                    ForEach(Equipment.allCases) { equipment in
                        Button {
                            toggleEquipment(equipment)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: equipment.systemImage)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 28)
                                Text(equipment.displayName)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Image(systemName: draft.availableEquipment.contains(equipment) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        draft.availableEquipment.contains(equipment) ? AppTheme.accent : AppTheme.mutedInk
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("availableEquipment-\(equipment.rawValue)")
                    }
                } header: {
                    Text("使える器具")
                } footer: {
                    Text("AIコーチは選択した器具だけでトレーニング計画を作ります。最低1つは選択されます。")
                }

                Section {
                    NumericTextInputControl(
                        text: $calorieGoalText,
                        title: "カロリー",
                        unit: "kcal",
                        range: 0...10_000,
                        step: 1,
                        defaultValue: NutritionGoals.default.calories,
                        accessibilityIdentifier: "nutritionCalorieGoalField"
                    )
                    NumericTextInputControl(
                        text: $proteinGoalText,
                        title: "たんぱく質",
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.protein,
                        accessibilityIdentifier: "nutritionProteinGoalField"
                    )
                    NumericTextInputControl(
                        text: $fatGoalText,
                        title: "脂質",
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.fat,
                        accessibilityIdentifier: "nutritionFatGoalField"
                    )
                    NumericTextInputControl(
                        text: $carbsGoalText,
                        title: "炭水化物",
                        unit: "g",
                        range: 0...2_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.carbs,
                        accessibilityIdentifier: "nutritionCarbsGoalField"
                    )
                    NumericTextInputControl(
                        text: $mealCountGoalText,
                        title: "食事回数",
                        unit: "回",
                        range: 1...12,
                        step: 1,
                        defaultValue: Double(NutritionGoals.default.mealCount),
                        accessibilityIdentifier: "nutritionMealCountGoalField"
                    )
                } header: {
                    Text("1日の食事目標")
                } footer: {
                    Text("食事回数の達成と、カロリー・PFCの達成を別々に表示します。")
                }

                Section("表示") {
                    ForEach(AppColorTheme.allCases) { theme in
                        Button {
                            appearanceDraft.colorTheme = theme
                        } label: {
                            ThemeOptionRow(
                                theme: theme,
                                isSelected: appearanceDraft.colorTheme == theme
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("themeOption-\(theme.rawValue)")
                        .accessibilityValue(appearanceDraft.colorTheme == theme ? "選択中" : "未選択")
                    }

                    Picker("表示モード", selection: $appearanceDraft.mode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearanceModePicker")

                    Picker("重量単位", selection: $draft.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Apple Healthワークアウト", isOn: $sensorDraft.healthIntegrationEnabled)
                        .disabled(healthDataManager.accessState == .unavailable)
                    Toggle("Watchで動作回数を推定", isOn: $sensorDraft.motionRepDetectionEnabled)
                    Toggle("心拍とRPEで休憩を調整", isOn: $sensorDraft.adaptiveRestEnabled)
                    Toggle("Watchの触覚通知", isOn: $sensorDraft.hapticCoachingEnabled)
                    Toggle("省電力サンプリング", isOn: $sensorDraft.reducedSensorSamplingEnabled)
                    Toggle("ジム訪問を自動記録", isOn: $sensorDraft.gymVisitDetectionEnabled)

                    Button {
                        Task { await healthDataManager.requestAuthorization() }
                    } label: {
                        Label("Healthの共有項目を確認", systemImage: "heart.text.square")
                    }
                    .disabled(!sensorDraft.healthIntegrationEnabled)
                    .accessibilityIdentifier("requestHealthFromSettingsButton")
                } header: {
                    Text("Apple Watch・センサー")
                } footer: {
                    Text("センサーが使えない場合も、重量・回数・RPEは手入力で記録できます。省電力サンプリングでは動作推定の更新頻度を下げます。")
                }

                Section {
                    Toggle("AI機能を使う", isOn: $aiDraft.isEnabled)

                    DisclosureGroup("AIへ送るデータ", isExpanded: $isAISharingExpanded) {
                        Toggle("身体KPI", isOn: $aiDraft.dataSharing.bodyMetrics)
                        Toggle("食事", isOn: $aiDraft.dataSharing.meals)
                        Toggle("筋トレ", isOn: $aiDraft.dataSharing.workouts)
                        Toggle("体型写真", isOn: $aiDraft.dataSharing.bodyPhotos)
                        Toggle("睡眠・回復", isOn: $aiDraft.dataSharing.sleepAndRecovery)
                        Toggle("日常活動", isOn: $aiDraft.dataSharing.dailyActivity)
                        Toggle("ジム訪問", isOn: $aiDraft.dataSharing.gymVisits)
                        Toggle("心拍・モーション", isOn: $aiDraft.dataSharing.workoutSensors)
                    }
                    .disabled(!aiDraft.isEnabled)

                    Text("現在選択: \(aiDraft.dataSharing.enabledCategoryNames.joined(separator: "、").ifEmpty("なし"))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    TextField("サーバーURL", text: $aiDraft.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("aiBaseURLField")

                    SecureField("APIキー", text: $aiDraft.apiKey)
                        .textInputAutocapitalization(.never)

                    Toggle("端末ごとの短期認証を使う", isOn: $aiDraft.usesSessionTokens)
                        .disabled(!aiDraft.isEnabled)

                    if aiDraft.usesSessionTokens {
                        Label(
                            "APIキーは短期トークンの取得だけに使い、通常のAI通信には送信しません。",
                            systemImage: "lock.shield"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    }

                    Button {
                        aiDraft.baseURLString = AISettings.default.baseURLString
                        aiDraft.apiKey = AISettings.default.apiKey
                        aiDraft.usesSessionTokens = AISettings.default.usesSessionTokens
                        aiDraft.isEnabled = AISettings.default.isEnabled
                        aiConnectionResult = nil
                    } label: {
                        Label(
                            AISettings.hasBundledConfiguration ? "配布時のAI設定を読み込む" : "AI設定を初期値に戻す",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .accessibilityIdentifier("resetAISettingsToSimulatorButton")

                    Button {
                        checkAIHealth()
                    } label: {
                        Label(isCheckingAI ? "確認中" : "接続確認", systemImage: "network")
                    }
                    .disabled(isCheckingAI || !aiDraft.isEnabled)
                    .accessibilityIdentifier("checkAIHealthButton")

                    if let aiConnectionResult {
                        AIConnectionCheckCard(result: aiConnectionResult)
                    }
                } header: {
                    Text("AIサーバー")
                } footer: {
                    Text(AISettings.configurationHelp)
                }

                LegalAndSupportSettingsSection()

                AdvertisingSettingsSection()

                Section("ヘルプ") {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .startBodyModeAppTour, object: nil)
                        }
                    } label: {
                        Label("画面ツアーを開始", systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("startAppTourButton")
                }

                Section {
                    Toggle("利用分析に協力", isOn: $usageAnalyticsEnabled)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("usageAnalyticsToggle")
                        .onChange(of: usageAnalyticsEnabled) { _, isEnabled in
                            UsageAnalytics.shared.setCollectionEnabled(isEnabled)
                        }

                    Button {
                        usageAnalyticsDocument = DiagnosticLogDocument(data: UsageAnalytics.shared.exportData())
                        isExportingUsageAnalytics = true
                    } label: {
                        Label("利用状況を書き出す", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportUsageAnalyticsButton")

                    Button(role: .destructive) {
                        UsageAnalytics.shared.deleteData()
                    } label: {
                        Label("利用状況を削除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteUsageAnalyticsButton")
                } header: {
                    Text("プライバシー")
                } footer: {
                    Text("使った機能の種類だけを端末内に保存します。体重、写真、食事内容、心拍、位置、メモは記録せず、自動送信もしません。")
                }

                Section {
                    LabeledContent {
                        Text("\(AppDiagnostics.shared.eventCount(categoryPrefix: "watch."))件")
                            .foregroundStyle(AppTheme.mutedInk)
                    } label: {
                        Label("Apple Watchログ", systemImage: "applewatch")
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label("全記録をJSONで書き出す", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportAllDataButton")

                    Button {
                        diagnosticDocument = DiagnosticLogDocument(data: AppDiagnostics.shared.exportData())
                        isExportingDiagnostics = true
                    } label: {
                        Label("診断ログを書き出す", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("exportDiagnosticsButton")

                    Button {
                        prepareDiagnosticShare()
                    } label: {
                        Label("診断ログを送る", systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("shareDiagnosticsButton")

                    Button(role: .destructive) {
                        AppDiagnostics.shared.deleteData()
                    } label: {
                        Label("診断ログを削除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteDiagnosticsButton")

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("全データ削除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("resetAllDataButton")
                } header: {
                    Text("データ")
                } footer: {
                    Text("診断ログにはiPhoneとApple Watchの動作・通信・ワークアウト操作の記録が含まれます。外部へは自動送信されません。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier("saveProfileSettingsButton")
                }
            }
            .confirmationDialog("全データを削除しますか？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("全データ削除", role: .destructive) {
                    appStore.resetAllData()
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("計画、履歴、身体KPI、食事、写真、AI会話・記憶、カスタム種目を削除します。")
            }
            .fileExporter(
                isPresented: $isExportingData,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "bodymode-export"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $isExportingDiagnostics,
                document: diagnosticDocument,
                contentType: .json,
                defaultFilename: "bodymode-diagnostics"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $isExportingUsageAnalytics,
                document: usageAnalyticsDocument,
                contentType: .json,
                defaultFilename: "bodymode-usage-events"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .sheet(item: $diagnosticSharePayload) { payload in
                ActivityShareView(activityItems: [payload.url])
            }
            .alert("書き出せませんでした", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "不明なエラー")
            }
        }
    }

    private func save() {
        let previousProfile = appStore.userProfile
        draft.heightCm = Double(heightText)
        draft.birthYear = Int(birthYearText)
        draft.customOutcomeText = draft.customOutcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.weeklyTrainingDays = min(7, max(1, Int(weeklyTrainingDaysText) ?? 3))
        draft.preferredSessionMinutes = min(240, max(10, Int(preferredSessionMinutesText) ?? 60))
        draft.nutritionGoals = NutritionGoals(
            calories: Double(calorieGoalText.replacingOccurrences(of: ",", with: ".")) ?? NutritionGoals.default.calories,
            protein: Double(proteinGoalText.replacingOccurrences(of: ",", with: ".")) ?? NutritionGoals.default.protein,
            fat: Double(fatGoalText.replacingOccurrences(of: ",", with: ".")) ?? NutritionGoals.default.fat,
            carbs: Double(carbsGoalText.replacingOccurrences(of: ",", with: ".")) ?? NutritionGoals.default.carbs,
            mealCount: Int(Double(mealCountGoalText) ?? Double(NutritionGoals.default.mealCount))
        ).normalized()
        recordCoachSelectionChanges(from: previousProfile, to: draft)
        appStore.saveUserProfile(draft)
        if healthDataManager.accessState == .unavailable {
            sensorDraft.healthIntegrationEnabled = false
        }
        sensorDraft.includeSensorDataInAI = aiDraft.dataSharing.sleepAndRecovery
            || aiDraft.dataSharing.dailyActivity
            || aiDraft.dataSharing.gymVisits
            || aiDraft.dataSharing.workoutSensors
        appStore.saveAISettings(aiDraft)
        appStore.saveSensorSettings(sensorDraft)
        appStore.saveAppearanceSettings(appearanceDraft)
        if sensorDraft.gymVisitDetectionEnabled {
            gymLocationManager.enableBackgroundVisitDetection()
        } else {
            gymLocationManager.disableVisitDetection()
        }
        dismiss()
    }

    private func recordCoachSelectionChanges(from previous: UserProfile, to current: UserProfile) {
        var changedDimensions: [String] = []
        if previous.coachType != current.coachType { changedDimensions.append("expertise") }
        if previous.coachPersona != current.coachPersona { changedDimensions.append("persona") }
        if previous.coachingStyle != current.coachingStyle { changedDimensions.append("style") }

        changedDimensions.forEach {
            UsageAnalytics.shared.record(.coachSelectionChanged, dimension: $0)
        }

        let recommendedTypes = Set(CoachType.recommendations(for: current).map(\.coachType))
        if previous.coachType != current.coachType,
           recommendedTypes.contains(current.coachType) {
            UsageAnalytics.shared.record(
                .coachRecommendationAccepted,
                dimension: current.coachType.rawValue
            )
        }
    }

    private var focusMuscleSummary: String {
        let names = draft.focusMuscles.map(\.displayName)
        return names.isEmpty ? "指定なし" : names.joined(separator: "・")
    }

    private func toggleFocusMuscle(_ muscle: MuscleGroup) {
        if let index = draft.focusMuscles.firstIndex(of: muscle) {
            draft.focusMuscles.remove(at: index)
        } else if draft.focusMuscles.count < 3 {
            draft.focusMuscles.append(muscle)
        }
    }

    private func toggleEquipment(_ equipment: Equipment) {
        if let index = draft.availableEquipment.firstIndex(of: equipment) {
            guard draft.availableEquipment.count > 1 else { return }
            draft.availableEquipment.remove(at: index)
        } else {
            draft.availableEquipment.append(equipment)
            draft.availableEquipment = Equipment.allCases.filter(draft.availableEquipment.contains)
        }
    }

    private func checkAIHealth() {
        guard aiDraft.isEnabled else {
            aiConnectionResult = .disabled
            return
        }

        isCheckingAI = true
        aiConnectionResult = nil

        Task {
            do {
                let client = AIAPIClient(settings: aiDraft)
                async let healthRequest = client.health()
                async let coachesRequest = client.coaches()
                let (health, coaches) = try await (healthRequest, coachesRequest)
                await MainActor.run {
                    aiConnectionResult = .init(health: health, coaches: coaches)
                    isCheckingAI = false
                }
            } catch {
                await MainActor.run {
                    aiConnectionResult = .init(error: error)
                    isCheckingAI = false
                }
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = GymDataExportDocument(data: try appStore.makeExportData())
            isExportingData = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func prepareDiagnosticShare() {
        do {
            diagnosticSharePayload = DiagnosticSharePayload(
                url: try AppDiagnostics.shared.makeShareFile()
            )
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: AppColorTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array(AppTheme.previewSwatches(for: theme).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(AppTheme.ink.opacity(0.16), lineWidth: 1))
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(theme.shortCode)  \(theme.displayName)")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(theme.summary)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.mutedInk)
        }
        .contentShape(Rectangle())
    }
}

private struct CoachExpertiseSummary: View {
    let profile: CoachExpertiseProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("助言で重視する割合", systemImage: "chart.bar.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text("能力や資格の評価ではありません。回答で優先する観点を示します。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedInk)
                focusRow("筋肥大", value: profile.focus.hypertrophy)
                focusRow("体型改善", value: profile.focus.bodyRecomposition)
                focusRow("減量", value: profile.focus.fatLoss)
                focusRow("食事", value: profile.focus.nutrition)
                focusRow("動作", value: profile.focus.movement)
                focusRow("回復", value: profile.focus.recovery)
                focusRow("競技力", value: profile.focus.performance)
            }
            summaryGroup("向いている人", systemImage: "person.2.fill", items: profile.recommendedFor)
            summaryGroup("特に重視", systemImage: "scope", items: profile.topFocusAreas)
            summaryGroup("進め方", systemImage: "list.number", items: profile.approach)
            summaryGroup("できないこと", systemImage: "shield.lefthalf.filled", items: profile.boundaries)
        }
        .padding(.vertical, 6)
    }

    private func focusRow(_ label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 54, alignment: .leading)
            ProgressView(value: Double(value), total: 5)
                .tint(AppTheme.accent)
            Text("\(value)/5")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) / 5")
    }

    private func summaryGroup(_ title: String, systemImage: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private struct AIConnectionCheckResult {
    enum Level {
        case ready
        case warning
        case failure
    }

    var level: Level
    var title: String
    var detail: String
    var recovery: String?

    static let disabled = AIConnectionCheckResult(
        level: .warning,
        title: "AI機能はオフです",
        detail: "手動記録はこのまま使えます。",
        recovery: "AI下書きや週次コメントを使う場合は、AI機能をオンにしてから接続確認してください。"
    )

    init(level: Level, title: String, detail: String, recovery: String?) {
        self.level = level
        self.title = title
        self.detail = detail
        self.recovery = recovery
    }

    init(health: AIHealthResponse, coaches: [AICoachSummary]) {
        if health.isReady {
            self.init(
                level: .ready,
                title: "AIサーバー接続OK",
                detail: "\(health.model)を利用できます。コーチ \(coaches.count)種類を確認しました。",
                recovery: health.message
            )
        } else if health.calorieModelAvailable == false {
            self.init(
                level: .warning,
                title: "カロリー推定モデル準備中",
                detail: "APIサーバーは応答していますが、画像カロリー推定を利用できません。",
                recovery: health.message
            )
        } else if !health.ollamaReachable {
            self.init(
                level: .warning,
                title: "補助モデル未接続",
                detail: "APIサーバーは応答していますが、料理・レポートの補助モデルを利用できません。",
                recovery: health.message
            )
        } else {
            self.init(
                level: .warning,
                title: "AIモデル準備中",
                detail: "APIサーバーは応答していますが、必要なモデルを利用できません。",
                recovery: health.message
            )
        }
    }

    init(error: Error) {
        let presentation = AIClientError.presentation(for: error)
        self.init(
            level: .failure,
            title: presentation.message,
            detail: "AI下書きや週次コメントは実行できませんが、手動記録は保存できます。",
            recovery: presentation.recovery
        )
    }

    var tint: Color {
        switch level {
        case .ready: AppTheme.positive
        case .warning: AppTheme.orange
        case .failure: AppTheme.critical
        }
    }

    var systemImage: String {
        switch level {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }
}

private struct AIConnectionCheckCard: View {
    let result: AIConnectionCheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.title, systemImage: result.systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(result.tint)

            Text(result.detail)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink)

            if let recovery = result.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiConnectionResultCard")
    }
}

#Preview {
    ProfileSettingsView(profile: .default, aiSettings: .default, appearanceSettings: .default)
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
