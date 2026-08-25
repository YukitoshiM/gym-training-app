import SwiftUI

struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var draft: TrainingPlan
    @State private var isSelectingExercise = false
    @State private var isShowingAIPlanCoach = false
    @State private var isShowingValidation = false
    @FocusState private var isPlanNameFocused: Bool

    let onSaved: () -> Void
    let mode: PlanEditorMode

    private let quickTemplates = PlanTemplate.defaults
    private let setPresets = PlanSetPreset.defaults
    private let setPresetColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(
        plan: TrainingPlan?,
        mode: PlanEditorMode = .standard,
        onSaved: @escaping () -> Void = {}
    ) {
        self.onSaved = onSaved
        self.mode = mode
        _draft = State(
            initialValue: plan ?? TrainingPlan(
                name: "",
                exercises: []
            )
        )
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !draft.exercises.isEmpty
        && draft.exercises.allSatisfy { !$0.sets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .beginnerStarter || mode == .beginnerProgression {
                    Section {
                        BeginnerStarterGuide(isProgression: mode == .beginnerProgression)
                    }
                    .listRowBackground(AppTheme.accent.opacity(0.1))
                }

                Section {
                    Button {
                        isShowingAIPlanCoach = true
                    } label: {
                        HStack(spacing: 12) {
                            CoachAvatarView(
                                persona: appStore.userProfile.coachPersona,
                                size: 48,
                                cornerRadius: 8
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    draft.exercises.isEmpty
                                        ? L10n.string("training.c5ce2388abe7", fallback: "{{value1}}に作ってもらう", values: [String(describing: appStore.userProfile.coachPersona.displayName)])
                                        : L10n.string("training.380f3b3f31f1", fallback: "{{value1}}に修正を相談", values: [String(describing: appStore.userProfile.coachPersona.displayName)])
                                )
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(L10n.string("training.53da0cff7831", fallback: "目標・実績・使える器具を反映"))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("consultAIFromPlanEditorButton")
                }

                Section(L10n.string("training.29ef9e964c43", fallback: "計画名")) {
                    TextField(L10n.string("training.9ec38ed0596c", fallback: "例: 胸の日"), text: $draft.name)
                        .accessibilityIdentifier("planNameField")
                        .focused($isPlanNameFocused)
                }

                if mode == .standard {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(quickTemplates) { template in
                                    Button {
                                        applyTemplate(template)
                                    } label: {
                                        PlanTemplateChip(template: template)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("planTemplate-\(template.id)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(L10n.string("training.880aa82c0af0", fallback: "クイック作成"))
                    }

                    Section {
                        if draft.exercises.isEmpty {
                            Text(L10n.string("training.50730e3c9ce5", fallback: "種目を追加すると一括設定できます。"))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.mutedInk)
                        } else {
                            LazyVGrid(columns: setPresetColumns, spacing: 8) {
                                ForEach(setPresets) { preset in
                                    Button {
                                        applySetPreset(preset)
                                    } label: {
                                        SetPresetChip(preset: preset)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("planSetPreset-\(preset.id)")
                                }
                            }
                        }
                    } header: {
                        Text(L10n.string("training.fca5e185e9e2", fallback: "セット一括設定"))
                    }
                }

                Section {
                    if draft.exercises.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.string("training.f91b5b160025", fallback: "種目がありません"), systemImage: "dumbbell")
                        } description: {
                            Text(L10n.string("training.5e2876f45479", fallback: "種目を追加して、セットごとの目標を入力します。"))
                        }
                    } else {
                        ForEach($draft.exercises) { $planExercise in
                            PlanExerciseEditorCard(planExercise: $planExercise) {
                                removeExercise(planExercise)
                            }
                        }
                        .onMove(perform: moveExercise)
                    }

                    Button {
                        isSelectingExercise = true
                    } label: {
                        Label(L10n.string("training.131342b755f7", fallback: "種目を追加"), systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addExerciseToPlanButton")
                } header: {
                    Text(L10n.string("training.460379a71a7f", fallback: "種目"))
                } footer: {
                    Text(L10n.string("training.ecbede3ec48a", fallback: "セット目標はワークアウト開始時にコピーされ、履歴に残ります。"))
                }

            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text(saveButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .padding()
                .background(AppTheme.elevatedBackground)
                .accessibilityIdentifier("savePlanPinnedButton")
            }
            .navigationTitle(draft.name.isEmpty ? L10n.string("training.9e5c5d0f4baf", fallback: "計画作成") : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("training.0fcb170ec7cf", fallback: "保存")) {
                        save()
                    }
                    .accessibilityIdentifier("savePlanButton")
                }

                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(draft.exercises.count < 2)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.string("training.fbf5f35e5109", fallback: "入力完了")) {
                        isPlanNameFocused = false
                    }
                    .accessibilityIdentifier("dismissKeyboardButton")
                }
            }
            .sheet(isPresented: $isSelectingExercise) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                    isSelectingExercise = false
                }
            }
            .sheet(isPresented: $isShowingAIPlanCoach) {
                AIPlanCoachView(startingPlan: draft.exercises.isEmpty ? nil : draft) { revisedPlan in
                    draft = revisedPlan
                }
            }
            .alert(L10n.string("training.6689025e44d0", fallback: "保存できません"), isPresented: $isShowingValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L10n.string("training.6558f1d0f210", fallback: "計画名と1つ以上の種目を入力してください。"))
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = draft.exercises.count
        draft.exercises.append(
            PlanExercise(
                exercise: exercise,
                sortOrder: nextOrder,
                restSeconds: appStore.latestRestSeconds(for: exercise) ?? 90,
                sets: suggestedSets(for: exercise)
            )
        )
    }

    private func applyTemplate(_ template: PlanTemplate) {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = template.name
        }

        var existingNames = Set(draft.exercises.map { $0.exercise.name })
        var nextOrder = draft.exercises.count

        for exerciseName in template.exerciseNames {
            guard !existingNames.contains(exerciseName),
                  let exercise = appStore.allExercises.first(where: { $0.name == exerciseName }) else {
                continue
            }

            draft.exercises.append(
                PlanExercise(
                    exercise: exercise,
                    sortOrder: nextOrder,
                    restSeconds: appStore.latestRestSeconds(for: exercise) ?? template.restSeconds,
                    sets: suggestedSets(
                        for: exercise,
                        count: template.setCount,
                        fallbackWeight: template.targetWeight,
                        fallbackReps: template.targetReps
                    )
                )
            )
            existingNames.insert(exerciseName)
            nextOrder += 1
        }

        normalizeSortOrder()
    }

    private func suggestedSets(
        for exercise: Exercise,
        count: Int = 3,
        fallbackWeight: Double = 50,
        fallbackReps: Int = 10
    ) -> [PlanSetTarget] {
        let previousSets = appStore.latestCompletedSets(for: exercise)
        return (1...max(count, 1)).map { setOrder in
            let previous = previousSets.first { $0.setOrder == setOrder } ?? previousSets.last
            let previousWeight = previous?.actualWeight
            let weight = exercise.supportsAssistedLoad
                ? previousWeight ?? 0
                : ((previousWeight ?? 0) > 0 ? previousWeight ?? fallbackWeight : fallbackWeight)
            let reps = (previous?.actualReps ?? 0) > 0
                ? previous?.actualReps ?? fallbackReps
                : fallbackReps
            return PlanSetTarget(
                setOrder: setOrder,
                targetWeight: weight,
                targetReps: reps
            )
        }
    }

    private func applySetPreset(_ preset: PlanSetPreset) {
        for index in draft.exercises.indices {
            let currentWeight = draft.exercises[index].sets.first?.targetWeight ?? preset.targetWeight
            draft.exercises[index].sets = PlanSetTarget.quickSets(
                count: preset.setCount,
                targetWeight: currentWeight,
                targetReps: preset.targetReps
            )
        }
    }

    private func removeExercise(_ planExercise: PlanExercise) {
        draft.exercises.removeAll { $0.id == planExercise.id }
        normalizeSortOrder()
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        draft.exercises.move(fromOffsets: source, toOffset: destination)
        normalizeSortOrder()
    }

    private func normalizeSortOrder() {
        for index in draft.exercises.indices {
            draft.exercises[index].sortOrder = index
        }
    }

    private func save() {
        guard canSave else {
            isShowingValidation = true
            return
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizeSortOrder()
        appStore.savePlan(draft)
        if mode == .beginnerStarter || mode == .beginnerProgression {
            appStore.selectTodayPlan(draft.id)
        }
        onSaved()
        dismiss()
    }

    private var saveButtonTitle: String {
        switch mode {
        case .beginnerStarter:
            L10n.string("training.65d75c9e2044", fallback: "このメニューで始める")
        case .beginnerProgression:
            L10n.string("training.65f350d032fe", fallback: "このメニューを保存")
        case .aiCoach:
            L10n.string("training.9920db8c0ebb", fallback: "確認して計画を保存")
        case .standard:
            L10n.string("training.241d46d2cd02", fallback: "計画を保存")
        }
    }
}

