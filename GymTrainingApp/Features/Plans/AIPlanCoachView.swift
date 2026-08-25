import SwiftUI

struct AIPlanExerciseDraft: Codable, Equatable {
    var exerciseName: String
    var sets: Int
    var reps: Int
    var weight: Double?
    var restSeconds: Int
    var targetRPE: Double?
    var concentricSeconds: Int?
    var eccentricSeconds: Int?
    var tempoBeatSpeed: Int?
    var alternativeExerciseNames: [String]?

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case sets
        case reps
        case weight
        case restSeconds = "rest_seconds"
        case targetRPE = "target_rpe"
        case concentricSeconds = "concentric_seconds"
        case eccentricSeconds = "eccentric_seconds"
        case tempoBeatSpeed = "tempo_beat_speed"
        case alternativeExerciseNames = "alternative_exercise_names"
    }
}

struct AITrainingPlanDraft: Codable, Equatable {
    var name: String
    var summary: String
    var exercises: [AIPlanExerciseDraft]
}

struct AITrainingPlanProposal: Equatable {
    var plan: TrainingPlan
    var summary: String
    var ignoredExerciseNames: [String]
    var evidence: [CoachEvidenceCitation] = []
    var evidenceStatus: CoachEvidenceStatus = .unavailable
}

enum AITrainingPlanDraftError: LocalizedError, Equatable {
    case invalidResponse
    case noUsableExercises

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.string("training.b2778f7f4f92", fallback: "AIの計画を読み取れませんでした。もう一度作成してください。")
        case .noUsableExercises:
            L10n.string("training.4b13f017ef21", fallback: "利用可能な種目が計画に含まれていませんでした。器具を見直して再作成してください。")
        }
    }
}

