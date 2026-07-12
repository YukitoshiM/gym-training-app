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
                            Label("該当する種目がありません", systemImage: "magnifyingglass")
                        } description: {
                            Text("必要な種目はカスタム種目として追加できます。")
                        } actions: {
                            Button("カスタム種目を追加") {
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
            .navigationTitle("種目を選択")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "種目名・部位・手法")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingCustomEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("カスタム種目を追加")
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
