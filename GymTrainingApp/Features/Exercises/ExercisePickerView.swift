import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let onSelect: (Exercise) -> Void

    private var filteredExercises: [Exercise] {
        guard !searchText.isEmpty else {
            return PresetExerciseStore.exercises
        }

        return PresetExerciseStore.exercises.filter {
            $0.name.localizedStandardContains(searchText)
            || $0.primaryMuscle.displayName.localizedStandardContains(searchText)
            || $0.equipment.displayName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    onSelect(exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.headline)
                        Text("\(exercise.primaryMuscle.displayName)・\(exercise.equipment.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("種目を選択")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "種目名・部位・器具")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ExercisePickerView { _ in }
}

