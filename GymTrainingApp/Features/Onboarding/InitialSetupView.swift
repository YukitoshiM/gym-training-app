import SwiftUI

struct InitialSetupView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var draft: UserProfile
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

    let onCompleted: () -> Void

    init(profile: UserProfile, onCompleted: @escaping () -> Void) {
        var normalizedProfile = profile
        if !OutcomeStyle.available(for: profile.goalType).contains(profile.outcomeStyle) {
            normalizedProfile.outcomeStyle = OutcomeStyle.recommended(for: profile.goalType)
        }
        _draft = State(initialValue: normalizedProfile)
        _customOutcomeText = State(initialValue: normalizedProfile.customOutcomeText)
        _weeklyTrainingDaysText = State(initialValue: String(normalizedProfile.weeklyTrainingDays))
        _preferredSessionMinutesText = State(initialValue: String(normalizedProfile.preferredSessionMinutes))
        _heightText = State(initialValue: normalizedProfile.heightCm.map {
            $0.formatted(.number.precision(.fractionLength(0...1)))
        } ?? "")
        _birthYearText = State(initialValue: normalizedProfile.birthYear.map(String.init) ?? "")
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
            AppIntroductionView()
        case .purpose:
            purposeStep
        case .pace:
            paceStep
        case .equipment:
            equipmentStep
        case .metrics:
            metricsStep
        }
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
                TextField("目指したい状態", text: $customOutcomeText, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .accessibilityIdentifier("setupCustomOutcomeField")
            }

            if draft.goalType.supportsFocusMuscles {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("重点部位")
                            .font(.title3.bold())
                        Spacer()
                        Text("最大3つ")
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
            SetupSection(title: "経験") {
                Picker("経験", selection: $draft.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setupExperiencePicker")
            }

            SetupSection(title: "続けられるペース") {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $weeklyTrainingDaysText,
                        title: "週の回数",
                        unit: "日",
                        range: 1...7,
                        step: 1,
                        defaultValue: 3,
                        accessibilityIdentifier: "setupWeeklyTrainingDays"
                    )

                    Divider()

                    NumericTextInputControl(
                        text: $preferredSessionMinutesText,
                        title: "1回の時間",
                        unit: "分",
                        range: 10...240,
                        step: 5,
                        defaultValue: 60,
                        accessibilityIdentifier: "setupSessionMinutes"
                    )
                }
            }

            SetupSection(title: "担当コーチ") {
                VStack(alignment: .leading, spacing: 12) {
                    CoachRecommendationPicker(profile: $draft)

                    Divider()

                    CoachPersonaPicker(selection: $draft.coachPersona)

                    Text("\(draft.coachPersona.displayName)・\(draft.coachType.displayName)")
                        .font(.subheadline.bold())
                    Text(draft.coachType.expertiseProfile.promise)
                        .font(.subheadline)
                    Text(CoachType.recommendationReason(for: draft))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)

                    Picker("話し方", selection: $draft.coachingStyle) {
                        ForEach(CoachingStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .accessibilityIdentifier("setupCoachingStylePicker")
                }
            }
        }
        .accessibilityIdentifier("initialSetupStep-pace")
    }

    private var equipmentStep: some View {
        SetupSection(title: "使える器具") {
            VStack(alignment: .leading, spacing: 10) {
                Text("通っているジムや自宅にあるものを選択")
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
            SetupSection(title: "基本情報・任意") {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $heightText,
                        title: "身長",
                        unit: "cm",
                        range: 50...250,
                        step: 0.1,
                        defaultValue: 170,
                        accessibilityIdentifier: "setupHeight"
                    )

                    Divider()

                    NumericTextInputControl(
                        text: $birthYearText,
                        title: "生年",
                        unit: "年",
                        range: 1900...Double(currentYear),
                        step: 1,
                        defaultValue: Double(currentYear - 30),
                        accessibilityIdentifier: "setupBirthYear"
                    )
                }
            }

            SetupSection(title: "性別・任意") {
                Picker("性別", selection: $draft.sex) {
                    ForEach(Sex.allCases) { sex in
                        Text(sex.displayName).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setupSexPicker")
            }

            SetupSection(title: "重量単位") {
                Picker("重量単位", selection: $draft.weightUnit) {
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
            SetupSection(title: "身長・任意") {
                NumericTextInputControl(
                    text: $heightText,
                    title: "現在",
                    unit: "cm",
                    range: 50...250,
                    step: 0.1,
                    defaultValue: 170,
                    accessibilityIdentifier: "setupHeight"
                )
            }

            SetupSection(title: "体重・任意") {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $currentWeightText,
                        title: "現在",
                        unit: "kg",
                        range: 20...400,
                        step: 0.1,
                        defaultValue: 70,
                        accessibilityIdentifier: "setupCurrentWeight"
                    )
                    Divider()
                    NumericTextInputControl(
                        text: $targetWeightText,
                        title: "目標",
                        unit: "kg",
                        range: 20...400,
                        step: 0.1,
                        defaultValue: 65,
                        accessibilityIdentifier: "setupTargetWeight"
                    )
                }
            }

            SetupSection(title: "腹囲・任意") {
                VStack(spacing: 14) {
                    NumericTextInputControl(
                        text: $currentWaistText,
                        title: "現在",
                        unit: "cm",
                        range: 30...250,
                        step: 0.1,
                        defaultValue: 80,
                        accessibilityIdentifier: "setupCurrentWaist"
                    )
                    Divider()
                    NumericTextInputControl(
                        text: $targetWaistText,
                        title: "目標",
                        unit: "cm",
                        range: 30...250,
                        step: 0.1,
                        defaultValue: 75,
                        accessibilityIdentifier: "setupTargetWaist"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("未入力の項目は、記録画面からあとで追加できます。", systemImage: "info.circle")
                Text("あとはBodyModeに任せてください。毎日、今日やることを最大3つ提案します。")
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
                    Label("戻る", systemImage: "chevron.left")
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("setupBackButton")
            }

            Button {
                moveForward()
            } label: {
                Label(
                    step == .metrics ? "BodyModeを始める" : "次へ",
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
        return true
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
        if CoachType.recommendations(for: draft).contains(where: { $0.coachType == draft.coachType }) {
            UsageAnalytics.shared.record(
                .coachRecommendationAccepted,
                dimension: draft.coachType.rawValue
            )
        }
        appStore.saveUserProfile(draft)

        saveMetric(kind: .bodyWeight, currentText: currentWeightText, targetText: targetWeightText, range: 20...400)
        saveMetric(kind: .waist, currentText: currentWaistText, targetText: targetWaistText, range: 30...250)
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
    case equipment
    case metrics

    var title: String {
        switch self {
        case .welcome: "理想の身体へ、迷わず進む。"
        case .purpose: "何を目指す？"
        case .pace: "週何回運動できる？"
        case .equipment: "利用できる器具は？"
        case .metrics: "現在の身体情報"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "最初に目標を決めたら、毎日やることは3つだけ"
        case .purpose: "最も近いものを1つ選択"
        case .pace: "無理のない回数と時間を設定"
        case .equipment: "使えるものだけでメニューを作ります"
        case .metrics: "変化を追いたい数値を設定"
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
        case .diet: "体重・腹囲を無理なく整える"
        case .muscleGain: "筋肉量とトレーニング実績を伸ばす"
        case .health: "運動・睡眠・食事の習慣を保つ"
        case .bodyShape: "写真・腹囲・部位バランスを整える"
        case .performance: "筋力・体力・回復を競技につなげる"
        }
    }

}

#Preview {
    InitialSetupView(profile: .default, onCompleted: {})
        .environmentObject(AppStore())
}
