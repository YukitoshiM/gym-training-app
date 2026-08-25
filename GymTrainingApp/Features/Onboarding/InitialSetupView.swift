import SwiftUI

struct InitialSetupView: View {
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguageIdentifier = AppLanguagePreference.systemIdentifier

    @State private var draft: UserProfile
    @State private var shareTrainingConsiderationsWithAI: Bool
    @State private var step: InitialSetupStep = .welcome
    @State private var customOutcomeText: String
    @State private var weeklyTrainingDaysText: String
    @State private var preferredSessionMinutesText: String
    @State private var heightText: String
    @State private var birthYearText: String
    @State private var currentWeightText = ""
    @State private var targetWeightText = ""
    @State private var currentWaistText = ""
    @State private var targetWaistText = ""
    @State private var otherTrainingDaysText: String

    let onCompleted: () -> Void

    init(
        profile: UserProfile,
        aiSettings: AISettings = .default,
        onCompleted: @escaping () -> Void
    ) {
        var normalizedProfile = profile
        if !OutcomeStyle.available(for: profile.goalType).contains(profile.outcomeStyle) {
            normalizedProfile.outcomeStyle = OutcomeStyle.recommended(for: profile.goalType)
        }
        _draft = State(initialValue: normalizedProfile)
        _shareTrainingConsiderationsWithAI = State(
            initialValue: aiSettings.dataSharing.trainingConsiderations
        )
        _customOutcomeText = State(initialValue: normalizedProfile.customOutcomeText)
        _weeklyTrainingDaysText = State(initialValue: String(normalizedProfile.weeklyTrainingDays))
        _preferredSessionMinutesText = State(initialValue: String(normalizedProfile.preferredSessionMinutes))
        _heightText = State(initialValue: normalizedProfile.heightCm.map {
            $0.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "")
        _birthYearText = State(initialValue: normalizedProfile.birthYear.map(String.init) ?? "")
        _otherTrainingDaysText = State(
            initialValue: normalizedProfile.healthIntake.otherTrainingDays.map(String.init) ?? "0"
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            setupHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(step.subtitle)
                            .font(.title3)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    stepContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .id(step)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            navigationBar
        }
    }

    private var setupHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("BodyMode")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(step.rawValue + 1) / \(InitialSetupStep.allCases.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.mutedInk)
            }

            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(InitialSetupStep.allCases.count)
            )
            .tint(AppTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(AppTheme.elevatedBackground)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .purpose:
            purposeStep
        case .pace:
            paceStep
        case .health:
            healthStep
        case .equipment:
            equipmentStep
        case .metrics:
            metricsStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupSection(title: AppLanguagePreference.languageLabel) {
                Picker(AppLanguagePreference.languageLabel, selection: $appLanguageIdentifier) {
                    Text(AppLanguagePreference.systemLabel)
                        .tag(AppLanguagePreference.systemIdentifier)
                    ForEach(AppLanguagePreference.supportedIdentifiers, id: \.self) { identifier in
                        Text(AppLanguagePreference.displayName(for: identifier))
                            .tag(identifier)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("setupLanguagePicker")

                Text(
                    AppLanguagePreference.bilingual(
                        japanese: "画面とAIコーチの返答言語に使います。",
                        english: "Used for both the app and AI coach responses."
                    )
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }

            AppIntroductionView()
        }
        .accessibilityIdentifier("initialSetupStep-welcome")
    }

    private var purposeStep: some View {
        LazyVStack(spacing: 10) {
            ForEach(GoalType.allCases) { goal in
                SetupOptionButton(
                    title: goal.displayName,
                    detail: goal.setupDescription,
                    systemImage: goal.systemImage,
                    isSelected: draft.goalType == goal
                ) {
                    selectGoal(goal)
                }
                .accessibilityIdentifier("setupGoal-\(goal.rawValue)")
            }
        }
        .accessibilityIdentifier("initialSetupStep-purpose")
    }

    private var outcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVStack(spacing: 10) {
                ForEach(OutcomeStyle.available(for: draft.goalType)) { style in
                    SetupOptionButton(
                        title: style.displayName,
                        detail: style.detail,
                        systemImage: style.systemImage,
                        isSelected: draft.outcomeStyle == style
                    ) {
                        draft.outcomeStyle = style
                    }
                    .accessibilityIdentifier("setupOutcome-\(style.rawValue)")
                }
            }

            if draft.outcomeStyle == .custom {
                TextField(L10n.string("core_ui.a5075311a2c0", fallback: "目指したい状態"), text: $customOutcomeText, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .accessibilityIdentifier("setupCustomOutcomeField")
            }

            if draft.goalType.supportsFocusMuscles {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.string("core_ui.c0244b275a43", fallback: "重点部位"))
                            .font(.title3.bold())
                        Spacer()
                        Text(L10n.string("core_ui.0f89f6f0b0b1", fallback: "最大3つ"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(MuscleGroup.focusSelectionCases) { muscle in
                            SetupMuscleButton(
                                muscle: muscle,
                                isSelected: draft.focusMuscles.contains(muscle),
                                isDisabled: draft.focusMuscles.count >= 3 && !draft.focusMuscles.contains(muscle)
                            ) {
                                toggleFocusMuscle(muscle)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("initialSetupStep-outcome")
    }

    private var paceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupSection(title: L10n.string("core_ui.ffd6cf1a85d3", fallback: "経験")) {
                Picker(L10n.string("core_ui.ffd6cf1a85d3", fallback: "経験"), selection: $draft.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setupExperiencePicker")
            }

            SetupSection(title: L10n.string("core_ui.781733d2b8b2", fallback: "続けられるペース")) {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $weeklyTrainingDaysText,
                        title: L10n.string("core_ui.77ab8584d196", fallback: "週の回数"),
                        unit: L10n.string("core_ui.1b712ec8244d", fallback: "日"),
                        range: 1...7,
                        step: 1,
                        defaultValue: 3,
                        accessibilityIdentifier: "setupWeeklyTrainingDays"
                    )

                    Divider()

                    NumericTextInputControl(
                        text: $preferredSessionMinutesText,
                        title: L10n.string("core_ui.bed598542aad", fallback: "1回の時間"),
                        unit: L10n.string("core_ui.07bfafc15465", fallback: "分"),
                        range: 10...240,
                        step: 5,
                        defaultValue: 60,
                        accessibilityIdentifier: "setupSessionMinutes"
                    )
                }
            }

            SetupSection(title: L10n.string("core_ui.a40e8863f052", fallback: "担当コーチ")) {
                VStack(alignment: .leading, spacing: 12) {
                    CoachRecommendationPicker(profile: $draft)

                    Divider()

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
                    .accessibilityIdentifier("setupCoachingStylePicker")

                    Divider()

                    CoachAssignmentSummary(
                        persona: draft.coachPersona,
                        coachType: draft.coachType,
                        coachingStyle: draft.coachingStyle,
                        recommendationReason: CoachType.recommendationReason(for: draft)
                    )
                }
            }
        }
        .accessibilityIdentifier("initialSetupStep-pace")
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                AppLanguagePreference.bilingual(
                    japanese: "約5分。運動前スクリーニングに基づく短い確認です。",
                    english: "About 5 minutes, using evidence-based pre-exercise screening."
                ),
                systemImage: "checklist"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.mutedInk)
            .accessibilityIdentifier("initialSetupStep-health")

            SetupSection(
                title: AppLanguagePreference.bilingual(
                    japanese: "現在の運動習慣",
                    english: "Current activity"
                )
            ) {
                LazyVStack(spacing: 8) {
                    ForEach(ExerciseActivityLevel.allCases.filter { $0 != .notAnswered }) { level in
                        SetupHealthChoiceButton(
                            title: level.displayName,
                            isSelected: draft.healthIntake.activityLevel == level
                        ) {
                            draft.healthIntake.activityLevel = level
                        }
                    }
                }
                .accessibilityIdentifier("setupActivityLevelPicker")
            }

            SetupSection(
                title: AppLanguagePreference.bilingual(
                    japanese: "予定する強度",
                    english: "Planned intensity"
                )
            ) {
                LazyVStack(spacing: 8) {
                    ForEach(PlannedExerciseIntensity.allCases.filter { $0 != .notAnswered }) { intensity in
                        SetupHealthChoiceButton(
                            title: intensity.displayName,
                            isSelected: draft.healthIntake.plannedIntensity == intensity
                        ) {
                            draft.healthIntake.plannedIntensity = intensity
                        }
                    }
                }
                .accessibilityIdentifier("setupPlannedIntensityPicker")
            }

            SetupSection(
                title: AppLanguagePreference.bilingual(
                    japanese: "運動上の配慮",
                    english: "Training considerations"
                )
            ) {
                Picker("", selection: $draft.healthIntake.safetyStatus) {
                    Text(
                        AppLanguagePreference.bilingual(japanese: "選択する", english: "Choose one")
                    )
                    .tag(TrainingSafetyStatus.notAnswered)
                    ForEach(TrainingSafetyStatus.allCases.filter { $0 != .notAnswered }) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("setupSafetyStatusPicker")

                if draft.healthIntake.safetyStatus == .hasConsiderations
                    || draft.healthIntake.safetyStatus == .followsProfessionalGuidance {
                    Divider()
                    LazyVStack(spacing: 8) {
                        ForEach(TrainingHealthConsideration.allCases) { consideration in
                            SetupHealthFlagButton(
                                title: consideration.displayName,
                                isSelected: draft.healthIntake.considerations.contains(consideration)
                            ) {
                                toggleHealthConsideration(consideration)
                            }
                        }
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
                    .accessibilityIdentifier("setupHealthNoteField")
                }
            }

            SetupSection(
                title: AppLanguagePreference.bilingual(
                    japanese: "ふだんの睡眠",
                    english: "Typical sleep"
                )
            ) {
                LazyVStack(spacing: 8) {
                    ForEach(TypicalSleepRange.allCases.filter { $0 != .notAnswered }) { range in
                        SetupHealthChoiceButton(
                            title: range.displayName,
                            isSelected: draft.healthIntake.typicalSleep == range
                        ) {
                            draft.healthIntake.typicalSleep = range
                        }
                    }
                }
                .accessibilityIdentifier("setupTypicalSleepChoices")
            }

            goalSpecificHealthSection

            SetupSection(
                title: AppLanguagePreference.bilingual(
                    japanese: "AIコーチでの利用",
                    english: "Use with AI coach"
                )
            ) {
                Toggle(
                    AppLanguagePreference.bilingual(
                        japanese: "運動上の配慮事項をAIに共有",
                        english: "Share training considerations with AI"
                    ),
                    isOn: $shareTrainingConsiderationsWithAI
                )
                .accessibilityIdentifier("setupShareTrainingConsiderationsToggle")

                Text(
                    AppLanguagePreference.bilingual(
                        japanese: "回答は端末に保存し、共有をオンにした場合だけAIの提案に含めます。",
                        english: "Answers stay on this device and are included in AI requests only when this is on."
                    )
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }

            Label(
                AppLanguagePreference.bilingual(
                    japanese: "BodyModeは診断を行いません。症状や専門家の指示がある場合は、そちらを優先してください。",
                    english: "BodyMode does not diagnose conditions. If you have symptoms or professional guidance, follow that guidance first."
                ),
                systemImage: "heart.text.square"
            )
            .font(.footnote)
            .foregroundStyle(AppTheme.mutedInk)
        }
    }

    @ViewBuilder
    private var goalSpecificHealthSection: some View {
        SetupSection(
            title: AppLanguagePreference.bilingual(
                japanese: "{{goal}}で優先すること".replacingOccurrences(of: "{{goal}}", with: draft.goalType.displayName),
                english: "Priority for \(draft.goalType.displayName)"
            )
        ) {
            LazyVStack(spacing: 8) {
                ForEach(GoalIntakeFocus.options(for: draft.goalType)) { focus in
                    SetupHealthChoiceButton(
                        title: focus.displayName,
                        isSelected: draft.healthIntake.goalFocus == focus
                    ) {
                        draft.healthIntake.goalFocus = focus
                    }
                }
            }
            .accessibilityIdentifier("setupGoalHealthFocusChoices")

            if draft.goalType == .diet || draft.goalType == .bodyShape {
                Divider()
                Text(
                    AppLanguagePreference.bilingual(
                        japanese: "食事助言の扱い",
                        english: "Nutrition guidance preference"
                    )
                )
                .font(.subheadline.weight(.semibold))
                Picker("", selection: $draft.healthIntake.nutritionGuidanceMode) {
                    ForEach(NutritionGuidanceMode.allCases.filter { $0 != .notAnswered }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("setupNutritionGuidanceModePicker")
            }

            if draft.goalType == .performance {
                Divider()
                TextField(
                    AppLanguagePreference.bilingual(
                        japanese: "競技・アクティビティ名・任意",
                        english: "Sport or activity (optional)"
                    ),
                    text: $draft.healthIntake.sportOrActivity
                )
                .onChange(of: draft.healthIntake.sportOrActivity) { _, value in
                    draft.healthIntake.sportOrActivity = String(value.prefix(80))
                }
                .accessibilityIdentifier("setupSportField")

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
                    accessibilityIdentifier: "setupOtherTrainingDays"
                )
            }
        }
    }

    private var equipmentStep: some View {
        SetupSection(title: L10n.string("core_ui.c1c9d8af06fa", fallback: "使える器具")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("core_ui.690f0b405af4", fallback: "通っているジムや自宅にあるものを選択"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(Equipment.allCases) { equipment in
                        SetupEquipmentButton(
                            equipment: equipment,
                            isSelected: draft.availableEquipment.contains(equipment)
                        ) {
                            toggleEquipment(equipment)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("initialSetupStep-equipment")
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupSection(title: L10n.string("core_ui.5fc716aa3fbf", fallback: "基本情報・任意")) {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $heightText,
                        title: L10n.string("core_ui.ad1e9ee3c7de", fallback: "身長"),
                        unit: "cm",
                        range: 50...250,
                        step: 0.1,
                        defaultValue: 170,
                        accessibilityIdentifier: "setupHeight"
                    )

                    Divider()

                    NumericTextInputControl(
                        text: $birthYearText,
                        title: L10n.string("core_ui.11c5aab1badf", fallback: "生年"),
                        unit: L10n.string("core_ui.d1ce72ea5c2b", fallback: "年"),
                        range: 1900...Double(currentYear),
                        step: 1,
                        defaultValue: Double(currentYear - 30),
                        accessibilityIdentifier: "setupBirthYear"
                    )
                }
            }

            SetupSection(title: L10n.string("core_ui.96465ca042cf", fallback: "性別・任意")) {
                Picker(L10n.string("core_ui.4ad24abc61b0", fallback: "性別"), selection: $draft.sex) {
                    ForEach(Sex.allCases) { sex in
                        Text(sex.displayName).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setupSexPicker")
            }

            SetupSection(title: L10n.string("core_ui.f1a5f69d86ba", fallback: "重量単位")) {
                Picker(L10n.string("core_ui.f1a5f69d86ba", fallback: "重量単位"), selection: $draft.weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setupWeightUnitPicker")
            }
        }
        .accessibilityIdentifier("initialSetupStep-profile")
    }

    private var metricsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupSection(title: L10n.string("core_ui.d2d277d3549f", fallback: "身長・任意")) {
                NumericTextInputControl(
                    text: $heightText,
                    title: L10n.string("core_ui.be12755005fc", fallback: "現在"),
                    unit: "cm",
                    range: 50...250,
                    step: 0.1,
                    defaultValue: 170,
                    accessibilityIdentifier: "setupHeight"
                )
            }

            SetupSection(title: L10n.string("core_ui.cada6d06bebb", fallback: "体重・任意")) {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $currentWeightText,
                        title: L10n.string("core_ui.be12755005fc", fallback: "現在"),
                        unit: "kg",
                        range: 20...400,
                        step: 0.1,
                        defaultValue: 70,
                        accessibilityIdentifier: "setupCurrentWeight"
                    )
                    Divider()
                    NumericTextInputControl(
                        text: $targetWeightText,
                        title: L10n.string("core_ui.8b91257ffe51", fallback: "目標"),
                        unit: "kg",
                        range: 20...400,
                        step: 0.1,
                        defaultValue: 65,
                        accessibilityIdentifier: "setupTargetWeight"
                    )
                }
            }

            SetupSection(title: L10n.string("core_ui.bcfa5445429a", fallback: "腹囲・任意")) {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $currentWaistText,
                        title: L10n.string("core_ui.be12755005fc", fallback: "現在"),
                        unit: "cm",
                        range: 30...250,
                        step: 0.1,
                        defaultValue: 80,
                        accessibilityIdentifier: "setupCurrentWaist"
                    )
                    Divider()
                    NumericTextInputControl(
                        text: $targetWaistText,
                        title: L10n.string("core_ui.8b91257ffe51", fallback: "目標"),
                        unit: "cm",
                        range: 30...250,
                        step: 0.1,
                        defaultValue: 75,
                        accessibilityIdentifier: "setupTargetWaist"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("core_ui.43babac56b38", fallback: "未入力の項目は、記録画面からあとで追加できます。"), systemImage: "info.circle")
                Text(L10n.string("core_ui.647335981a99", fallback: "あとはBodyModeに任せてください。毎日、今日やることを最大3つ提案します。"))
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityIdentifier("initialSetupStep-metrics")
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button {
                    moveBack()
                } label: {
                    Label(L10n.string("core_ui.789d7c369bcb", fallback: "戻る"), systemImage: "chevron.left")
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("setupBackButton")
            }

            Button {
                moveForward()
            } label: {
                Label(
                    step == .metrics ? L10n.string("core_ui.0a1dbd803991", fallback: "BodyModeを始める") : L10n.string("core_ui.d4d1fe3054d4", fallback: "次へ"),
                    systemImage: step == .metrics ? "checkmark" : "chevron.right"
                )
                .labelStyle(SetupForwardLabelStyle())
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canMoveForward)
            .accessibilityIdentifier(step == .metrics ? "setupFinishButton" : "setupContinueButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.elevatedBackground)
    }

    private var canMoveForward: Bool {
        switch step {
        case .health:
            let intake = draft.healthIntake
            let hasSelectedConsideration = intake.safetyStatus != .hasConsiderations
                || !intake.considerations.isEmpty
            let hasNutritionPreference = ![GoalType.diet, .bodyShape].contains(draft.goalType)
                || intake.nutritionGuidanceMode != .notAnswered
            return intake.activityLevel != .notAnswered
                && intake.plannedIntensity != .notAnswered
                && intake.safetyStatus != .notAnswered
                && intake.typicalSleep != .notAnswered
                && intake.goalFocus != .notAnswered
                && hasSelectedConsideration
                && hasNutritionPreference
        default:
            return true
        }
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func selectGoal(_ goal: GoalType) {
        draft.goalType = goal
        draft.coachType = CoachType.recommended(for: goal)
        draft.outcomeStyle = OutcomeStyle.recommended(for: goal)
        if !goal.supportsFocusMuscles {
            draft.focusMuscles = []
        }
        draft.healthIntake = draft.healthIntake.normalized(for: goal)
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

    private func moveBack() {
        guard let previous = InitialSetupStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func moveForward() {
        guard canMoveForward else { return }
        if let next = InitialSetupStep(rawValue: step.rawValue + 1) {
            step = next
        } else {
            completeSetup()
        }
    }

    private func completeSetup() {
        draft.customOutcomeText = customOutcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.weeklyTrainingDays = clampedInt(weeklyTrainingDaysText, fallback: 3, range: 1...7)
        draft.preferredSessionMinutes = clampedInt(preferredSessionMinutesText, fallback: 60, range: 10...240)
        draft.heightCm = optionalDouble(heightText, range: 50...250)
        draft.birthYear = optionalInt(birthYearText, range: 1900...currentYear)
        draft.healthIntake.otherTrainingDays = optionalInt(otherTrainingDaysText, range: 0...14)
        draft.healthIntake = draft.healthIntake.normalized(for: draft.goalType)
        if CoachType.recommendations(for: draft).contains(where: { $0.coachType == draft.coachType }) {
            UsageAnalytics.shared.record(
                .coachRecommendationAccepted,
                dimension: draft.coachType.rawValue
            )
        }
        appStore.saveUserProfile(draft)

        var updatedAISettings = appStore.aiSettings
        updatedAISettings.dataSharing.trainingConsiderations = shareTrainingConsiderationsWithAI
        appStore.saveAISettings(updatedAISettings)

        saveMetric(kind: .bodyWeight, currentText: currentWeightText, targetText: targetWeightText, range: 20...400)
        saveMetric(kind: .waist, currentText: currentWaistText, targetText: targetWaistText, range: 30...250)
        UsageAnalytics.shared.record(.initialSetupCompleted)
        onCompleted()
    }

    private func saveMetric(
        kind: BodyMetricKind,
        currentText: String,
        targetText: String,
        range: ClosedRange<Double>
    ) {
        let current = optionalDouble(currentText, range: range)
        let target = optionalDouble(targetText, range: range)

        if let current {
            appStore.saveBodyMetricEntry(BodyMetricEntry(kind: kind, value: current))
        }
        if let target {
            let direction: BodyMetricGoalDirection
            if let current {
                direction = target >= current ? .increase : .decrease
            } else if kind == .bodyWeight, draft.goalType == .muscleGain {
                direction = .increase
            } else {
                direction = .decrease
            }
            appStore.saveBodyMetricGoal(
                BodyMetricGoal(kind: kind, targetValue: target, direction: direction)
            )
        }
    }

    private func optionalDouble(_ text: String, range: ClosedRange<Double>) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private func optionalInt(_ text: String, range: ClosedRange<Int>) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let value = Int(normalized) else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private func clampedInt(_ text: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, Int(text) ?? fallback))
    }
}

private enum InitialSetupStep: Int, CaseIterable {
    case welcome
    case purpose
    case pace
    case health
    case equipment
    case metrics

    var title: String {
        switch self {
        case .welcome: L10n.string("core_ui.52709c47198c", fallback: "理想の身体へ、迷わず進む。")
        case .purpose: L10n.string("core_ui.117fe6f9d272", fallback: "何を目指す？")
        case .pace: L10n.string("core_ui.4f3a00976e8f", fallback: "週何回運動できる？")
        case .health: AppLanguagePreference.bilingual(japanese: "身体の状態を確認", english: "Your health and activity")
        case .equipment: L10n.string("core_ui.9d6adc8c71ef", fallback: "利用できる器具は？")
        case .metrics: L10n.string("core_ui.b156d426183c", fallback: "現在の身体情報")
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: L10n.string("core_ui.b02b7cafa79f", fallback: "最初に目標を決めたら、毎日やることは3つだけ")
        case .purpose: L10n.string("core_ui.d0ebd393995d", fallback: "最も近いものを1つ選択")
        case .pace: L10n.string("core_ui.738330e87b19", fallback: "無理のない回数と時間を設定")
        case .health: AppLanguagePreference.bilingual(japanese: "安全と目的に合わせて提案を調整", english: "Tailor recommendations to your safety and goal")
        case .equipment: L10n.string("core_ui.81cbef31388d", fallback: "使えるものだけでメニューを作ります")
        case .metrics: L10n.string("core_ui.d4fe0248b5c0", fallback: "変化を追いたい数値を設定")
        }
    }
}

private struct SetupOptionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        isSelected ? AppTheme.accent : AppTheme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.mutedInk)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.mutedInk.opacity(0.22), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetupMuscleButton: View {
    let muscle: MuscleGroup
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: muscle.systemImage)
                    .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.accent)
                Text(muscle.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSelected ? AppTheme.accent : AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityIdentifier("setupFocusMuscle-\(muscle.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetupEquipmentButton: View {
    let equipment: Equipment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: equipment.systemImage)
                    .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.accent)
                Text(equipment.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSelected ? AppTheme.accent : AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("setupEquipment-\(equipment.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetupHealthFlagButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.mutedInk)
                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("setupHealthConsideration-\(title)")
    }
}

private struct SetupHealthChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.mutedInk)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            content
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SetupForwardLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

private extension GoalType {
    var setupDescription: String {
        switch self {
        case .diet: L10n.string("core_ui.27e336fb0262", fallback: "体重・腹囲を無理なく整える")
        case .muscleGain: L10n.string("core_ui.48648d4ea8d7", fallback: "筋肉量とトレーニング実績を伸ばす")
        case .health: L10n.string("core_ui.ecd3571c4ca8", fallback: "運動・睡眠・食事の習慣を保つ")
        case .bodyShape: L10n.string("core_ui.bf6f2859521c", fallback: "写真・腹囲・部位バランスを整える")
        case .performance: L10n.string("core_ui.4cfa4f6e6a37", fallback: "筋力・体力・回復を競技につなげる")
        }
    }

}

#Preview {
    InitialSetupView(profile: .default, onCompleted: {})
        .environmentObject(AppStore())
}
