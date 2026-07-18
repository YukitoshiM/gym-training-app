import SwiftUI

struct PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var draft: TrainingPlan
    @State private var isSelectingExercise = false
    @State private var isShowingValidation = false
    @FocusState private var isPlanNameFocused: Bool

    let onSaved: () -> Void

    private let quickTemplates = PlanTemplate.defaults
    private let setPresets = PlanSetPreset.defaults
    private let setPresetColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(plan: TrainingPlan?, onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
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
                Section("計画名") {
                    TextField("例: 胸の日", text: $draft.name)
                        .accessibilityIdentifier("planNameField")
                        .focused($isPlanNameFocused)
                }

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
                    Text("クイック作成")
                }

                Section {
                    if draft.exercises.isEmpty {
                        Text("種目を追加すると一括設定できます。")
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
                    Text("セット一括設定")
                }

                Section {
                    if draft.exercises.isEmpty {
                        ContentUnavailableView {
                            Label("種目がありません", systemImage: "dumbbell")
                        } description: {
                            Text("種目を追加して、セットごとの目標を入力します。")
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
                        Label("種目を追加", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addExerciseToPlanButton")
                } header: {
                    Text("種目")
                } footer: {
                    Text("セット目標はワークアウト開始時にコピーされ、履歴に残ります。")
                }

            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text("計画を保存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .padding()
                .background(AppTheme.elevatedBackground)
                .accessibilityIdentifier("savePlanPinnedButton")
            }
            .navigationTitle(draft.name.isEmpty ? "計画作成" : draft.name)
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
                    .accessibilityIdentifier("savePlanButton")
                }

                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(draft.exercises.count < 2)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("入力完了") {
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
            .alert("保存できません", isPresented: $isShowingValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("計画名と1つ以上の種目を入力してください。")
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let nextOrder = draft.exercises.count
        draft.exercises.append(
            PlanExercise(
                exercise: exercise,
                sortOrder: nextOrder
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
                    restSeconds: template.restSeconds,
                    sets: PlanSetTarget.quickSets(
                        count: template.setCount,
                        targetWeight: template.targetWeight,
                        targetReps: template.targetReps
                    )
                )
            )
            existingNames.insert(exerciseName)
            nextOrder += 1
        }

        normalizeSortOrder()
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
        onSaved()
        dismiss()
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
            name: "胸の日",
            subtitle: "押す / 胸上部",
            systemImage: "figure.strengthtraining.traditional",
            tint: AppTheme.accent,
            exerciseNames: ["ベンチプレス", "インクラインダンベルプレス", "ケーブルクロスオーバー", "トライセプスプレスダウン"],
            setCount: 3,
            targetWeight: 20,
            targetReps: 10,
            restSeconds: 90
        ),
        PlanTemplate(
            id: "back",
            name: "背中の日",
            subtitle: "引く / 厚み",
            systemImage: "figure.pull",
            tint: AppTheme.blue,
            exerciseNames: ["ラットプルダウン", "シーテッドロー", "ワンハンドダンベルロー", "フェイスプル"],
            setCount: 3,
            targetWeight: 20,
            targetReps: 10,
            restSeconds: 90
        ),
        PlanTemplate(
            id: "legs",
            name: "脚の日",
            subtitle: "脚 / 臀部",
            systemImage: "figure.walk",
            tint: AppTheme.orange,
            exerciseNames: ["レッグプレス", "レッグカール", "ヒップスラスト", "スタンディングカーフレイズ"],
            setCount: 3,
            targetWeight: 20,
            targetReps: 10,
            restSeconds: 120
        ),
        PlanTemplate(
            id: "shouldersArms",
            name: "肩・腕",
            subtitle: "肩 / 二頭 / 三頭",
            systemImage: "figure.arms.open",
            tint: AppTheme.purple,
            exerciseNames: ["ショルダープレス", "サイドレイズ", "ダンベルカール", "トライセプスプレスダウン"],
            setCount: 3,
            targetWeight: 15,
            targetReps: 12,
            restSeconds: 75
        ),
        PlanTemplate(
            id: "fullBodyLight",
            name: "全身軽め",
            subtitle: "全身 / 維持",
            systemImage: "figure.mixed.cardio",
            tint: AppTheme.accent,
            exerciseNames: ["スクワット", "ベンチプレス", "ラットプルダウン", "ショルダープレス"],
            setCount: 2,
            targetWeight: 20,
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
        PlanSetPreset(id: "standard", title: "3x10", detail: "標準", setCount: 3, targetWeight: 20, targetReps: 10, tint: AppTheme.accent),
        PlanSetPreset(id: "hypertrophy", title: "4x8", detail: "筋肥大", setCount: 4, targetWeight: 20, targetReps: 8, tint: AppTheme.blue),
        PlanSetPreset(id: "strength", title: "5x5", detail: "高重量", setCount: 5, targetWeight: 20, targetReps: 5, tint: AppTheme.orange),
        PlanSetPreset(id: "pump", title: "2x15", detail: "軽め", setCount: 2, targetWeight: 20, targetReps: 15, tint: AppTheme.purple)
    ]
}

private struct PlanTemplateChip: View {
    let template: PlanTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(systemImage: template.systemImage, tint: template.tint)
                Spacer()
                Text("\(template.exerciseNames.count)種目")
                    .font(.caption.bold())
                    .foregroundStyle(template.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(template.subtitle)
                    .font(.caption)
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
                    .font(.caption)
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
                    Text("\(planExercise.exercise.primaryMuscle.displayName)・\(planExercise.exercise.equipment.displayName)")
                        .font(.caption)
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
                Label("セット構成", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("planExerciseSetMenu-\(planExercise.exercise.name)")

            VStack(spacing: 8) {
                ForEach($planExercise.sets) { $set in
                    PlanSetTargetRow(
                        set: $set,
                        exerciseSortOrder: planExercise.sortOrder
                    ) {
                        removeSet(set)
                    }
                }
            }

            Button {
                addSet()
            } label: {
                Label("セットを追加", systemImage: "plus")
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
                targetWeight: previous?.targetWeight ?? 20,
                targetReps: previous?.targetReps ?? 10
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
    let exerciseSortOrder: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.setOrder)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(AppTheme.ink.opacity(0.09), in: Circle())

            WeightInputControl(
                weightInKilograms: $set.targetWeight,
                unit: appStore.userProfile.weightUnit,
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
        .font(.subheadline)
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
}
