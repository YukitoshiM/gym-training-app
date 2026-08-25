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
    @State private var otherTrainingDaysText: String
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
    @State private var isPresentingAIEnrollment = false
    @State private var aiEnrollmentCode = ""
    @State private var languageDraft: String
    @State private var isDeletingAllData = false
    @AppStorage(BodyLengthUnit.storageKey) private var bodyLengthUnitRaw = BodyLengthUnit.defaultValue.rawValue
    @AppStorage(DailyRecommendationAICreditPolicy.automaticUseKey) private var automaticDailyAICreditUse = false

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
        _languageDraft = State(initialValue: AppLanguagePreference.selectedIdentifier)
        _usageAnalyticsEnabled = State(initialValue: UsageAnalytics.shared.isCollectionEnabled)
        _heightText = State(initialValue: profile.heightCm.map { String(format: "%.1f", $0) } ?? "")
        _birthYearText = State(initialValue: profile.birthYear.map(String.init) ?? "")
        _weeklyTrainingDaysText = State(initialValue: String(profile.weeklyTrainingDays))
        _preferredSessionMinutesText = State(initialValue: String(profile.preferredSessionMinutes))
        _calorieGoalText = State(initialValue: profile.nutritionGoals.calories.formatted(.number.precision(.fractionLength(0))))
        _proteinGoalText = State(initialValue: profile.nutritionGoals.protein.formatted(.number.precision(.fractionLength(0))))
        _fatGoalText = State(initialValue: profile.nutritionGoals.fat.formatted(.number.precision(.fractionLength(0))))
        _carbsGoalText = State(initialValue: profile.nutritionGoals.carbs.formatted(.number.precision(.fractionLength(0))))
        _mealCountGoalText = State(initialValue: String(profile.nutritionGoals.mealCount))
        _otherTrainingDaysText = State(initialValue: profile.healthIntake.otherTrainingDays.map(String.init) ?? "0")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("core_ui.e028f6ce70b7", fallback: "プロフィール")) {
                    Picker(L10n.string("core_ui.d63e2c6f601f", fallback: "目的"), selection: $draft.goalType) {
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
                        draft.healthIntake = draft.healthIntake.normalized(for: goal)
                    }

                    CoachRecommendationPicker(profile: $draft)

                    Picker(L10n.string("core_ui.3e6334ceae9a", fallback: "すべての担当"), selection: $draft.coachType) {
                        ForEach(CoachType.allCases) { coach in
                            Text(coach.displayName).tag(coach)
                        }
                    }
                    .onChange(of: draft.coachType) { _, coachType in
                        draft.coachPersona = draft.coachPersona.replacement(for: coachType)
                        draft.coachingStyle = draft.coachPersona.recommendedStyle
                    }
                    .accessibilityIdentifier("coachTypePicker")

                    if draft.coachType != CoachType.recommended(for: draft.goalType) {
                        Button {
                            draft.coachType = CoachType.recommended(for: draft.goalType)
                            draft.coachPersona = draft.coachPersona.replacement(for: draft.coachType)
                            draft.coachingStyle = draft.coachPersona.recommendedStyle
                        } label: {
                            Label(L10n.string("core_ui.154071eaa53b", fallback: "おすすめの担当を適用"), systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("applyRecommendedCoachButton")
                    }

                    CoachPersonaPicker(
                        selection: $draft.coachPersona,
                        coachingStyle: $draft.coachingStyle,
                        coachType: draft.coachType
                    )

                    Picker(L10n.string("core_ui.247d52447f29", fallback: "話し方"), selection: $draft.coachingStyle) {
                        ForEach(CoachingStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("coachingStylePicker")

                    CoachAssignmentSummary(
                        persona: draft.coachPersona,
                        coachType: draft.coachType,
                        coachingStyle: draft.coachingStyle,
                        recommendationReason: CoachType.recommendationReason(for: draft)
                    )
                    .accessibilityIdentifier("coachCharacteristic")

                    DisclosureGroup(L10n.string("core_ui.46e1ee031bf8", fallback: "担当コーチの方針")) {
                        CoachExpertiseSummary(profile: draft.coachType.expertiseProfile)
                    }
                    .accessibilityIdentifier("coachExpertiseDetails")

                    NumericTextInputControl(
                        text: $heightText,
                        title: L10n.string("core_ui.ad1e9ee3c7de", fallback: "身長"),
                        unit: "cm",
                        range: 50...250,
                        step: 0.1,
                        defaultValue: 170,
                        accessibilityIdentifier: "profileHeightField"
                    )

                    NumericTextInputControl(
                        text: $birthYearText,
                        title: L10n.string("core_ui.11c5aab1badf", fallback: "生年"),
                        unit: L10n.string("core_ui.d1ce72ea5c2b", fallback: "年"),
                        range: 1900...Double(Calendar.current.component(.year, from: Date())),
                        step: 1,
                        defaultValue: Double(Calendar.current.component(.year, from: Date()) - 30),
                        accessibilityIdentifier: "profileBirthYearField"
                    )

                    Picker(L10n.string("core_ui.4ad24abc61b0", fallback: "性別"), selection: $draft.sex) {
                        ForEach(Sex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }

                    Picker(L10n.string("core_ui.8fd842ee7231", fallback: "経験レベル"), selection: $draft.experienceLevel) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                Section(L10n.string("core_ui.95b6839df407", fallback: "目標とペース")) {
                    Picker(L10n.string("core_ui.728b5580ef93", fallback: "目指すスタイル"), selection: $draft.outcomeStyle) {
                        ForEach(OutcomeStyle.available(for: draft.goalType)) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("outcomeStylePicker")

                    Text(draft.outcomeStyle.detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    if draft.outcomeStyle == .custom {
                        TextField(L10n.string("core_ui.a5075311a2c0", fallback: "目指したい状態"), text: $draft.customOutcomeText, axis: .vertical)
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
                            LabeledContent(L10n.string("core_ui.c0244b275a43", fallback: "重点部位"), value: focusMuscleSummary)
                        }
                        .accessibilityIdentifier("focusMuscleMenu")
                    }

                    NumericTextInputControl(
                        text: $weeklyTrainingDaysText,
                        title: L10n.string("core_ui.77ab8584d196", fallback: "週の回数"),
                        unit: L10n.string("core_ui.1b712ec8244d", fallback: "日"),
                        range: 1...7,
                        step: 1,
                        defaultValue: 3,
                        accessibilityIdentifier: "weeklyTrainingDaysField"
                    )

                    NumericTextInputControl(
                        text: $preferredSessionMinutesText,
                        title: L10n.string("core_ui.bed598542aad", fallback: "1回の時間"),
                        unit: L10n.string("core_ui.07bfafc15465", fallback: "分"),
                        range: 10...240,
                        step: 5,
                        defaultValue: 60,
                        accessibilityIdentifier: "preferredSessionMinutesField"
                    )
                }

                Section {
                    Picker(
                        AppLanguagePreference.bilingual(japanese: "運動習慣", english: "Current activity"),
                        selection: $draft.healthIntake.activityLevel
                    ) {
                        Text(AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered"))
                            .tag(ExerciseActivityLevel.notAnswered)
                        ForEach(ExerciseActivityLevel.allCases.filter { $0 != .notAnswered }) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    Picker(
                        AppLanguagePreference.bilingual(japanese: "予定強度", english: "Planned intensity"),
                        selection: $draft.healthIntake.plannedIntensity
                    ) {
                        Text(AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered"))
                            .tag(PlannedExerciseIntensity.notAnswered)
                        ForEach(PlannedExerciseIntensity.allCases.filter { $0 != .notAnswered }) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }

                    Picker(
                        AppLanguagePreference.bilingual(japanese: "ふだんの睡眠", english: "Typical sleep"),
                        selection: $draft.healthIntake.typicalSleep
                    ) {
                        Text(AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered"))
                            .tag(TypicalSleepRange.notAnswered)
                        ForEach(TypicalSleepRange.allCases.filter { $0 != .notAnswered }) { range in
                            Text(range.displayName).tag(range)
                        }
                    }

                    Picker(
                        AppLanguagePreference.bilingual(japanese: "配慮の有無", english: "Training considerations"),
                        selection: $draft.healthIntake.safetyStatus
                    ) {
                        Text(AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered"))
                            .tag(TrainingSafetyStatus.notAnswered)
                        ForEach(TrainingSafetyStatus.allCases.filter { $0 != .notAnswered }) { status in
                            Text(status.displayName).tag(status)
                        }
                    }

                    if draft.healthIntake.safetyStatus == .hasConsiderations
                        || draft.healthIntake.safetyStatus == .followsProfessionalGuidance {
                        ForEach(TrainingHealthConsideration.allCases) { consideration in
                            Button {
                                toggleHealthConsideration(consideration)
                            } label: {
                                Label(
                                    consideration.displayName,
                                    systemImage: draft.healthIntake.considerations.contains(consideration)
                                        ? "checkmark.square.fill"
                                        : "square"
                                )
                            }
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityAddTraits(
                                draft.healthIntake.considerations.contains(consideration) ? .isSelected : []
                            )
                        }

                        TextField(
                            AppLanguagePreference.bilingual(
                                japanese: "専門家の指示や避けたい動作・任意",
                                english: "Professional guidance or movements to avoid (optional)"
                            ),
                            text: $draft.healthIntake.note,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .onChange(of: draft.healthIntake.note) { _, value in
                            draft.healthIntake.note = String(value.prefix(300))
                        }
                    }

                    Picker(
                        AppLanguagePreference.bilingual(japanese: "優先すること", english: "Priority"),
                        selection: $draft.healthIntake.goalFocus
                    ) {
                        Text(AppLanguagePreference.bilingual(japanese: "未選択", english: "Not selected"))
                            .tag(GoalIntakeFocus.notAnswered)
                        ForEach(GoalIntakeFocus.options(for: draft.goalType)) { focus in
                            Text(focus.displayName).tag(focus)
                        }
                    }

                    if draft.goalType == .diet || draft.goalType == .bodyShape {
                        Picker(
                            AppLanguagePreference.bilingual(japanese: "食事助言", english: "Nutrition guidance"),
                            selection: $draft.healthIntake.nutritionGuidanceMode
                        ) {
                            Text(AppLanguagePreference.bilingual(japanese: "未回答", english: "Not answered"))
                                .tag(NutritionGuidanceMode.notAnswered)
                            ForEach(NutritionGuidanceMode.allCases.filter { $0 != .notAnswered }) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }

                    if draft.goalType == .performance {
                        TextField(
                            AppLanguagePreference.bilingual(
                                japanese: "競技・アクティビティ名",
                                english: "Sport or activity"
                            ),
                            text: $draft.healthIntake.sportOrActivity
                        )
                        .onChange(of: draft.healthIntake.sportOrActivity) { _, value in
                            draft.healthIntake.sportOrActivity = String(value.prefix(80))
                        }

                        NumericTextInputControl(
                            text: $otherTrainingDaysText,
                            title: AppLanguagePreference.bilingual(
                                japanese: "その他の練習・週",
                                english: "Other sessions/week"
                            ),
                            unit: AppLanguagePreference.bilingual(japanese: "回", english: "times"),
                            range: 0...14,
                            step: 1,
                            defaultValue: 0,
                            accessibilityIdentifier: "profileOtherTrainingDays"
                        )
                    }
                } header: {
                    Text(
                        AppLanguagePreference.bilingual(
                            japanese: "健康・運動ヒアリング",
                            english: "Health and activity intake"
                        )
                    )
                } footer: {
                    Text(
                        AppLanguagePreference.bilingual(
                            japanese: "診断ではなく、安全な負荷調整と目的別の提案に使います。専門家の指示がある場合はそちらを優先してください。",
                            english: "Used to tailor training load and goal-specific guidance, not to diagnose. Follow professional guidance first."
                        )
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
                    Text(L10n.string("core_ui.c1c9d8af06fa", fallback: "使える器具"))
                } footer: {
                    Text(L10n.string("core_ui.17c5baf0a5ab", fallback: "AIコーチは選択した器具だけでトレーニング計画を作ります。最低1つは選択されます。"))
                }

                Section {
                    NumericTextInputControl(
                        text: $calorieGoalText,
                        title: L10n.string("core_ui.3be34ee2e466", fallback: "カロリー"),
                        unit: "kcal",
                        range: 0...10_000,
                        step: 1,
                        defaultValue: NutritionGoals.default.calories,
                        accessibilityIdentifier: "nutritionCalorieGoalField"
                    )
                    NumericTextInputControl(
                        text: $proteinGoalText,
                        title: L10n.string("core_ui.6122ee8bbee3", fallback: "たんぱく質"),
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.protein,
                        accessibilityIdentifier: "nutritionProteinGoalField"
                    )
                    NumericTextInputControl(
                        text: $fatGoalText,
                        title: L10n.string("core_ui.66cd07bba953", fallback: "脂質"),
                        unit: "g",
                        range: 0...1_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.fat,
                        accessibilityIdentifier: "nutritionFatGoalField"
                    )
                    NumericTextInputControl(
                        text: $carbsGoalText,
                        title: L10n.string("core_ui.fa1f489c01a4", fallback: "炭水化物"),
                        unit: "g",
                        range: 0...2_000,
                        step: 0.1,
                        defaultValue: NutritionGoals.default.carbs,
                        accessibilityIdentifier: "nutritionCarbsGoalField"
                    )
                    NumericTextInputControl(
                        text: $mealCountGoalText,
                        title: L10n.string("core_ui.3871f0a40fbb", fallback: "食事回数"),
                        unit: L10n.string("core_ui.f894a2a47a50", fallback: "回"),
                        range: 1...12,
                        step: 1,
                        defaultValue: Double(NutritionGoals.default.mealCount),
                        accessibilityIdentifier: "nutritionMealCountGoalField"
                    )
                } header: {
                    Text(L10n.string("core_ui.79f4b3098d2f", fallback: "1日の食事目標"))
                } footer: {
                    Text(L10n.string("core_ui.e98cf07747d2", fallback: "食事回数の達成と、カロリー・PFCの達成を別々に表示します。"))
                }

                Section(L10n.string("core_ui.f34962367358", fallback: "表示")) {
                    Picker(AppLanguagePreference.languageLabel, selection: $languageDraft) {
                        Text(AppLanguagePreference.systemLabel)
                            .tag(AppLanguagePreference.systemIdentifier)
                        ForEach(AppLanguagePreference.supportedIdentifiers, id: \.self) { identifier in
                            Text(AppLanguagePreference.displayName(for: identifier))
                                .tag(identifier)
                        }
                    }
                    .accessibilityIdentifier("appLanguagePicker")

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
                        .accessibilityValue(appearanceDraft.colorTheme == theme ? L10n.string("core_ui.1588c48590fa", fallback: "選択中") : L10n.string("core_ui.b5bf4c52186f", fallback: "未選択"))
                    }

                    Picker(L10n.string("core_ui.9fdcbafcd96a", fallback: "表示モード"), selection: $appearanceDraft.mode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearanceModePicker")

                    Picker(L10n.string("core_ui.f1a5f69d86ba", fallback: "重量単位"), selection: $draft.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(L10n.string("release_delta.body_size_unit", fallback: "身体サイズ単位"), selection: $bodyLengthUnitRaw) {
                        ForEach(BodyLengthUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text(verbatim: "Apple Health (HealthKit)")
                        .font(.headline)

                    Toggle(L10n.string("core_ui.bfcdf42c1ed2", fallback: "Apple Healthワークアウト"), isOn: $sensorDraft.healthIntegrationEnabled)
                        .disabled(healthDataManager.accessState == .unavailable)
                    Toggle(L10n.string("core_ui.2dd0bb3c4033", fallback: "Watchで動作回数を推定"), isOn: $sensorDraft.motionRepDetectionEnabled)
                    Toggle(L10n.string("core_ui.82ae8bf04c79", fallback: "心拍とRPEで休憩を調整"), isOn: $sensorDraft.adaptiveRestEnabled)
                    Toggle(L10n.string("core_ui.0db9dbeb81f2", fallback: "Watchの触覚通知"), isOn: $sensorDraft.hapticCoachingEnabled)
                    Toggle(L10n.string("core_ui.b6d7339a72a5", fallback: "省電力サンプリング"), isOn: $sensorDraft.reducedSensorSamplingEnabled)
                    Toggle(L10n.string("core_ui.f904bbca161c", fallback: "ジム訪問を自動記録"), isOn: $sensorDraft.gymVisitDetectionEnabled)

                    Button {
                        Task { await healthDataManager.requestAuthorization() }
                    } label: {
                        Label(L10n.string("core_ui.a0332baa739d", fallback: "Healthの共有項目を確認"), systemImage: "heart.text.square")
                    }
                    .disabled(!sensorDraft.healthIntegrationEnabled)
                    .accessibilityIdentifier("requestHealthFromSettingsButton")
                } header: {
                    Text(verbatim: "Apple Health (HealthKit) & Apple Watch")
                } footer: {
                    Text(healthKitSettingsFooter)
                }

                aiConnectionSection

                LegalAndSupportSettingsSection()

                AdvertisingSettingsSection()

                Section(L10n.string("core_ui.88b5b95a568c", fallback: "ヘルプ")) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .startBodyModeAppTour, object: nil)
                        }
                    } label: {
                        Label(L10n.string("core_ui.eb51a9c91d64", fallback: "画面ツアーを開始"), systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("startAppTourButton")
                }

                Section {
                    Toggle(L10n.string("core_ui.9ddacc949085", fallback: "利用分析に協力"), isOn: $usageAnalyticsEnabled)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("usageAnalyticsToggle")
                        .onChange(of: usageAnalyticsEnabled) { _, isEnabled in
                            UsageAnalytics.shared.setCollectionEnabled(isEnabled)
                            guard isEnabled else { return }
                            UsageAnalytics.shared.record(.initialSetupCompleted)
                            if !appStore.workoutHistory.isEmpty {
                                UsageAnalytics.shared.record(.firstWorkoutCompleted)
                            }
                        }

                    Button {
                        usageAnalyticsDocument = DiagnosticLogDocument(data: UsageAnalytics.shared.exportData())
                        isExportingUsageAnalytics = true
                    } label: {
                        Label(L10n.string("core_ui.6de6ada9475e", fallback: "利用状況を書き出す"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportUsageAnalyticsButton")

                    Button(role: .destructive) {
                        UsageAnalytics.shared.deleteData()
                        Task {
                            try? await AIAPIClient(settings: appStore.aiSettings).deleteUsageEvents()
                        }
                    } label: {
                        Label(L10n.string("core_ui.96ca24057307", fallback: "利用状況を削除"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteUsageAnalyticsButton")
                } header: {
                    Text(L10n.string("core_ui.3ecafdb887da", fallback: "プライバシー"))
                } footer: {
                    Text(L10n.string(
                        "core_ui.analytics_privacy_explanation",
                        fallback: "同意時だけ、機能の利用状況と目的・経験・調子・提案カテゴリの区分を、氏名等と結び付けないインストール単位で送信します。身体や食事の数値、写真、心拍、睡眠時間、位置、メモ、広告IDは送りません。"
                    ))
                }

                Section {
                    LabeledContent {
                        Text(L10n.string("core_ui.af89edae43f1", fallback: "{{value1}}件", values: [String(describing: AppDiagnostics.shared.eventCount(categoryPrefix: "watch."))]))
                            .foregroundStyle(AppTheme.mutedInk)
                    } label: {
                        Label(L10n.string("core_ui.4bebd78efec8", fallback: "Apple Watchログ"), systemImage: "applewatch")
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label(L10n.string("core_ui.c0db37cbee38", fallback: "全記録をJSONで書き出す"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportAllDataButton")

                    NavigationLink {
                        DataImportView()
                    } label: {
                        Label("記録を取り込む", systemImage: "tray.and.arrow.down")
                    }
                    .accessibilityIdentifier("openDataImportButton")

                    NavigationLink {
                        DeletedRecordsView()
                    } label: {
                        Label(
                            L10n.string("core_ui.trash", fallback: "ゴミ箱"),
                            systemImage: "trash"
                        )
                    }
                    .badge(appStore.deletedRecords.count)
                    .accessibilityIdentifier("openDeletedRecordsButton")

                    Button {
                        diagnosticDocument = DiagnosticLogDocument(data: AppDiagnostics.shared.exportData())
                        isExportingDiagnostics = true
                    } label: {
                        Label(L10n.string("core_ui.3c4f04e77e6a", fallback: "診断ログを書き出す"), systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("exportDiagnosticsButton")

                    Button {
                        prepareDiagnosticShare()
                    } label: {
                        Label(L10n.string("core_ui.7de76d94979f", fallback: "診断ログを送る"), systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("shareDiagnosticsButton")

                    Button(role: .destructive) {
                        AppDiagnostics.shared.deleteData()
                    } label: {
                        Label(L10n.string("core_ui.b9422032c88b", fallback: "診断ログを削除"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteDiagnosticsButton")

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label(L10n.string("core_ui.b5f638ea3736", fallback: "全データ削除"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("resetAllDataButton")
                } header: {
                    Text(L10n.string("core_ui.2fa9d7bbabe7", fallback: "データ"))
                } footer: {
                    Text(L10n.string("core_ui.5f8bbdddc70b", fallback: "診断ログにはiPhoneとApple Watchの動作・通信・ワークアウト操作の記録が含まれます。外部へは自動送信されません。"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("core_ui.347a70f8f182", fallback: "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("core_ui.fa14b32474d2", fallback: "閉じる")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("core_ui.b3f9e7c55531", fallback: "保存")) {
                        save()
                    }
                    .accessibilityIdentifier("saveProfileSettingsButton")
                }
            }
            .confirmationDialog(L10n.string("core_ui.e29cb92d2b35", fallback: "全データを削除しますか？"), isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button(L10n.string("core_ui.b5f638ea3736", fallback: "全データ削除"), role: .destructive) {
                    Task { await deleteAllData() }
                }
                .disabled(isDeletingAllData)
                Button(L10n.string("core_ui.37a3754927b6", fallback: "キャンセル"), role: .cancel) {}
            } message: {
                Text(L10n.string("ai_credit.delete_warning", fallback: "端末内の全記録とBodyModeアカウントを削除します。残っている購入・特典クレジットも失われ、復元できません。"))
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
            .alert(L10n.string("core_ui.684a148ea1f5", fallback: "書き出せませんでした"), isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? L10n.string("core_ui.4662621ef14c", fallback: "不明なエラー"))
            }
        }
    }

    @MainActor
    private func deleteAllData() async {
        isDeletingAllData = true
        defer { isDeletingAllData = false }
        do {
            if SecureSettingsStore.hasAIAccount {
                _ = try await AIAPIClient(settings: appStore.aiSettings).deleteAccount()
            }
            appStore.resetAllData()
            dismiss()
        } catch {
            exportErrorMessage = AIClientError.presentation(for: error).message
        }
    }

    private var aiConnectionSection: some View {
        Section {
            Toggle(L10n.string("core_ui.70d26c237020", fallback: "AI機能を使う"), isOn: $aiDraft.isEnabled)
                .accessibilityIdentifier("aiEnabledToggle")

            Toggle(
                L10n.string(
                    "ai_credit.automatic_daily_credit_use",
                    fallback: "今日の提案をAIが自動確認"
                ),
                isOn: $automaticDailyAICreditUse
            )
            .disabled(!aiDraft.isEnabled)
            .accessibilityIdentifier("automaticDailyAICreditUseToggle")

            Text(
                automaticDailyAICreditUse
                    ? L10n.string(
                        "ai_credit.automatic_daily_credit_use_on",
                        fallback: "1日最大1回、日次補正の1クレジットを自動で消費します。"
                    )
                    : L10n.string(
                        "ai_credit.automatic_daily_credit_use_off",
                        fallback: "端末内の今日の提案は無料で使えます。AIクレジットは自動消費しません。"
                    )
            )
            .font(.footnote)
            .foregroundStyle(AppTheme.mutedInk)

            DisclosureGroup(L10n.string("core_ui.f2baffe4a974", fallback: "AIへ送るデータ"), isExpanded: $isAISharingExpanded) {
                Toggle(L10n.string("core_ui.8ec43439f302", fallback: "身体KPI"), isOn: $aiDraft.dataSharing.bodyMetrics)
                Toggle(L10n.string("core_ui.e8a52146d9dc", fallback: "食事"), isOn: $aiDraft.dataSharing.meals)
                Toggle(L10n.string("core_ui.536e51b3f816", fallback: "筋トレ"), isOn: $aiDraft.dataSharing.workouts)
                Toggle(L10n.string("core_ui.910d79f7cbf5", fallback: "体型写真"), isOn: $aiDraft.dataSharing.bodyPhotos)
                Toggle(L10n.string("core_ui.212ef44a8ffe", fallback: "睡眠・回復"), isOn: $aiDraft.dataSharing.sleepAndRecovery)
                Toggle(L10n.string("core_ui.214ff534b879", fallback: "日常活動"), isOn: $aiDraft.dataSharing.dailyActivity)
                Toggle(L10n.string("core_ui.42ff672ad87a", fallback: "ジム訪問"), isOn: $aiDraft.dataSharing.gymVisits)
                Toggle(L10n.string("core_ui.5263b86c134f", fallback: "心拍・モーション"), isOn: $aiDraft.dataSharing.workoutSensors)
                Toggle(
                    AppLanguagePreference.bilingual(
                        japanese: "運動上の配慮事項",
                        english: "Training considerations"
                    ),
                    isOn: $aiDraft.dataSharing.trainingConsiderations
                )
            }
            .disabled(!aiDraft.isEnabled)
            .accessibilityIdentifier("aiDataSharingDisclosure")

            Text(L10n.string("core_ui.6861aea5ee0c", fallback: "現在選択: {{value1}}", values: [String(describing: aiDraft.dataSharing.enabledCategoryNames.joined(separator: "、").ifEmpty("なし"))]))
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)

            aiConnectionControls

            Button {
                checkAIHealth()
            } label: {
                Label(isCheckingAI ? L10n.string("core_ui.271ef84863f9", fallback: "確認中") : L10n.string("core_ui.4116785260b6", fallback: "接続確認"), systemImage: "network")
            }
            .disabled(isCheckingAI || !aiDraft.isEnabled)
            .accessibilityIdentifier("checkAIHealthButton")

            if let aiConnectionResult {
                AIConnectionCheckCard(result: aiConnectionResult)
            }
        } header: {
            Text(L10n.string("core_ui.6867f20e988c", fallback: "AI接続"))
        } footer: {
            Text(AISettings.configurationHelp)
        }
    }

    @ViewBuilder
    private var aiConnectionControls: some View {
        if AISettings.allowsConnectionEditing {
            TextField(L10n.string("core_ui.5318d1ecf91a", fallback: "サーバーURL"), text: $aiDraft.baseURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("aiBaseURLField")

            SecureField(L10n.string("core_ui.04b0c641ffb6", fallback: "APIキー"), text: $aiDraft.apiKey)
                .textInputAutocapitalization(.never)

            Toggle(L10n.string("core_ui.3b78698aba6f", fallback: "端末ごとの短期認証を使う"), isOn: $aiDraft.usesSessionTokens)
                .disabled(!aiDraft.isEnabled)

            if aiDraft.usesSessionTokens {
                Label(
                    L10n.string("core_ui.4330553de90e", fallback: "APIキーは短期トークンの取得だけに使い、通常のAI通信には送信しません。"),
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
                    AISettings.hasBundledConfiguration ? L10n.string("core_ui.b9f3dd55ffff", fallback: "配布時のAI設定を読み込む") : L10n.string("core_ui.5d0ffa7e4b48", fallback: "AI設定を初期値に戻す"),
                    systemImage: "arrow.counterclockwise"
                )
            }
            .accessibilityIdentifier("resetAISettingsToSimulatorButton")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.string("core_ui.f2168633ea59", fallback: "BodyMode管理AI"), systemImage: "lock.shield")
                    Spacer()
                    Text(aiDraft.hasConfiguredConnection ? L10n.string("core_ui.f6c6bda43180", fallback: "設定済み") : L10n.string("core_ui.213dbf0be17e", fallback: "未設定"))
                        .foregroundStyle(aiDraft.hasConfiguredConnection ? AppTheme.positive : AppTheme.warning)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("aiManagedConnectionStatus")

                Button {
                    aiEnrollmentCode = ""
                    isPresentingAIEnrollment = true
                } label: {
                    Label("AI利用コードを登録", systemImage: "key")
                }
                .accessibilityIdentifier("registerAIEnrollmentCodeButton")
            }
            .sheet(isPresented: $isPresentingAIEnrollment) {
                aiEnrollmentSheet
            }
        }
    }

    private var aiEnrollmentSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("利用コード", text: $aiEnrollmentCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("aiEnrollmentCodeField")
                } footer: {
                    Text("発行されたコードがある場合だけ入力してください。接続先や認証情報は画面と診断ログに表示しません。")
                }
            }
            .navigationTitle("AI利用コード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("core_ui.37a3754927b6", fallback: "キャンセル")) {
                        isPresentingAIEnrollment = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("core_ui.b3f9e7c55531", fallback: "保存")) {
                        registerAIEnrollmentCode()
                    }
                    .disabled(normalizedAIEnrollmentCode.isEmpty)
                    .accessibilityIdentifier("saveAIEnrollmentCodeButton")
                }
            }
        }
    }

    private var normalizedAIEnrollmentCode: String {
        aiEnrollmentCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func registerAIEnrollmentCode() {
        let code = normalizedAIEnrollmentCode
        guard !code.isEmpty else { return }

        var updated = aiDraft
        if let bundled = AISettings.bundledConfiguration {
            updated.baseURLString = bundled.baseURLString
        }
        updated.apiKey = code
        updated.usesSessionTokens = true
        updated.isEnabled = true
        updated.managedConfigurationVersion = nil
        aiDraft = updated
        appStore.saveAISettings(updated)
        aiConnectionResult = nil
        aiEnrollmentCode = ""
        isPresentingAIEnrollment = false
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
        draft.healthIntake.otherTrainingDays = Int(otherTrainingDaysText)
        draft.healthIntake = draft.healthIntake.normalized(for: draft.goalType)
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
        UserDefaults.standard.set(languageDraft, forKey: AppLanguagePreference.storageKey)
        if sensorDraft.gymVisitDetectionEnabled {
            gymLocationManager.enableBackgroundVisitDetection()
        } else {
            gymLocationManager.disableVisitDetection()
        }
        dismiss()
    }

    private var healthKitSettingsFooter: String {
        let read = (Bundle.main.localizedInfoDictionary?["NSHealthShareUsageDescription"] as? String)
            ?? L10n.string("health_meals_body_ai.efb7ffef371a", fallback: "歩数、活動量、睡眠、心拍などをApple Healthから読み取ります。")
        let write = (Bundle.main.localizedInfoDictionary?["NSHealthUpdateUsageDescription"] as? String)
            ?? L10n.string("core_ui.a6e1ba4bb69f", fallback: "ワークアウトをApple Watchへ同期")
        let manual = L10n.string("core_ui.693f2367c5a9", fallback: "センサーが使えない場合も、重量・回数・RPEは手入力で記録できます。省電力サンプリングでは動作推定の更新頻度を下げます。")
        return [read, write, manual].joined(separator: "\n\n")
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

    private func toggleHealthConsideration(_ consideration: TrainingHealthConsideration) {
        if let index = draft.healthIntake.considerations.firstIndex(of: consideration) {
            draft.healthIntake.considerations.remove(at: index)
        } else {
            draft.healthIntake.considerations.append(consideration)
            draft.healthIntake.considerations = TrainingHealthConsideration.allCases.filter(
                draft.healthIntake.considerations.contains
            )
        }
    }

    private var focusMuscleSummary: String {
        let names = draft.focusMuscles.map(\.displayName)
        return names.isEmpty ? L10n.string("core_ui.4a384e48e5fa", fallback: "指定なし") : names.joined(separator: L10n.string("core_ui.3b67eb100838", fallback: "・"))
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
                Label(L10n.string("core_ui.8ed7116ddb59", fallback: "助言で重視する割合"), systemImage: "chart.bar.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(L10n.string("core_ui.4bf044eb7319", fallback: "能力や資格の評価ではありません。回答で優先する観点を示します。"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedInk)
                focusRow(L10n.string("core_ui.f0cee25fbea7", fallback: "筋肥大"), value: profile.focus.hypertrophy)
                focusRow(L10n.string("core_ui.e4890e3026c6", fallback: "体型改善"), value: profile.focus.bodyRecomposition)
                focusRow(L10n.string("core_ui.7d3eec40647b", fallback: "減量"), value: profile.focus.fatLoss)
                focusRow(L10n.string("core_ui.e8a52146d9dc", fallback: "食事"), value: profile.focus.nutrition)
                focusRow(L10n.string("core_ui.01123bc3cf73", fallback: "動作"), value: profile.focus.movement)
                focusRow(L10n.string("core_ui.06d6e4f2f426", fallback: "回復"), value: profile.focus.recovery)
                focusRow(L10n.string("core_ui.d5abaf673873", fallback: "競技力"), value: profile.focus.performance)
            }
            summaryGroup(L10n.string("core_ui.d357bb8bb46e", fallback: "向いている人"), systemImage: "person.2.fill", items: profile.recommendedFor)
            summaryGroup(L10n.string("core_ui.240039c19262", fallback: "特に重視"), systemImage: "scope", items: profile.topFocusAreas)
            summaryGroup(L10n.string("core_ui.905a5306693a", fallback: "進め方"), systemImage: "list.number", items: profile.approach)
            summaryGroup(L10n.string("core_ui.77e36dbf6362", fallback: "できないこと"), systemImage: "shield.lefthalf.filled", items: profile.boundaries)
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
        title: L10n.string("core_ui.774ed165f29d", fallback: "AI機能はオフです"),
        detail: L10n.string("core_ui.9e3593f0f682", fallback: "手動記録はこのまま使えます。"),
        recovery: L10n.string("core_ui.08b9d0492bce", fallback: "AI下書きや週次コメントを使う場合は、AI機能をオンにしてから接続確認してください。")
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
                title: L10n.string("core_ui.7d0a47df7889", fallback: "AIサーバー接続OK"),
                detail: L10n.string("core_ui.851b7f4f21fc", fallback: "{{value1}}を利用できます。コーチ {{value2}}種類を確認しました。", values: [String(describing: health.model), String(describing: coaches.count)]),
                recovery: health.message
            )
        } else if health.calorieModelAvailable == false {
            self.init(
                level: .warning,
                title: L10n.string("core_ui.d22be6e7aad2", fallback: "カロリー推定モデル準備中"),
                detail: L10n.string("core_ui.b0a2ce18faf2", fallback: "APIサーバーは応答していますが、画像カロリー推定を利用できません。"),
                recovery: health.message
            )
        } else if !health.ollamaReachable {
            self.init(
                level: .warning,
                title: L10n.string("core_ui.19b1ef380c77", fallback: "補助モデル未接続"),
                detail: L10n.string("core_ui.dcf81350e9e5", fallback: "APIサーバーは応答していますが、料理・レポートの補助モデルを利用できません。"),
                recovery: health.message
            )
        } else {
            self.init(
                level: .warning,
                title: L10n.string("core_ui.d48edde1fdc0", fallback: "AIモデル準備中"),
                detail: L10n.string("core_ui.0922a8545a63", fallback: "APIサーバーは応答していますが、必要なモデルを利用できません。"),
                recovery: health.message
            )
        }
    }

    init(error: Error) {
        let presentation = AIClientError.presentation(for: error)
        self.init(
            level: .failure,
            title: presentation.message,
            detail: L10n.string("core_ui.288a496c1f39", fallback: "AI下書きや週次コメントは実行できませんが、手動記録は保存できます。"),
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
