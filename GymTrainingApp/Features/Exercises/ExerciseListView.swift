import SwiftUI

struct ExerciseListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var searchText = ""
    @State private var isShowingCustomEditor = false
    @State private var selectedMuscle: MuscleGroup?
    @State private var selectedEquipment: Equipment?
    private let embedsInNavigationStack: Bool

    init(embedsInNavigationStack: Bool = true) {
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    private var filteredExercises: [Exercise] {
        appStore.allExercises.filter { exercise in
            exercise.matches(muscle: selectedMuscle)
            && exercise.matches(equipment: selectedEquipment)
            && matchesSearch(exercise)
        }
    }

    private var groupedExercises: [ExerciseSection] {
        filteredExercises.groupedForExerciseFilter(selectedMuscle: selectedMuscle)
    }

    var body: some View {
        if embedsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                ExerciseFilterView(selectedMuscle: $selectedMuscle, selectedEquipment: $selectedEquipment)
            }

            if filteredExercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(L10n.string("training.725a4adfc01a", fallback: "該当する種目がありません"), systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.string("training.4ec785b46677", fallback: "右上の追加ボタンからカスタム種目を登録できます。"))
                    }
                }
            } else {
                ForEach(groupedExercises) { group in
                        Section(group.title) {
                            ForEach(group.exercises) { exercise in
                                NavigationLink {
                                    ExerciseDetailView(exercise: exercise)
                                } label: {
                                    ExerciseSummaryRow(exercise: exercise)
                                }
                                .accessibilityIdentifier("exerciseDetailLink-\(exercise.name)")
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("training.460379a71a7f", fallback: "種目"))
        .searchable(text: $searchText, prompt: L10n.string("training.e82a5f19c417", fallback: "種目名・部位・手法"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCustomEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.string("training.42254297b975", fallback: "カスタム種目を追加"))
                .accessibilityIdentifier("addCustomExerciseButton")
            }
        }
        .sheet(isPresented: $isShowingCustomEditor) {
            CustomExerciseEditorView(initialName: searchText)
        }
    }

    private func matchesSearch(_ exercise: Exercise) -> Bool {
        guard !searchText.isEmpty else {
            return true
        }

        return exercise.name.localizedStandardContains(searchText)
        || exercise.primaryMuscle.displayName.localizedStandardContains(searchText)
        || exercise.secondaryMuscles.map(\.displayName).joined(separator: " ").localizedStandardContains(searchText)
        || exercise.equipment.displayName.localizedStandardContains(searchText)
    }
}

struct ExerciseSummaryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExercisePhotoCropView(exercise: exercise)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name)
                    .font(.headline)

                HStack(spacing: 10) {
                    Label(exercise.primaryMuscle.displayName, systemImage: exercise.primaryMuscle.systemImage)
                    Label(exercise.equipment.displayName, systemImage: exercise.equipment.systemImage)
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseSection: Identifiable {
    let title: String
    let exercises: [Exercise]
    let sortOrder: Int

    var id: String { title }
}

extension Array where Element == Exercise {
    func sortedByName() -> [Exercise] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func groupedForExerciseFilter(selectedMuscle: MuscleGroup?) -> [ExerciseSection] {
        if selectedMuscle == nil {
            let order = Dictionary(uniqueKeysWithValues: MuscleGroup.selectionCases.enumerated().map { ($0.element, $0.offset) })
            return Dictionary(grouping: self, by: \.primaryMuscle)
                .map { muscle, exercises in
                    ExerciseSection(
                        title: muscle.displayName,
                        exercises: exercises.sortedByName(),
                        sortOrder: order[muscle] ?? Int.max
                    )
                }
                .sortedBySectionOrder()
        }

        let order = Dictionary(uniqueKeysWithValues: Equipment.allCases.enumerated().map { ($0.element, $0.offset) })
        return Dictionary(grouping: self, by: \.equipment)
            .map { equipment, exercises in
                ExerciseSection(
                    title: equipment.displayName,
                    exercises: exercises.sortedByName(),
                    sortOrder: order[equipment] ?? Int.max
                )
            }
            .sortedBySectionOrder()
    }
}

private extension Array where Element == ExerciseSection {
    func sortedBySectionOrder() -> [ExerciseSection] {
        sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

            return $0.sortOrder < $1.sortOrder
        }
    }
}

#Preview {
    ExerciseListView()
        .environmentObject(AppStore())
}