struct AITrainingPlanDraftParser {
    func parse(
        reply: String,
        availableExercises: [Exercise],
        existingPlan: TrainingPlan? = nil
    ) throws -> AITrainingPlanProposal {
        guard let data = jsonData(in: reply),
              let draft = try? JSONDecoder().decode(AITrainingPlanDraft.self, from: data) else {
            throw AITrainingPlanDraftError.invalidResponse
        }

        let exerciseLookup = Dictionary(
            availableExercises.map { ($0.name.normalizedExerciseName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingLookup = Dictionary(
            (existingPlan?.exercises ?? []).map { ($0.exercise.name.normalizedExerciseName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var usedNames: Set<String> = []
        var ignoredNames: [String] = []
        var planExercises: [PlanExercise] = []

        for item in draft.exercises.prefix(12) {
            let key = item.exerciseName.normalizedExerciseName
            guard !key.isEmpty,
                  usedNames.insert(key).inserted,
                  let exercise = exerciseLookup[key] else {
                if !item.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignoredNames.append(item.exerciseName)
                }
                continue
            }

            let existingExercise = existingLookup[key]
            let setCount = min(10, max(1, item.sets))
            let targetReps = min(100, max(1, item.reps))
            let fallbackWeight = existingExercise?.sets.first?.targetWeight
                ?? defaultWeight(for: exercise)
            let requestedWeight = item.weight ?? fallbackWeight
            let targetWeight = roundedWeight(
                min(exercise.weightInputRange.upperBound, max(exercise.weightInputRange.lowerBound, requestedWeight))
            )
            let restSeconds = roundedRestSeconds(item.restSeconds)
            let existingFirstSet = existingExercise?.sets.first
            let targetRPE = min(10, max(1, item.targetRPE ?? existingFirstSet?.targetRPE ?? 7))
            let concentricSeconds = min(10, max(1, item.concentricSeconds ?? existingFirstSet?.plannedConcentricSeconds ?? 1))
            let eccentricSeconds = min(10, max(1, item.eccentricSeconds ?? existingFirstSet?.plannedEccentricSeconds ?? 2))
            let tempoBeatSpeed = min(3, max(1, item.tempoBeatSpeed ?? existingFirstSet?.plannedTempoBeatSpeed ?? 1))
            let targets = (1...setCount).map { order in
                PlanSetTarget(
                    setOrder: order,
                    targetWeight: targetWeight,
                    targetReps: targetReps,
                    targetRPE: targetRPE,
                    plannedConcentricSeconds: concentricSeconds,
                    plannedEccentricSeconds: eccentricSeconds,
                    plannedTempoBeatSpeed: tempoBeatSpeed
                )
            }
            let requestedAlternatives = item.alternativeExerciseNames ?? []
            var alternativeIDs = requestedAlternatives.compactMap { name in
                exerciseLookup[name.normalizedExerciseName]
            }.filter { $0.id != exercise.id }.map(\.id)
            if alternativeIDs.isEmpty {
                alternativeIDs = existingExercise?.alternativeExerciseIDs ?? []
            }
            if alternativeIDs.isEmpty,
               let automaticAlternative = availableExercises.first(where: {
                   $0.id != exercise.id
                       && $0.primaryMuscle == exercise.primaryMuscle
                       && $0.equipment != exercise.equipment
               }) ?? availableExercises.first(where: {
                   $0.id != exercise.id && $0.primaryMuscle == exercise.primaryMuscle
               }) {
                alternativeIDs = [automaticAlternative.id]
            }
            var seenAlternativeIDs = Set<UUID>()
            alternativeIDs = alternativeIDs.filter { seenAlternativeIDs.insert($0).inserted }
            planExercises.append(
                PlanExercise(
                    exercise: exercise,
                    sortOrder: planExercises.count,
                    restSeconds: restSeconds,
                    sets: targets,
                    alternativeExerciseIDs: Array(alternativeIDs.prefix(3))
                )
            )
        }

        guard !planExercises.isEmpty else {
            throw AITrainingPlanDraftError.noUsableExercises
        }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TrainingPlan(
            id: existingPlan?.id ?? UUID(),
            name: trimmedName.isEmpty ? L10n.string("training.fadb3814b3dc", fallback: "AIコーチプラン") : String(trimmedName.prefix(40)),
            exercises: planExercises,
            createdAt: existingPlan?.createdAt ?? Date(),
            updatedAt: Date()
        )
        return AITrainingPlanProposal(
            plan: plan,
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            ignoredExerciseNames: ignoredNames
        )
    }

    private func jsonData(in reply: String) -> Data? {
        guard let firstBrace = reply.firstIndex(of: "{"),
              let lastBrace = reply.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        return String(reply[firstBrace...lastBrace]).data(using: .utf8)
    }

    private func defaultWeight(for exercise: Exercise) -> Double {
        if exercise.equipment == .bodyweight {
            return 0
        }
        return 20
    }

    private func roundedWeight(_ weight: Double) -> Double {
        (weight * 10).rounded() / 10
    }

    private func roundedRestSeconds(_ seconds: Int) -> Int {
        let clamped = min(600, max(5, seconds))
        return Int((Double(clamped) / 5).rounded()) * 5
    }
}

struct AITrainingPlanPromptBuilder {
    func makePrompt(
        profile: UserProfile,
        exercises: [Exercise],
        selectedEquipment: Set<Equipment>,
        request: String,
        currentPlan: TrainingPlan?
    ) -> String {
        let candidateLabels = exercises
            .filter { selectedEquipment.contains($0.equipment) }
            .map { "\($0.name)[\($0.primaryMuscle.displayName)/\($0.equipment.displayName)]" }
        var includedLabels: [String] = []
        var candidateCharacters = 0
        for label in candidateLabels where candidateCharacters + label.count + 1 <= 2_200 {
            includedLabels.append(label)
            candidateCharacters += label.count + 1
        }
        let allowedExercises = includedLabels.joined(separator: "、")
        let currentPlanText = String((currentPlan.map { plan in
            plan.exercises.map { item in
                let set = item.sets.first
                let rpe = set?.targetRPE.map { "RPE \($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? "RPE -"
                let tempo = if let up = set?.plannedConcentricSeconds,
                               let down = set?.plannedEccentricSeconds {
                    "テンポ \(up)-\(down)"
                } else {
                    "テンポ -"
                }
                return L10n.string("training.98e103d659e2", fallback: "{{value1}}: {{value2}}セット, {{value3}}kg, {{value4}}回, 休憩{{value5}}秒", values: [String(describing: item.exercise.name), String(describing: item.sets.count), String(describing: set?.targetWeight ?? 0), String(describing: set?.targetReps ?? 0), String(describing: item.restSeconds)]) + " / \(rpe) / \(tempo)"
            }.joined(separator: " / ")
        } ?? L10n.string("training.6e64eee654b8", fallback: "なし")).prefix(700))
        let specificRequest = String(
            request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        )
        let outcome = profile.outcomeStyle == .custom && !profile.customOutcomeText.isEmpty
            ? profile.customOutcomeText
            : profile.outcomeStyle.displayName

        return """
        [BODYMODE_PLAN_JSON]
        あなたはBodyModeの担当トレーナー\(profile.coachPersona.displayName)（\(profile.coachType.displayName)）です。
        話し方: \(profile.coachingStyle.promptDescription)
        指導方針: \(profile.coachType.expertiseProfile.promise)
        重視する領域: \(profile.coachType.expertiseProfile.topFocusAreas.joined(separator: "、"))
        ユーザーの記録と次の条件から、安全に編集できるトレーニング計画の下書きを1つ作成してください。

        目的: \(profile.goalType.displayName)
        目標像: \(outcome)
        重点部位: \(profile.focusMuscles.map(\.displayName).joined(separator: "、").ifEmpty(L10n.string("training.2dffe9ee162c", fallback: "指定なし")))
        経験: \(profile.experienceLevel.displayName)
        頻度と時間: 週\(profile.weeklyTrainingDays)日、1回\(profile.preferredSessionMinutes)分
        利用可能器具: \(selectedEquipment.sortedByDisplayOrder.map(\.displayName).joined(separator: "、"))
        ユーザーの希望: \(specificRequest.ifEmpty(L10n.string("training.0e7d62c179e0", fallback: "記録と目標から適切に判断")))
        現在の計画: \(currentPlanText)

        exercise_nameは次の候補と完全に同じ名前だけを使ってください:
        \(allowedExercises)

        JSON以外の文章やMarkdownは返さないでください。重量が判断できない場合はweightをnullにしてください。自重種目は0、アシスト付きチンニング・ディップスは補助重量をマイナスで表せます。target_rpeは1〜10、concentric_secondsとeccentric_secondsは1〜10、tempo_beat_speedは1〜3にしてください。alternative_exercise_namesは候補内から最大3件にしてください。
        {"name":L10n.string("training.29ef9e964c43", fallback: "計画名"),"summary":L10n.string("training.95a2d2eab80c", fallback: "提案理由を短く"),"exercises":[{"exercise_name":L10n.string("training.c6f3f3a298ad", fallback: "候補内の種目名"),"sets":3,"reps":10,"weight":20.0,"rest_seconds":90,"target_rpe":7,"concentric_seconds":1,"eccentric_seconds":2,"tempo_beat_speed":1,"alternative_exercise_names":[]}]}
        """
    }
}

enum AIPlanCoachLaunchMode: Equatable {
    case manual
    case automaticStart
    case automaticRevision
}

struct AIPlanCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    let startingPlan: TrainingPlan?
    let launchMode: AIPlanCoachLaunchMode
    let onApply: (TrainingPlan) -> Void
    let onStartOnce: ((TrainingPlan) -> Void)?
    let onSaveAsNew: ((TrainingPlan) -> Void)?
    let onDeclineRevision: (() -> Void)?
    let onRevisionDecision: ((AITrainingPlanProposal, Bool) -> Void)?

    @State private var selectedEquipment: Set<Equipment>
    @State private var isEquipmentExpanded = false
    @State private var requestText = ""
    @State private var proposal: AITrainingPlanProposal?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var creditAccessIssue: AICreditAccessIssue?
    @State private var memoryCandidates: [CoachMemoryCandidate] = []
    @State private var isReviewingMemories = false
    @State private var didRequestAutomaticPlan = false

    init(
        startingPlan: TrainingPlan? = nil,
        launchMode: AIPlanCoachLaunchMode = .manual,
        onStartOnce: ((TrainingPlan) -> Void)? = nil,
        onSaveAsNew: ((TrainingPlan) -> Void)? = nil,
        onDeclineRevision: (() -> Void)? = nil,
        onRevisionDecision: ((AITrainingPlanProposal, Bool) -> Void)? = nil,
        onApply: @escaping (TrainingPlan) -> Void
    ) {
        self.startingPlan = startingPlan
        self.launchMode = launchMode
        self.onStartOnce = onStartOnce
        self.onSaveAsNew = onSaveAsNew
        self.onDeclineRevision = onDeclineRevision
        self.onRevisionDecision = onRevisionDecision
        self.onApply = onApply
        _selectedEquipment = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                coachSection

                if let proposal {
                    proposalSection(proposal)
                    requestSection
                    equipmentSection
                } else if launchMode != .manual {
                    automaticPreparationSection
                } else {
                    equipmentSection
                    requestSection
                }

                if let errorMessage {
                    Section(L10n.string("training.97c1ea491f39", fallback: "エラー")) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.critical)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(startingPlan == nil ? L10n.string("training.3754e98d69a7", fallback: "{{value1}}と計画作成", values: [String(describing: appStore.userProfile.coachPersona.displayName)]) : L10n.string("training.6db8599d1a4e", fallback: "{{value1}}に相談", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.2ea27dba9b9a", fallback: "閉じる")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
            }
            .onAppear {
                if selectedEquipment.isEmpty {
                    selectedEquipment = Set(appStore.userProfile.availableEquipment)
                }
                requestAutomaticPlanIfNeeded()
            }
            .sheet(isPresented: $isReviewingMemories) {
                CoachMemoryCandidateReviewView(
                    candidates: memoryCandidates,
                    coachPersona: appStore.userProfile.coachPersona
                ) { approved in
                    approved.forEach(appStore.approveCoachMemory)
                }
            }
            .aiCreditRecoverySheet(
                issue: $creditAccessIssue,
                settings: appStore.aiSettings,
                onResolved: {
                    await MainActor.run {
                        errorMessage = nil
                        generatePlan()
                    }
                }
            )
        }
    }

    private var coachSection: some View {
        Section(L10n.string("training.4dc9770fdb02", fallback: "担当コーチ")) {
            CoachIdentityView(
                persona: appStore.userProfile.coachPersona,
                role: appStore.userProfile.coachType.displayName,
                detail: L10n.string("training.82f49e5f2763", fallback: "{{value1}}・{{value2}}", values: [String(describing: appStore.userProfile.goalType.displayName), String(describing: appStore.userProfile.outcomeStyle.displayName)]),
                avatarSize: 64
            )
            .accessibilityIdentifier("aiPlanCoachIdentity")

            LabeledContent(L10n.string("training.4f40a3e174d3", fallback: "目安"), value: L10n.string("training.f1bec92b6943", fallback: "週{{value1}}日・{{value2}}分", values: [String(describing: appStore.userProfile.weeklyTrainingDays), String(describing: appStore.userProfile.preferredSessionMinutes)]))
        }
    }

    private var automaticPreparationSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("core_ui.99f0bdf9e0f1", fallback: "今日のメニューを準備しています"))
                        .font(.headline)
                    Text(L10n.string("core_ui.647335981a99", fallback: "目標、記録、使える器具から完成した内容を作成します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .accessibilityIdentifier("automaticAIPlanPreparation")
        }
    }

    private var equipmentSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isEquipmentExpanded) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Equipment.allCases) { equipment in
                        Button {
                            toggleEquipment(equipment)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: equipment.systemImage)
                                Text(equipment.displayName)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                                if selectedEquipment.contains(equipment) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedEquipment.contains(equipment) ? AppTheme.onAccent : AppTheme.ink)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selectedEquipment.contains(equipment) ? AppTheme.accent : AppTheme.cardBackground,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiPlanEquipment-\(equipment.rawValue)")
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label(L10n.string("training.0b8c05103896", fallback: "今回使える器具"), systemImage: "dumbbell")
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(L10n.string("training.396fd4f4d8fa", fallback: "{{value1}}種類", values: [String(describing: selectedEquipment.count)]))
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        } footer: {
            Text(L10n.string("training.7d2c88039500", fallback: "選択した器具に対応する登録済み種目だけをAIへ候補として渡します。"))
        }
    }