private struct BeginnerStarterGuide: View {
    let isProgression: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(AppTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(isProgression ? L10n.string("training.c9046d518292", fallback: "目的・器具に合わせた次のレベル") : L10n.string("training.90dd341bcfdd", fallback: "LEVEL 1・全身スターター"))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text(
                    isProgression
                        ? L10n.string("training.16261933d5eb", fallback: "過去の達成状況から重量・回数を調整しています。確認して保存します。")
                        : L10n.string("training.8011c7f226da", fallback: "3種目を2セットずつ。無理のない重量に調整して保存します。")
                )
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isProgression ? "beginnerProgressionGuide" : "beginnerStarterGuide")
    }
}

private struct PlanTemplate: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let exerciseNames: [String]
    let setCount: Int
    let targetWeight: Double
    let targetReps: Int
    let restSeconds: Int

    static let defaults: [PlanTemplate] = [
        PlanTemplate(
            id: "chest",
            name: L10n.string("training.d30ca9b91ccb", fallback: "胸の日"),
            subtitle: L10n.string("training.705d0af3ec6e", fallback: "押す / 胸上部"),
            systemImage: "figure.strengthtraining.traditional",
            tint: AppTheme.accent,
            exerciseNames: [L10n.string("training.e2b5cf1b1f39", fallback: "ベンチプレス"), L10n.string("training.39029011b26a", fallback: "インクラインダンベルプレス"), L10n.string("training.e696e3ae3665", fallback: "ケーブルクロスオーバー"), L10n.string("training.2f0138ac5e92", fallback: "トライセプスプレスダウン")],
            setCount: 3,
            targetWeight: 50,
            targetReps: 10,
            restSeconds: 90
        ),
        PlanTemplate(
            id: "back",
            name: L10n.string("training.6ffb7a731dd0", fallback: "背中の日"),
            subtitle: L10n.string("training.461619512206", fallback: "引く / 厚み"),
            systemImage: "figure.pull",
            tint: AppTheme.blue,
            exerciseNames: [L10n.string("training.350f04ad1646", fallback: "ラットプルダウン"), L10n.string("training.861902f328fe", fallback: "シーテッドロー"), L10n.string("training.37679aa5c82b", fallback: "ワンハンドダンベルロー"), L10n.string("training.555c9f45a820", fallback: "フェイスプル")],
            setCount: 3,
            targetWeight: 50,
            targetReps: 10,
            restSeconds: 90
        ),
        PlanTemplate(
            id: "legs",
            name: L10n.string("training.f9b578ec8c80", fallback: "脚の日"),
            subtitle: L10n.string("training.59a002a36b66", fallback: "脚 / 臀部"),
            systemImage: "figure.walk",
            tint: AppTheme.orange,
            exerciseNames: [L10n.string("training.f0fcaf87273a", fallback: "レッグプレス"), L10n.string("training.c47e9693a5f3", fallback: "レッグカール"), L10n.string("training.bc25e5938e41", fallback: "ヒップスラスト"), L10n.string("training.d92fd6ec348c", fallback: "スタンディングカーフレイズ")],
            setCount: 3,
            targetWeight: 50,
            targetReps: 10,
            restSeconds: 120
        ),
        PlanTemplate(
            id: "shouldersArms",
            name: L10n.string("training.14f202634605", fallback: "肩・腕"),
            subtitle: L10n.string("training.0ee4231d91b6", fallback: "肩 / 二頭 / 三頭"),
            systemImage: "figure.arms.open",
            tint: AppTheme.purple,
            exerciseNames: [L10n.string("training.7a44ac818519", fallback: "ショルダープレス"), L10n.string("training.8eac181b85a5", fallback: "サイドレイズ"), L10n.string("training.c878919a9bf6", fallback: "ダンベルカール"), L10n.string("training.2f0138ac5e92", fallback: "トライセプスプレスダウン")],
            setCount: 3,
            targetWeight: 50,
            targetReps: 12,
            restSeconds: 75
        ),
        PlanTemplate(
            id: "fullBodyLight",
            name: L10n.string("training.eb204e77e96f", fallback: "全身軽め"),
            subtitle: L10n.string("training.de776f6a7f2c", fallback: "全身 / 維持"),
            systemImage: "figure.mixed.cardio",
            tint: AppTheme.accent,
            exerciseNames: [L10n.string("training.ce9fc6f5909f", fallback: "スクワット"), L10n.string("training.e2b5cf1b1f39", fallback: "ベンチプレス"), L10n.string("training.350f04ad1646", fallback: "ラットプルダウン"), L10n.string("training.7a44ac818519", fallback: "ショルダープレス")],
            setCount: 2,
            targetWeight: 50,
            targetReps: 10,
            restSeconds: 90
        )
    ]
}

