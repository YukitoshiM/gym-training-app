import SwiftUI

struct ExercisePickerView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup?
    @State private var selectedEquipment: Equipment?
    @State private var isShowingCustomEditor = false
    let onSelect: (Exercise) -> Void

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
        NavigationStack {
            List {
                Section {
                    ExerciseFilterView(selectedMuscle: $selectedMuscle, selectedEquipment: $selectedEquipment)
                }

                if filteredExercises.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(L10n.string("training.725a4adfc01a", fallback: "該当する種目がありません"), systemImage: "magnifyingglass")
                        } description: {
                            Text(L10n.string("training.827de2f8b16f", fallback: "必要な種目はカスタム種目として追加できます。"))
                        } actions: {
                            Button(L10n.string("training.42254297b975", fallback: "カスタム種目を追加")) {
                                isShowingCustomEditor = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ForEach(groupedExercises) { section in
                        Section(section.title) {
                            ForEach(section.exercises) { exercise in
                                Button {
                                    onSelect(exercise)
                                } label: {
                                    ExerciseSummaryRow(exercise: exercise)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("exercisePicker-\(exercise.name)")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("training.66f7a1943f08", fallback: "種目を選択"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L10n.string("training.e82a5f19c417", fallback: "種目名・部位・手法"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.2ea27dba9b9a", fallback: "閉じる")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingCustomEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.string("training.42254297b975", fallback: "カスタム種目を追加"))
                }
            }
            .sheet(isPresented: $isShowingCustomEditor) {
                CustomExerciseEditorView(initialName: searchText) { exercise in
                    onSelect(exercise)
                }
            }
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

#Preview {
    ExercisePickerView { _ in }
}