    private var requestSection: some View {
        Section {
            TextField(
                proposal == nil ? L10n.string("training.5ed33898a3d7", fallback: "例: 脚は軽め、胸を重点的に") : L10n.string("training.a1576054e4f1", fallback: "例: 種目を1つ減らして休憩を長く"),
                text: $requestText,
                axis: .vertical
            )
            .lineLimit(3...6)
            .accessibilityIdentifier("aiPlanRequestField")
        } header: {
            Text(proposal == nil ? L10n.string("training.f0d764cbc433", fallback: "コーチへの希望・任意") : L10n.string("training.d652983f98fd", fallback: "この計画をどう直す？"))
        }
    }

    private func proposalSection(_ proposal: AITrainingPlanProposal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(proposal.plan.name, systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Label(
                    L10n.string(
                        "training.41bc72cbabce",
                        fallback: "{{value1}}種目・{{value2}}セット・約{{value3}}分",
                        values: [
                            proposal.plan.exercises.count.formatted(),
                            proposal.plan.totalSetCount.formatted(),
                            proposal.plan.estimatedDurationMinutes.formatted()
                        ]
                    ),
                    systemImage: "clock"
                )
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
                if !proposal.summary.isEmpty {
                    Text(proposal.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineSpacing(3)
                }
            }

            ForEach(proposal.plan.exercises) { item in
                HStack(spacing: 11) {
                    Image(systemName: item.exercise.primaryMuscle.systemImage)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.exercise.name)
                            .font(.body.weight(.semibold))
                        if let first = item.sets.first {
                            Text(planExerciseSummary(item, firstSet: first))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        if let alternatives = item.alternativeExerciseIDs,
                           !alternatives.isEmpty {
                            Label(alternativeNames(for: alternatives), systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(AppTheme.mutedInk)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if launchMode == .automaticRevision,
               let startingPlan,
               !planRevisionDiffs(from: startingPlan, to: proposal.plan).isEmpty {
                DisclosureGroup(L10n.string("ai_plan.changes", fallback: "変更内容")) {
                    ForEach(planRevisionDiffs(from: startingPlan, to: proposal.plan), id: \.self) { difference in
                        Label(difference, systemImage: "arrow.right.circle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink)
                            .padding(.vertical, 2)
                    }
                }
                .accessibilityIdentifier("aiPlanRevisionDiffs")
            }

            if !proposal.ignoredExerciseNames.isEmpty {
                Label(
                    L10n.string("training.a0c8f6106c6b", fallback: "未登録のため除外: {{value1}}", values: [String(describing: proposal.ignoredExerciseNames.joined(separator: "、"))]),
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }

            if !proposal.evidence.isEmpty {
                DisclosureGroup(L10n.string("release_delta.evidence_count", fallback: "科学的根拠 {{value1}}件", values: [proposal.evidence.count.formatted()])) {
                    ForEach(proposal.evidence) { citation in
                        CoachEvidenceCitationRow(citation: citation)
                            .padding(.vertical, 4)
                    }
                }
            } else {
                Label(
                    proposal.evidenceStatus.state == "ready"
                        ? L10n.string("release_delta.no_direct_evidence", fallback: "この提案に直接使える根拠は見つかりませんでした")
                        : L10n.string("release_delta.evidence_unavailable", fallback: "科学的根拠を確認できないため、記録と一般原則を中心に提案しています"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.warning)
            }
        } header: {
            Text(L10n.string("training.859660768503", fallback: "{{value1}}の下書き", values: [String(describing: appStore.userProfile.coachPersona.displayName)]))
        } footer: {
            Text(
                launchMode == .automaticStart
                    ? L10n.string("ai_plan.try_or_save", fallback: "このまま一度だけ試すか、計画として保存できます。")
                    : L10n.string("training.e1b8fd383091", fallback: "次の画面で重量・回数・種目を確認してから保存します。")
            )
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        VStack(spacing: 8) {
            if proposal == nil || errorMessage != nil {
                AICreditCostStatusView(feature: "plan_generation", settings: appStore.aiSettings)
                    .padding(.horizontal)
            }

            if launchMode == .automaticRevision,
               let proposal,
               onRevisionDecision != nil || onSaveAsNew != nil {
                revisionDecisionActions(proposal, onSaveAsNew: onSaveAsNew)
            } else if launchMode == .automaticStart, let proposal, let onStartOnce {
                VStack(spacing: 8) {
                    Button {
                        onStartOnce(proposal.plan)
                        dismiss()
                    } label: {
                        Label(
                            L10n.string("ai_plan.start_once", fallback: "今回だけ実行"),
                            systemImage: "play.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                    .accessibilityIdentifier("startAIPlanOnceButton")

                    HStack(spacing: 10) {
                        revisionButton

                        Button {
                            onApply(proposal.plan)
                            dismiss()
                        } label: {
                            Label(
                                L10n.string("ai_plan.save_and_start", fallback: "保存して開始"),
                                systemImage: "bookmark.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)
                        .accessibilityIdentifier("saveAndStartAIPlanButton")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(AppTheme.elevatedBackground)
            } else {
                defaultBottomActions
            }
        }
        .background(AppTheme.elevatedBackground)
    }

    private func revisionDecisionActions(
        _ proposal: AITrainingPlanProposal,
        onSaveAsNew: ((TrainingPlan) -> Void)?
    ) -> some View {
        VStack(spacing: 8) {
            Button {
                if let onRevisionDecision {
                    onRevisionDecision(proposal, false)
                } else {
                    onApply(proposal.plan)
                }
                dismiss()
            } label: {
                Label(
                    L10n.string("ai_plan.update_current_plan", fallback: "既存計画を更新"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
            .accessibilityIdentifier("updateExistingAIPlanButton")

            HStack(spacing: 10) {
                Button {
                    if let onRevisionDecision {
                        onRevisionDecision(proposal, true)
                    } else {
                        onSaveAsNew?(proposal.plan)
                    }
                    dismiss()
                } label: {
                    Label(
                        L10n.string("ai_plan.save_as_new_plan", fallback: "新しい計画にする"),
                        systemImage: "plus.square.on.square"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
                .accessibilityIdentifier("saveRevisionAsNewPlanButton")

                Button {
                    onDeclineRevision?()
                    dismiss()
                } label: {
                    Text(L10n.string("ai_plan.not_now", fallback: "今回は変更しない"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("declineAIPlanRevisionButton")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(AppTheme.elevatedBackground)
    }

    private var defaultBottomActions: some View {
        HStack(spacing: 10) {
            if launchMode == .manual || proposal != nil || errorMessage != nil {
                revisionButton
            } else if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.string("training.3cee319a5e3a", fallback: "計画を作る"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("automaticAIPlanProgress")
            }

            if let proposal {
                Button {
                    onApply(proposal.plan)
                    dismiss()
                } label: {
                    Label(
                        launchMode == .automaticStart
                            ? L10n.string("core_ui.bb8ea3c17233", fallback: "このメニューを開始")
                            : L10n.string("training.299456e922c2", fallback: "編集へ"),
                        systemImage: launchMode == .automaticStart ? "play.fill" : "slider.horizontal.3"
                    )
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                .accessibilityIdentifier("applyAIPlanButton")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(AppTheme.elevatedBackground)
    }

    private var revisionButton: some View {
        Button {
            generatePlan()
        } label: {
            Label(
                proposal == nil ? L10n.string("training.3cee319a5e3a", fallback: "計画を作る") : L10n.string("training.d73b5768f914", fallback: "相談して修正"),
                systemImage: proposal == nil ? "sparkles" : "arrow.triangle.2.circlepath"
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(isGenerating || selectedEquipment.isEmpty)
        .accessibilityIdentifier("generateAIPlanButton")
    }

    private func requestAutomaticPlanIfNeeded() {
        guard launchMode != .manual,
              !didRequestAutomaticPlan,
              proposal == nil,
              !selectedEquipment.isEmpty else { return }
        didRequestAutomaticPlan = true
        generatePlan()
    }

    private var availableExercises: [Exercise] {
        appStore.allExercises.filter { selectedEquipment.contains($0.equipment) }
    }

    private func toggleEquipment(_ equipment: Equipment) {
        if selectedEquipment.contains(equipment) {
            guard selectedEquipment.count > 1 else { return }
            selectedEquipment.remove(equipment)
        } else {
            selectedEquipment.insert(equipment)
        }
    }

    private func generatePlan() {
        guard !isGenerating, !availableExercises.isEmpty else { return }
        isGenerating = true
        errorMessage = nil

        let currentPlan = proposal?.plan ?? startingPlan
        let automaticRequest = launchMode == .automaticRevision
            ? L10n.string("ai_plan.automatic_revision_request", fallback: "直近の実績、達成率、RPE、回復状態を確認し、次回から実行しやすい計画へ具体的に調整してください。変更不要なら現在値を維持してください。")
            : ""
        let prompt = AITrainingPlanPromptBuilder().makePrompt(
            profile: appStore.userProfile,
            exercises: appStore.allExercises,
            selectedEquipment: selectedEquipment,
            request: requestText.ifEmpty(automaticRequest),
            currentPlan: currentPlan
        )
        let context = CoachContextBuilder().build(
            profile: appStore.userProfile,
            sharing: appStore.aiSettings.dataSharing,
            bodyMetrics: appStore.bodyMetricEntries,
            bodyMetricGoals: appStore.bodyMetricGoals,
            meals: appStore.mealEntries,
            bodyPhotos: appStore.bodyPhotoEntries,
            workouts: appStore.workoutHistory,
            gymVisits: appStore.gymVisits,
            subjectiveRecovery: appStore.subjectiveRecoveryEntries,
            healthSnapshot: healthDataManager.snapshot,
            recoveryHistory: healthDataManager.recoveryHistory,
            memories: appStore.coachMemories,
            insights: appStore.aiInsights,
            planRevisions: appStore.planRevisionProposals
        )
        let payload = CoachChatRequest(
            coachID: appStore.userProfile.coachType.rawValue,
            coach: AIRequestCoachContext(profile: appStore.userProfile),
            purpose: .planGeneration,
            message: String(prompt.prefix(CoachChatRequest.maximumMessageCharacters)),
            context: context,
            recentMessages: []
        )
        let transmission = AITransmissionRecord(
            purpose: L10n.string("training.e41498e34979", fallback: "{{value1}}・計画作成", values: [String(describing: appStore.userProfile.coachType.displayName)]),
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames + [L10n.string("training.891003bfa15c", fallback: "目標"), L10n.string("training.2ea97ad7fcee", fallback: "利用可能器具"), L10n.string("training.621fc28b71e5", fallback: "登録種目")],
            itemCount: context.itemCount + availableExercises.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let response = try await AIAPIClient(settings: appStore.aiSettings).chat(payload: payload)
                var parsed = try AITrainingPlanDraftParser().parse(
                    reply: response.reply,
                    availableExercises: availableExercises,
                    existingPlan: currentPlan
                )
                parsed.evidence = response.evidence
                parsed.evidenceStatus = response.evidenceStatus
                proposal = parsed
                requestText = ""
                appStore.updateAITransmission(id: transmission.id, status: .completed)
                let newCandidates = appStore.newCoachMemoryCandidates(response.memoryCandidates)
                if !newCandidates.isEmpty {
                    memoryCandidates = newCandidates
                    isReviewingMemories = true
                }
            } catch {
                appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                creditAccessIssue = AICreditAccessIssue(error: error)
                if launchMode == .automaticStart {
                    let fallbackPlan = appStore.makeBeginnerStarterPlan()
                    if fallbackPlan.exercises.isEmpty {
                        errorMessage = AIClientError.presentation(for: error).message
                    } else {
                        proposal = AITrainingPlanProposal(
                            plan: fallbackPlan,
                            summary: L10n.string(
                                "core_ui.79fac498bcc6",
                                fallback: "AIに接続できないため、端末内の目標と利用器具からメニューを用意しました。"
                            ),
                            ignoredExerciseNames: []
                        )
                        errorMessage = nil
                    }
                } else {
                    errorMessage = AIClientError.presentation(for: error).message
                }
            }
            isGenerating = false
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }

    private func planExerciseSummary(_ item: PlanExercise, firstSet: PlanSetTarget) -> String {
        var parts = [
            "\(item.sets.count)セット × \(firstSet.targetReps)回",
            "\(formatWeight(firstSet.targetWeight))kg"
        ]
        if let targetRPE = firstSet.targetRPE {
            parts.append("RPE \(targetRPE.formatted(.number.precision(.fractionLength(0...1))))")
        }
        if let up = firstSet.plannedConcentricSeconds,
           let down = firstSet.plannedEccentricSeconds {
            parts.append("テンポ \(up)-\(down)")
        }
        parts.append("休憩\(item.restSeconds)秒")
        return parts.joined(separator: "・")
    }

    private func alternativeNames(for ids: [UUID]) -> String {
        let names = ids.compactMap { id in appStore.allExercises.first(where: { $0.id == id })?.name }
        return names.joined(separator: "、")
    }

    private func planRevisionDiffs(from oldPlan: TrainingPlan, to newPlan: TrainingPlan) -> [String] {
        let oldByName = oldPlan.exercises.reduce(into: [String: PlanExercise]()) { result, exercise in
            result[exercise.exercise.name] = result[exercise.exercise.name] ?? exercise
        }
        let newByName = newPlan.exercises.reduce(into: [String: PlanExercise]()) { result, exercise in
            result[exercise.exercise.name] = result[exercise.exercise.name] ?? exercise
        }
        var differences: [String] = []

        for oldExercise in oldPlan.exercises where newByName[oldExercise.exercise.name] == nil {
            differences.append(L10n.string("ai_plan.diff_remove_exercise", fallback: "{{value1}}を外す", values: [oldExercise.exercise.name]))
        }
        for newExercise in newPlan.exercises {
            guard let oldExercise = oldByName[newExercise.exercise.name] else {
                differences.append(L10n.string("ai_plan.diff_add_exercise", fallback: "{{value1}}を追加", values: [newExercise.exercise.name]))
                continue
            }
            if oldExercise.sets.count != newExercise.sets.count {
                differences.append(L10n.string("ai_plan.diff_sets", fallback: "{{value1}}：{{value2}}→{{value3}}セット", values: [newExercise.exercise.name, oldExercise.sets.count.formatted(), newExercise.sets.count.formatted()]))
            }
            if let oldSet = oldExercise.sets.sorted(by: { $0.setOrder < $1.setOrder }).first,
               let newSet = newExercise.sets.sorted(by: { $0.setOrder < $1.setOrder }).first {
                if oldSet.targetWeight != newSet.targetWeight {
                    differences.append("\(newExercise.exercise.name)：\(formatWeight(oldSet.targetWeight))→\(formatWeight(newSet.targetWeight))kg")
                }
                if oldSet.targetReps != newSet.targetReps {
                    differences.append(L10n.string("ai_plan.diff_reps", fallback: "{{value1}}：{{value2}}→{{value3}}回", values: [newExercise.exercise.name, oldSet.targetReps.formatted(), newSet.targetReps.formatted()]))
                }
                if oldSet.targetRPE != newSet.targetRPE {
                    let oldRPE = oldSet.targetRPE.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "-"
                    let newRPE = newSet.targetRPE.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "-"
                    differences.append("\(newExercise.exercise.name)：RPE \(oldRPE)→\(newRPE)")
                }
            }
            if oldExercise.restSeconds != newExercise.restSeconds {
                differences.append(L10n.string("ai_plan.diff_rest", fallback: "{{value1}}：休憩{{value2}}→{{value3}}秒", values: [newExercise.exercise.name, oldExercise.restSeconds.formatted(), newExercise.restSeconds.formatted()]))
            }
        }
        return differences
    }
}

private extension String {
    var normalizedExerciseName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension Set where Element == Equipment {
    var sortedByDisplayOrder: [Equipment] {
        Equipment.allCases.filter(contains)
    }
}

#Preview {
    AIPlanCoachView { _ in }
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