private struct PlanSetPreset: Identifiable {
    let id: String
    let title: String
    let detail: String
    let setCount: Int
    let targetWeight: Double
    let targetReps: Int
    let tint: Color

    static let defaults: [PlanSetPreset] = [
        PlanSetPreset(id: "standard", title: "3x10", detail: L10n.string("training.3d3e4ad500a9", fallback: "標準"), setCount: 3, targetWeight: 50, targetReps: 10, tint: AppTheme.accent),
        PlanSetPreset(id: "hypertrophy", title: "4x8", detail: L10n.string("training.ff094202dcaa", fallback: "筋肥大"), setCount: 4, targetWeight: 50, targetReps: 8, tint: AppTheme.blue),
        PlanSetPreset(id: "strength", title: "5x5", detail: L10n.string("training.7aa2531ffa78", fallback: "高重量"), setCount: 5, targetWeight: 50, targetReps: 5, tint: AppTheme.orange),
        PlanSetPreset(id: "pump", title: "2x15", detail: L10n.string("training.56009c5efa29", fallback: "軽め"), setCount: 2, targetWeight: 50, targetReps: 15, tint: AppTheme.purple)
    ]
}

private struct PlanTemplateChip: View {
    let template: PlanTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(systemImage: template.systemImage, tint: template.tint)
                Spacer()
                Text(L10n.string("training.70d17961dda6", fallback: "{{value1}}種目", values: [String(describing: template.exerciseNames.count)]))
                    .font(.footnote.bold())
                    .foregroundStyle(template.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(template.subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(12)
        .background(template.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(template.tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SetPresetChip: View {
    let preset: PlanSetPreset

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.headline)
                .foregroundStyle(preset.tint)
                .frame(width: 30, height: 30)
                .background(preset.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(preset.detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(10)
        .background(preset.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct PlanExerciseEditorCard: View {
    @Binding var planExercise: PlanExercise
    let onDelete: () -> Void

    private let setPresets = PlanSetPreset.defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planExercise.exercise.name)
                        .font(.headline)
                    Text(L10n.string("training.82f49e5f2763", fallback: "{{value1}}・{{value2}}", values: [String(describing: planExercise.exercise.primaryMuscle.displayName), String(describing: planExercise.exercise.equipment.displayName)]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            RestSecondsInputControl(
                seconds: $planExercise.restSeconds,
                accessibilityIdentifier: "planRestSeconds-\(planExercise.sortOrder)"
            )

            Menu {
                ForEach(setPresets) { preset in
                    Button("\(preset.title) \(preset.detail)") {
                        applySetPreset(preset)
                    }
                }
            } label: {
                Label(L10n.string("training.fa6a2ef643a8", fallback: "セット構成"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("planExerciseSetMenu-\(planExercise.exercise.name)")

            VStack(spacing: 8) {
                ForEach($planExercise.sets) { $set in
                    PlanSetTargetRow(
                        set: $set,
                        exercise: planExercise.exercise,
                        exerciseSortOrder: planExercise.sortOrder
                    ) {
                        removeSet(set)
                    }
                }
            }

            if planExercise.exercise.supportsAssistedLoad {
                Label(L10n.string("training.a9ba22011245", fallback: "加算重量を入力。アシスト重量はマイナスで記録できます。"), systemImage: "plus.forwardslash.minus")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Button {
                addSet()
            } label: {
                Label(L10n.string("training.0a9240ad4b7e", fallback: "セットを追加"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("addPlanSetButton")
        }
        .padding(.vertical, 6)
    }

    private func addSet() {
        let previous = planExercise.sets.last
        planExercise.sets.append(
            PlanSetTarget(
                setOrder: planExercise.sets.count + 1,
                targetWeight: previous?.targetWeight ?? 50,
                targetReps: previous?.targetReps ?? 10,
                targetRPE: previous?.targetRPE,
                plannedConcentricSeconds: previous?.plannedConcentricSeconds,
                plannedEccentricSeconds: previous?.plannedEccentricSeconds,
                plannedTempoBeatSpeed: previous?.plannedTempoBeatSpeed
            )
        )
    }

    private func applySetPreset(_ preset: PlanSetPreset) {
        let currentWeight = planExercise.sets.first?.targetWeight ?? preset.targetWeight
        planExercise.sets = PlanSetTarget.quickSets(
            count: preset.setCount,
            targetWeight: currentWeight,
            targetReps: preset.targetReps
        )
    }

    private func removeSet(_ set: PlanSetTarget) {
        guard planExercise.sets.count > 1 else {
            return
        }

        planExercise.sets.removeAll { $0.id == set.id }
        for index in planExercise.sets.indices {
            planExercise.sets[index].setOrder = index + 1
        }
    }
}

private struct PlanSetTargetRow: View {
    @EnvironmentObject private var appStore: AppStore
    @Binding var set: PlanSetTarget
    let exercise: Exercise
    let exerciseSortOrder: Int
    let onDelete: () -> Void
    @State private var isTempoEditorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(set.setOrder)")
                    .font(.headline)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.ink.opacity(0.09), in: Circle())

                WeightInputControl(
                    weightInKilograms: $set.targetWeight,
                    unit: appStore.userProfile.weightUnit,
                    kilogramRange: exercise.weightInputRange,
                    accessibilityIdentifier: "planWeightField-\(exerciseSortOrder)-\(set.setOrder)"
                )

                RepsInputControl(
                    reps: $set.targetReps,
                    in: 1...999,
                    accessibilityIdentifier: "planRepsField-\(exerciseSortOrder)-\(set.setOrder)"
                )

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            Button {
                isTempoEditorPresented = true
            } label: {
                Label(tempoTitle, systemImage: "metronome")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("planTempoButton-\(exerciseSortOrder)-\(set.setOrder)")
        }
        .font(.subheadline)
        .sheet(isPresented: $isTempoEditorPresented) {
            PlanSetTempoEditor(set: $set)
                .presentationDetents([.height(390)])
        }
    }

    private var tempoTitle: String {
        guard let up = set.plannedConcentricSeconds,
              let down = set.plannedEccentricSeconds else {
            return L10n.string("training.8f6540106bbd", fallback: "テンポを設定")
        }
        let speed = min(3, max(1, set.plannedTempoBeatSpeed ?? 1))
        return L10n.string("training.46bd062fc9c7", fallback: "上げ {{value1}}秒・下げ {{value2}}秒・{{value3}}回/秒", values: [String(describing: up), String(describing: down), String(describing: speed)])
    }
}

private struct PlanSetTempoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var set: PlanSetTarget
    @State private var isEnabled: Bool
    @State private var concentricText: String
    @State private var eccentricText: String
    @State private var beatSpeed: Int

    init(set: Binding<PlanSetTarget>) {
        _set = set
        let current = set.wrappedValue
        _isEnabled = State(initialValue: current.plannedConcentricSeconds != nil)
        _concentricText = State(initialValue: String(current.plannedConcentricSeconds ?? 2))
        _eccentricText = State(initialValue: String(current.plannedEccentricSeconds ?? 3))
        _beatSpeed = State(initialValue: min(3, max(1, current.plannedTempoBeatSpeed ?? 1)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.string("training.36467fec4916", fallback: "触覚でテンポを案内"), isOn: $isEnabled)
                        .accessibilityIdentifier("planTempoEnabled")
                } footer: {
                    Text(L10n.string("training.4343c0de2bfd", fallback: "Apple Watchが設定した上げ・下げ時間を、1秒あたり1〜3回の触覚で案内します。"))
                }

                if isEnabled {
                    Section(L10n.string("training.965f9a854c19", fallback: "1回の動作")) {
                        NumericTextInputControl(
                            text: $concentricText,
                            title: L10n.string("training.3c0d51bbe730", fallback: "上げ"),
                            unit: L10n.string("training.b1d936d15858", fallback: "秒"),
                            range: 1...10,
                            step: 1,
                            defaultValue: 2,
                            accessibilityIdentifier: "planConcentricSeconds"
                        )
                        Picker(L10n.string("training.6532391678cf", fallback: "振動速度"), selection: $beatSpeed) {
                            ForEach(1...3, id: \.self) { value in
                                Text(L10n.string("training.4d980bac73d4", fallback: "{{value1}}回/秒", values: [String(describing: value)])).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("planTempoBeatSpeed")
                        NumericTextInputControl(
                            text: $eccentricText,
                            title: L10n.string("training.4befe1f9a87c", fallback: "下げ"),
                            unit: L10n.string("training.b1d936d15858", fallback: "秒"),
                            range: 1...10,
                            step: 1,
                            defaultValue: 3,
                            accessibilityIdentifier: "planEccentricSeconds"
                        )
                    }
                }
            }
            .navigationTitle(L10n.string("training.84c7d164b06b", fallback: "動作テンポ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("training.0fcb170ec7cf", fallback: "保存")) {
                        if isEnabled {
                            set.plannedConcentricSeconds = parsed(concentricText, fallback: 2)
                            set.plannedEccentricSeconds = parsed(eccentricText, fallback: 3)
                            set.plannedTempoBeatSpeed = beatSpeed
                        } else {
                            set.plannedConcentricSeconds = nil
                            set.plannedEccentricSeconds = nil
                            set.plannedTempoBeatSpeed = nil
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("savePlanTempoButton")
                }
            }
        }
    }

    private func parsed(_ text: String, fallback: Int) -> Int {
        min(10, max(1, Int(Double(text.replacingOccurrences(of: ",", with: ".")) ?? Double(fallback))))
    }
}

private extension PlanSetTarget {
    static func quickSets(count: Int, targetWeight: Double, targetReps: Int) -> [PlanSetTarget] {
        (1...max(count, 1)).map {
            PlanSetTarget(setOrder: $0, targetWeight: targetWeight, targetReps: targetReps)
        }
    }
}

#Preview {
    PlanEditorView(plan: nil)
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
