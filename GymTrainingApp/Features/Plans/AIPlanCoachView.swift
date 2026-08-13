import SwiftUI

struct AIPlanExerciseDraft: Codable, Equatable {
    var exerciseName: String
    var sets: Int
    var reps: Int
    var weight: Double?
    var restSeconds: Int

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case sets
        case reps
        case weight
        case restSeconds = "rest_seconds"
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
}

enum AITrainingPlanDraftError: LocalizedError, Equatable {
    case invalidResponse
    case noUsableExercises

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "AIの計画を読み取れませんでした。もう一度作成してください。"
        case .noUsableExercises:
            "利用可能な種目が計画に含まれていませんでした。器具を見直して再作成してください。"
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
            let targets = (1...setCount).map { order in
                PlanSetTarget(
                    setOrder: order,
                    targetWeight: targetWeight,
                    targetReps: targetReps
                )
            }
            planExercises.append(
                PlanExercise(
                    exercise: exercise,
                    sortOrder: planExercises.count,
                    restSeconds: restSeconds,
                    sets: targets
                )
            )
        }

        guard !planExercises.isEmpty else {
            throw AITrainingPlanDraftError.noUsableExercises
        }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TrainingPlan(
            id: existingPlan?.id ?? UUID(),
            name: trimmedName.isEmpty ? "AIコーチプラン" : String(trimmedName.prefix(40)),
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
                return "\(item.exercise.name): \(item.sets.count)セット, \(set?.targetWeight ?? 0)kg, \(set?.targetReps ?? 0)回, 休憩\(item.restSeconds)秒"
            }.joined(separator: " / ")
        } ?? "なし").prefix(700))
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
        重点部位: \(profile.focusMuscles.map(\.displayName).joined(separator: "、").ifEmpty("指定なし"))
        経験: \(profile.experienceLevel.displayName)
        頻度と時間: 週\(profile.weeklyTrainingDays)日、1回\(profile.preferredSessionMinutes)分
        利用可能器具: \(selectedEquipment.sortedByDisplayOrder.map(\.displayName).joined(separator: "、"))
        ユーザーの希望: \(specificRequest.ifEmpty("記録と目標から適切に判断"))
        現在の計画: \(currentPlanText)

        exercise_nameは次の候補と完全に同じ名前だけを使ってください:
        \(allowedExercises)

        JSON以外の文章やMarkdownは返さないでください。重量が判断できない場合はweightをnullにしてください。自重種目は0、アシスト付きチンニング・ディップスは補助重量をマイナスで表せます。
        {"name":"計画名","summary":"提案理由を短く","exercises":[{"exercise_name":"候補内の種目名","sets":3,"reps":10,"weight":20.0,"rest_seconds":90}]}
        """
    }
}

struct AIPlanCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    let startingPlan: TrainingPlan?
    let onApply: (TrainingPlan) -> Void

    @State private var selectedEquipment: Set<Equipment>
    @State private var isEquipmentExpanded = false
    @State private var requestText = ""
    @State private var proposal: AITrainingPlanProposal?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var memoryCandidates: [CoachMemoryCandidate] = []
    @State private var isReviewingMemories = false

    init(startingPlan: TrainingPlan? = nil, onApply: @escaping (TrainingPlan) -> Void) {
        self.startingPlan = startingPlan
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
                } else {
                    equipmentSection
                    requestSection
                }

                if let errorMessage {
                    Section("エラー") {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.critical)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(startingPlan == nil ? "\(appStore.userProfile.coachPersona.displayName)と計画作成" : "\(appStore.userProfile.coachPersona.displayName)に相談")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
            }
            .onAppear {
                if selectedEquipment.isEmpty {
                    selectedEquipment = Set(appStore.userProfile.availableEquipment)
                }
            }
            .sheet(isPresented: $isReviewingMemories) {
                CoachMemoryCandidateReviewView(
                    candidates: memoryCandidates,
                    coachPersona: appStore.userProfile.coachPersona
                ) { approved in
                    approved.forEach(appStore.approveCoachMemory)
                }
            }
        }
    }

    private var coachSection: some View {
        Section("担当コーチ") {
            CoachIdentityView(
                persona: appStore.userProfile.coachPersona,
                role: appStore.userProfile.coachType.displayName,
                detail: "\(appStore.userProfile.goalType.displayName)・\(appStore.userProfile.outcomeStyle.displayName)",
                avatarSize: 64
            )
            .accessibilityIdentifier("aiPlanCoachIdentity")

            LabeledContent("目安", value: "週\(appStore.userProfile.weeklyTrainingDays)日・\(appStore.userProfile.preferredSessionMinutes)分")
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
                    Label("今回使える器具", systemImage: "dumbbell")
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("\(selectedEquipment.count)種類")
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
        } footer: {
            Text("選択した器具に対応する登録済み種目だけをAIへ候補として渡します。")
        }
    }

    private var requestSection: some View {
        Section {
            TextField(
                proposal == nil ? "例: 脚は軽め、胸を重点的に" : "例: 種目を1つ減らして休憩を長く",
                text: $requestText,
                axis: .vertical
            )
            .lineLimit(3...6)
            .accessibilityIdentifier("aiPlanRequestField")
        } header: {
            Text(proposal == nil ? "コーチへの希望・任意" : "この計画をどう直す？")
        }
    }

    private func proposalSection(_ proposal: AITrainingPlanProposal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(proposal.plan.name, systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
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
                            Text("\(item.sets.count)セット × \(first.targetReps)回・\(formatWeight(first.targetWeight))kg・休憩\(item.restSeconds)秒")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                    }
                }
            }

            if !proposal.ignoredExerciseNames.isEmpty {
                Label(
                    "未登録のため除外: \(proposal.ignoredExerciseNames.joined(separator: "、"))",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
            }
        } header: {
            Text("\(appStore.userProfile.coachPersona.displayName)の下書き")
        } footer: {
            Text("次の画面で重量・回数・種目を確認してから保存します。")
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button {
                generatePlan()
            } label: {
                if isGenerating {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Label(
                        proposal == nil ? "計画を作る" : "相談して修正",
                        systemImage: proposal == nil ? "sparkles" : "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating || selectedEquipment.isEmpty)
            .accessibilityIdentifier("generateAIPlanButton")

            if let proposal {
                Button {
                    onApply(proposal.plan)
                    dismiss()
                } label: {
                    Label("編集へ", systemImage: "slider.horizontal.3")
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
        let prompt = AITrainingPlanPromptBuilder().makePrompt(
            profile: appStore.userProfile,
            exercises: appStore.allExercises,
            selectedEquipment: selectedEquipment,
            request: requestText,
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
            insights: appStore.aiInsights
        )
        let payload = CoachChatRequest(
            coachID: appStore.userProfile.coachType.rawValue,
            message: String(prompt.prefix(CoachChatRequest.maximumMessageCharacters)),
            context: context,
            recentMessages: []
        )
        let transmission = AITransmissionRecord(
            purpose: "\(appStore.userProfile.coachType.displayName)・計画作成",
            sharedCategories: appStore.aiSettings.dataSharing.enabledCategoryNames + ["目標", "利用可能器具", "登録種目"],
            itemCount: context.itemCount + availableExercises.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let response = try await AIAPIClient(settings: appStore.aiSettings).chat(payload: payload)
                let parsed = try AITrainingPlanDraftParser().parse(
                    reply: response.reply,
                    availableExercises: availableExercises,
                    existingPlan: currentPlan
                )
                proposal = parsed
                requestText = ""
                appStore.updateAITransmission(id: transmission.id, status: .completed)
                let newCandidates = appStore.newCoachMemoryCandidates(response.memoryCandidates)
                if !newCandidates.isEmpty {
                    memoryCandidates = newCandidates
                    isReviewingMemories = true
                }
            } catch {
                appStore.updateAITransmission(id: transmission.id, status: .failed)
                errorMessage = AIClientError.presentation(for: error).message
            }
            isGenerating = false
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
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
